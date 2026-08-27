// Situação da unidade AGORA, no fuso dela — e a agenda que decide o dia.
//
// O backend não tem `open_now?` de propósito (o horário da unidade é informativo, ver
// UnitWorkingHour): quem responde "aberta agora" é esta tela, e cada unidade responde
// no próprio fuso — a filial de Cuiabá abre uma hora depois da de São Paulo.
//
// A regra de agenda (feriado, evento, temporada) SUBSTITUI a linha da semana no dia em
// que cai. É assim que ela fecha um feriado e é assim que ela ABRE um domingo que a
// grade fecha: basta ter faixa própria.

import {
  differenceInCalendarWeeks,
  differenceInCalendarMonths,
  lastDayOfMonth,
} from 'date-fns';

const DIAS = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };

const doisDigitos = valor => String(valor).padStart(2, '0');

// Meio-dia de propósito: data construída à meia-noite pode escorregar um dia em fuso
// com horário de verão que vira à meia-noite.
const comoData = texto => {
  const [ano, mes, dia] = texto.split('-').map(Number);
  return new Date(ano, mes - 1, dia, 12);
};

export const comoTextoISO = data =>
  `${data.getFullYear()}-${doisDigitos(data.getMonth() + 1)}-${doisDigitos(data.getDate())}`;

// Data/hora de referência no fuso da unidade — não no fuso de quem está olhando.
// `referencia` entra por parâmetro para a tela poder reavaliar a cada minuto: é o
// relógio que muda "aberta" para "fechada", não a unidade.
export const agoraNaUnidade = (timezone, referencia = new Date()) => {
  const partes = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      weekday: 'short',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    })
      .formatToParts(referencia)
      .map(parte => [parte.type, parte.value])
  );

  return {
    dia: DIAS[partes.weekday],
    ano: Number(partes.year),
    mes: Number(partes.month),
    diaDoMes: Number(partes.day),
    minutos: Number(partes.hour) * 60 + Number(partes.minute),
    hora: `${partes.hour}:${partes.minute}`,
    data: new Date(
      Number(partes.year),
      Number(partes.month) - 1,
      Number(partes.day),
      12
    ),
  };
};

// --- a regra cai neste dia? --------------------------------------------------------

const dentroDaJanela = (regra, data) => {
  if (data < comoData(regra.starts_on)) return false;
  return !regra.until_date || data <= comoData(regra.until_date);
};

const posicaoNoMes = data => Math.ceil(data.getDate() / 7);

const ehUltimaSemana = data =>
  data.getDate() > lastDayOfMonth(data).getDate() - 7;

const ehUltimoDia = data => data.getDate() === lastDayOfMonth(data).getDate();

// Um período (`ends_on`) é a duração de uma regra que não repete — as férias coletivas
// de 20/12 a 05/01 numa linha só, em vez de dezessete.
const casaPeriodo = (regra, data) => {
  const fim = regra.ends_on
    ? comoData(regra.ends_on)
    : comoData(regra.starts_on);
  return data <= fim;
};

const casaSemanal = (regra, data) => {
  if (!regra.weekdays.includes(data.getDay())) return false;
  const semanas = differenceInCalendarWeeks(data, comoData(regra.starts_on));
  return semanas % regra.repeat_interval === 0;
};

// Mensal tem duas formas: pelo dia do mês ("todo dia 10") ou pela posição do dia da
// semana ("1º e 3º domingo") — é esta segunda que o Google Agenda chama de mensal.
const casaMensal = (regra, data) => {
  const meses = differenceInCalendarMonths(data, comoData(regra.starts_on));
  if (meses % regra.repeat_interval !== 0) return false;

  if (regra.month_days.length) {
    return (
      regra.month_days.includes(data.getDate()) ||
      (regra.month_days.includes(-1) && ehUltimoDia(data))
    );
  }

  if (!regra.weekdays.includes(data.getDay())) return false;
  return (
    regra.week_positions.includes(posicaoNoMes(data)) ||
    (regra.week_positions.includes(-1) && ehUltimaSemana(data))
  );
};

const casaAnual = (regra, data) => {
  const inicio = comoData(regra.starts_on);
  return (
    (data.getFullYear() - inicio.getFullYear()) % regra.repeat_interval === 0 &&
    data.getMonth() === inicio.getMonth() &&
    data.getDate() === inicio.getDate()
  );
};

export const regraValeNoDia = (regra, data) => {
  if (!dentroDaJanela(regra, data)) return false;

  switch (regra.frequency) {
    case 'semanal':
      return casaSemanal(regra, data);
    case 'mensal':
      return casaMensal(regra, data);
    case 'anual':
      return casaAnual(regra, data);
    default:
      return casaPeriodo(regra, data);
  }
};

// --- precedência: qual regra manda no dia ------------------------------------------

// Da mais específica para a mais genérica. Vai escrito na tela, não escondido aqui.
const ESPECIFICIDADE = { nao_repete: 0, mensal: 2, semanal: 3, anual: 4 };

const especificidade = regra => {
  if (regra.frequency === 'nao_repete') return regra.ends_on ? 1 : 0;
  return ESPECIFICIDADE[regra.frequency] ?? 9;
};

export const regraDoDia = (unit, data) => {
  const candidatas = (unit.exceptions || []).filter(regra =>
    regraValeNoDia(regra, data)
  );
  if (!candidatas.length) return null;

  // Empate na especificidade: vence a que FECHA. Nunca prometer ao cliente que a
  // filial está aberta.
  return [...candidatas].sort(
    (a, b) =>
      especificidade(a) - especificidade(b) ||
      Number(b.closed_all_day) - Number(a.closed_all_day)
  )[0];
};

const regraDeHoje = (unit, momento) =>
  regraDoDia(unit, momento.data) ||
  (unit.working_hours || []).find(hora => hora.day_of_week === momento.dia);

// --- prévia das próximas datas -----------------------------------------------------

const TETO_DE_DIAS = 1200; // ~3 anos: cobre até "a cada 3 anos" sem varrer o infinito

export const proximasOcorrencias = (
  regra,
  quantas = 4,
  apartirDe = new Date()
) => {
  if (!regra?.starts_on) return [];

  const inicio = comoData(regra.starts_on);
  const cursor = apartirDe > inicio ? new Date(apartirDe) : inicio;
  cursor.setHours(12, 0, 0, 0);

  const achadas = [];
  for (
    let passo = 0;
    passo < TETO_DE_DIAS && achadas.length < quantas;
    passo += 1
  ) {
    if (regraValeNoDia(regra, cursor)) achadas.push(new Date(cursor));
    cursor.setDate(cursor.getDate() + 1);
  }
  return achadas;
};

// "Termina após N ocorrências" não é coluna no banco: a tela converte em data-limite
// na hora de salvar, e a avaliação só precisa olhar `until_date`.
export const dataDaEnesimaOcorrencia = (regra, n) => {
  const ocorrencias = proximasOcorrencias(
    { ...regra, until_date: null },
    n,
    comoData(regra.starts_on)
  );
  return ocorrencias.length === n ? comoTextoISO(ocorrencias[n - 1]) : '';
};

// --- leitura -----------------------------------------------------------------------

const temPausa = regra =>
  regra?.break_start_hour !== null && regra?.break_start_hour !== undefined;

const hhmm = (hora, minuto) => `${doisDigitos(hora)}:${doisDigitos(minuto)}`;

// Minutos desde a meia-noite, para comparar o relógio com a faixa.
const minutosDe = (hora, minuto) => hora * 60 + minuto;

const dentroDaPausa = (regra, minutos) =>
  temPausa(regra) &&
  minutos >= minutosDe(regra.break_start_hour, regra.break_start_minutes) &&
  minutos < minutosDe(regra.break_end_hour, regra.break_end_minutes);

// Com parada para o almoço a faixa vira duas: "08:00 – 12:00 · 13:30 – 18:00".
export const faixaLegivel = regra => {
  if (!regra || regra.closed_all_day) return '';
  if (regra.open_all_day) return '24h';

  const abertura = hhmm(regra.open_hour, regra.open_minutes);
  const fechamento = hhmm(regra.close_hour, regra.close_minutes);
  if (!temPausa(regra)) return `${abertura} – ${fechamento}`;

  const inicioDaPausa = hhmm(regra.break_start_hour, regra.break_start_minutes);
  const fimDaPausa = hhmm(regra.break_end_hour, regra.break_end_minutes);
  return `${abertura} – ${inicioDaPausa} · ${fimDaPausa} – ${fechamento}`;
};

export const situacaoDaUnidade = (unit, referencia = new Date()) => {
  const momento = agoraNaUnidade(unit.timezone, referencia);
  const regra = regraDeHoje(unit, momento);
  const naPausa = dentroDaPausa(regra, momento.minutos);
  const aberta =
    !!regra &&
    !regra.closed_all_day &&
    !naPausa &&
    (regra.open_all_day ||
      (momento.minutos >= minutosDe(regra.open_hour, regra.open_minutes) &&
        momento.minutos < minutosDe(regra.close_hour, regra.close_minutes)));

  return {
    aberta,
    horaLocal: momento.hora,
    faixa: faixaLegivel(regra),
    // Fechada por causa do almoço não é fechada pelo dia: a tela diz a que horas volta.
    voltaAs: naPausa ? hhmm(regra.break_end_hour, regra.break_end_minutes) : '',
    // Só regra de agenda tem nome e categoria: é o que a lista mostra para explicar um
    // "fechada" fora do padrão da semana.
    excecao: regra?.name || '',
    categoria: regra?.category || '',
  };
};

export const dataLegivel = data => data.split('-').reverse().join('/');
