// Ajudantes PUROS do formulário de unidade. Moram fora do .vue para poderem ser testados sem montar
// a tela — mesmo caminho do unitSchedule.js ao lado.

// 78550041, 78550-041 ou 78.550-041 dão no mesmo: fica só o dígito, no máximo 8, com o traço depois do
// quinto. A busca no ViaCEP já removia tudo que não é dígito, então ela não muda.
export const formatarCep = valor => {
  const digitos = (valor || '').replace(/\D/g, '').slice(0, 8);
  return digitos.length > 5
    ? `${digitos.slice(0, 5)}-${digitos.slice(5)}`
    : digitos;
};

// Segunda a sexta costuma ser tudo igual: preenche um dia, copia, e ajusta só o que foge. Copia para
// os dias ABERTOS — fim de semana fechado continua fechado. Devolve a grade nova e quantos dias mudaram.
export const copiarHorarioParaDias = (slots, origem) => {
  let copiados = 0;
  const novos = slots.map(item => {
    if (item.day === origem.day || !item.from || !item.to) return item;

    copiados += 1;
    return {
      ...item,
      from: origem.from,
      to: origem.to,
      breakFrom: origem.breakFrom,
      breakTo: origem.breakTo,
      openAllDay: origem.openAllDay,
      valid: origem.valid,
    };
  });

  return { slots: novos, copiados };
};
