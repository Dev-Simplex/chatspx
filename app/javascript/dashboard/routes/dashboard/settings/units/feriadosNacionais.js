// Feriados nacionais brasileiros — o que todo calendário de unidade tem e ninguém
// devia ter que digitar filial por filial.
//
// Nove são de DATA FIXA (25/12 é sempre 25/12) e viram uma regra ANUAL: uma linha só,
// que vale deste ano em diante sem recadastro. Três andam com a Páscoa — Carnaval,
// Sexta-feira Santa e Corpus Christi — e data móvel não cabe em "todo ano no dia tal":
// cada ano vira uma linha própria, calculada aqui. Daí o horizonte de ANOS: quem
// clicar de novo lá na frente completa o que faltar, porque o que já está marcado é
// pulado.
//
// Carnaval e Corpus Christi são ponto facultativo, não feriado por lei — entram porque
// o comércio fecha, e a linha some num clique para quem abre.

import {
  comoTextoISO,
  proximasOcorrencias,
  regraValeNoDia,
} from './unitSchedule';

// Anos de datas móveis geradas de uma vez. Cinco cobre a vida útil de um cadastro sem
// encher a lista: são três linhas por ano.
const ANOS = 5;

// [mês, dia, nome] — as datas fixas, na ordem do ano.
const FIXOS = [
  [1, 1, 'Confraternização Universal'],
  [4, 21, 'Tiradentes'],
  [5, 1, 'Dia do Trabalho'],
  [9, 7, 'Independência do Brasil'],
  [10, 12, 'Nossa Senhora Aparecida'],
  [11, 2, 'Finados'],
  [11, 15, 'Proclamação da República'],
  [11, 20, 'Consciência Negra'],
  [12, 25, 'Natal'],
];

// [dias a partir do Domingo de Páscoa, nome] — é o que faz a data móvel ser móvel.
const MOVEIS = [
  [-47, 'Carnaval'],
  [-2, 'Sexta-feira Santa'],
  [60, 'Corpus Christi'],
];

// O que a regra de feriado tem de igual em todas: fecha o dia inteiro, não repete por
// semana nem por mês, não avisa ninguém. O resto (nome, data, frequência) entra depois.
const REGRA_BASE = {
  category: 'feriado',
  closed_all_day: true,
  ends_on: null,
  repeat_interval: 1,
  weekdays: [],
  week_positions: [],
  month_days: [],
  until_date: null,
  reminder_days_before: null,
  open_hour: null,
  open_minutes: null,
  close_hour: null,
  close_minutes: null,
};

// Meio-dia pelo mesmo motivo do unitSchedule: data à meia-noite escorrega um dia em
// fuso que vira o horário de verão à meia-noite.
const aoMeioDia = (ano, mes, dia) => new Date(ano, mes - 1, dia, 12);

// Domingo de Páscoa pelo algoritmo de Meeus/Butcher (calendário gregoriano). É dele que
// saem as três datas móveis, e é a única conta desta tela que não dá para ler no banco.
const domingoDePascoa = ano => {
  const a = ano % 19;
  const b = Math.floor(ano / 100);
  const c = ano % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const dias = h + l - 7 * m + 114;
  return aoMeioDia(ano, Math.floor(dias / 31), (dias % 31) + 1);
};

const comDeslocamento = (data, dias) => {
  const movida = new Date(data);
  movida.setDate(data.getDate() + dias);
  return movida;
};

const regraFixa = (ano, [mes, dia, name]) => ({
  ...REGRA_BASE,
  name,
  frequency: 'anual',
  starts_on: comoTextoISO(aoMeioDia(ano, mes, dia)),
});

const regraMovel = (data, name) => ({
  ...REGRA_BASE,
  name,
  frequency: 'nao_repete',
  starts_on: comoTextoISO(data),
});

// As regras de feriado nacional que caberiam nesta unidade, gravadas ou não.
//
// A data fixa começa no ano corrente mesmo que já tenha passado: a regra anual só vale
// de `starts_on` em diante, então o 1º de janeiro passado não polui o calendário e o
// que ainda vem neste ano (12/10, 25/12) já aparece marcado. A móvel que passou não
// entra — seria linha morta na lista.
export const feriadosNacionais = (hoje = new Date()) => {
  const ano = hoje.getFullYear();
  const referencia = aoMeioDia(
    hoje.getFullYear(),
    hoje.getMonth() + 1,
    hoje.getDate()
  );

  const moveis = [];
  for (let passo = 0; passo < ANOS; passo += 1) {
    const pascoa = domingoDePascoa(ano + passo);
    MOVEIS.forEach(([deslocamento, name]) => {
      const data = comDeslocamento(pascoa, deslocamento);
      if (data >= referencia) moveis.push(regraMovel(data, name));
    });
  }

  return [...FIXOS.map(fixo => regraFixa(ano, fixo)), ...moveis];
};

// Dia que já é feriado não ganha um segundo feriado em cima: nem o que o admin marcou à
// mão ("Natal"), nem o do clique anterior neste botão. A comparação é pela PRÓXIMA data
// em que a regra cai — é o que distingue a regra anual de 25/12 de uma de 26/12 — e só
// olha regras da categoria feriado, para um expediente especial de sexta-feira não
// engolir a Sexta-feira Santa.
const jaMarcado = (regras, candidata, hoje) => {
  const [proxima] = proximasOcorrencias(candidata, 1, hoje);
  if (!proxima) return true;

  return regras.some(
    regra => regra.category === 'feriado' && regraValeNoDia(regra, proxima)
  );
};

// O que falta marcar — é isto que a tela adiciona à lista de regras da unidade.
export const feriadosQueFaltam = (regras = [], hoje = new Date()) =>
  feriadosNacionais(hoje).reduce((faltando, candidata) => {
    const marcadas = [...regras, ...faltando];
    return jaMarcado(marcadas, candidata, hoje)
      ? faltando
      : [...faltando, candidata];
  }, []);
