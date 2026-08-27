// Situação da unidade AGORA, no fuso dela.
//
// O backend não tem `open_now?` de propósito (o horário da unidade é informativo, ver
// UnitWorkingHour): quem responde "aberta agora" é esta tela, e cada unidade responde
// no próprio fuso — a filial de Cuiabá abre uma hora depois da de São Paulo.

const DIAS = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };

const doisDigitos = valor => String(valor).padStart(2, '0');

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
  };
};

// Exceção "todo ano" ignora o ano cadastrado: 25/12 vale para sempre.
const casaComADataDeHoje = (excecao, { ano, mes, diaDoMes }) => {
  const [anoDela, mesDela, diaDela] = excecao.date.split('-').map(Number);
  return (
    mesDela === mes &&
    diaDela === diaDoMes &&
    (excecao.annual || anoDela === ano)
  );
};

// A exceção do dia SUBSTITUI a linha da semana — é para isso que ela existe.
const regraDeHoje = (unit, momento) =>
  (unit.exceptions || []).find(excecao =>
    casaComADataDeHoje(excecao, momento)
  ) ||
  (unit.working_hours || []).find(hora => hora.day_of_week === momento.dia);

export const faixaLegivel = regra => {
  if (!regra || regra.closed_all_day) return '';
  if (regra.open_all_day) return '24h';
  return `${doisDigitos(regra.open_hour)}:${doisDigitos(regra.open_minutes)} – ${doisDigitos(regra.close_hour)}:${doisDigitos(regra.close_minutes)}`;
};

export const situacaoDaUnidade = (unit, referencia = new Date()) => {
  const momento = agoraNaUnidade(unit.timezone, referencia);
  const regra = regraDeHoje(unit, momento);
  const aberta =
    !!regra &&
    !regra.closed_all_day &&
    (regra.open_all_day ||
      (momento.minutos >= regra.open_hour * 60 + regra.open_minutes &&
        momento.minutos < regra.close_hour * 60 + regra.close_minutes));

  return {
    aberta,
    horaLocal: momento.hora,
    faixa: faixaLegivel(regra),
    // Só exceção tem nome: é o que a lista mostra para explicar um "fechada" fora do padrão.
    excecao: regra?.name || '',
  };
};

export const dataLegivel = data => data.split('-').reverse().join('/');
