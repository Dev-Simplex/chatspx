// A cor da espera do lead. Usa o MESMO limite do cartão "Sem movimento" (os minutos para pegar
// da política; 30 quando não há) — nenhuma regra nova:
//   verde    — alguém pegou dentro do limite
//   amarelo  — ainda esperando, mas dentro do limite
//   vermelho — passou do limite (esperando ou não), ou expirou sem ninguém pegar
// A legenda da página e o cartão leem daqui, para a cor nunca dizer uma coisa num e outra no outro.

export const FAIXAS = {
  ok: {
    selo: 'bg-n-teal-3 text-n-teal-11',
    barra: 'bg-n-teal-9',
    texto: 'text-n-teal-11',
    borda: 'border-n-teal-9',
  },
  atencao: {
    selo: 'bg-n-amber-3 text-n-amber-11',
    barra: 'bg-n-amber-9',
    texto: 'text-n-amber-11',
    borda: 'border-n-amber-9',
  },
  atrasado: {
    selo: 'bg-n-ruby-3 text-n-ruby-11',
    barra: 'bg-n-ruby-9',
    texto: 'text-n-ruby-11',
    borda: 'border-n-ruby-9',
  },
};

export const faixaDaEspera = ({
  segundos,
  limiar,
  aindaEsperando,
  perdido,
}) => {
  if (perdido || segundos > limiar * 60) return FAIXAS.atrasado;
  return aindaEsperando ? FAIXAS.atencao : FAIXAS.ok;
};
