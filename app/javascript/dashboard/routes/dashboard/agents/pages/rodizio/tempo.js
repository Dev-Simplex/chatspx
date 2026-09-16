// Como o Rodízio escreve duração e instante. Mora fora das telas porque a faixa por consultor,
// a aba de leads e o cabeçalho precisam escrever a MESMA coisa do mesmo jeito.
//
// Formatador próprio em vez do `formatTime` dos relatórios: aquele arredonda 1h50 para "1h", e
// numa tela em que a diferença entre 2 min e 38 min é o assunto, isso apaga o dado.

export const duracao = (t, segundos) => {
  const total = Math.round(segundos || 0);
  if (total < 60) return t('AGENTS_RODIZIO.TIMELINE.SECONDS', { n: total });

  const minutos = Math.floor(total / 60);
  if (minutos < 60) return t('AGENTS_RODIZIO.TIMELINE.MINUTES', { n: minutos });

  const horas = Math.floor(minutos / 60);
  const resto = minutos % 60;
  if (horas < 24) {
    // Minuto com zero à esquerda: "1h06", não "1h6".
    return resto
      ? t('AGENTS_RODIZIO.TIMELINE.HOURS_MINUTES', {
          h: horas,
          m: String(resto).padStart(2, '0'),
        })
      : t('AGENTS_RODIZIO.TIMELINE.HOURS', { n: horas });
  }

  const dias = Math.floor(horas / 24);
  const restoHoras = horas % 24;
  return restoHoras
    ? t('AGENTS_RODIZIO.TIMELINE.DAYS_HOURS', { d: dias, h: restoHoras })
    : t('AGENTS_RODIZIO.TIMELINE.DAYS', { n: dias });
};

// Instante curto: se é de hoje, só a hora; se é de outro dia, dia/mês e hora. Seis marcos com
// data completa viram ruído.
export const instante = valor => {
  if (!valor) return '—';

  const quando = new Date(valor);
  const relogio = { hour: '2-digit', minute: '2-digit' };
  return quando.toDateString() === new Date().toDateString()
    ? quando.toLocaleTimeString([], relogio)
    : quando.toLocaleString([], {
        day: '2-digit',
        month: '2-digit',
        ...relogio,
      });
};
