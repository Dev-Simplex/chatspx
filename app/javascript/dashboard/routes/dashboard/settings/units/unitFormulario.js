// Ajudantes PUROS do formulário de unidade. Moram fora do .vue para poderem ser testados sem montar
// a tela — mesmo caminho do unitSchedule.js ao lado.

// 78550041, 78550-041 ou 78.550-041 dão no mesmo: fica só o dígito, no máximo 8, escrito como o CEP
// é escrito — ponto depois do segundo, traço depois do quinto. A busca no ViaCEP já removia tudo que
// não é dígito, então ela não muda.
export const formatarCep = valor => {
  const digitos = (valor || '').replace(/\D/g, '').slice(0, 8);
  const inicio =
    digitos.length > 2
      ? `${digitos.slice(0, 2)}.${digitos.slice(2, 5)}`
      : digitos;

  return digitos.length > 5 ? `${inicio}-${digitos.slice(5)}` : inicio;
};

// Telefone da filial: o parêntese e o traço aparecem enquanto se digita, como no CEP. Fixo fica
// (66) 3531-0000 e celular (66) 99999-9999 — quem manda é a quantidade de dígitos, não um seletor.
// Número colado com o 55 na frente perde o 55 em vez de perder os dois últimos dígitos no corte.
export const formatarTelefone = valor => {
  let digitos = (valor || '').replace(/\D/g, '');
  if (digitos.length > 11 && digitos.startsWith('55'))
    digitos = digitos.slice(2);
  digitos = digitos.slice(0, 11);

  if (digitos.length <= 2) return digitos ? `(${digitos}` : '';

  const ddd = `(${digitos.slice(0, 2)}) `;
  const resto = digitos.slice(2);
  if (resto.length <= 4) return ddd + resto;

  const corte = resto.length > 8 ? 5 : 4;
  return `${ddd}${resto.slice(0, corte)}-${resto.slice(corte)}`;
};

// Segunda a sexta costuma ser tudo igual: preenche um dia, copia, e ajusta só o que foge. Copia para
// os dias ABERTOS — fim de semana fechado continua fechado. Devolve a grade nova e QUAIS dias mudaram:
// o aviso nomeia os dias ("copiado para terça, quarta, quinta e sexta"), que é o que deixa claro, sem
// ler manual, que o fim de semana ficou de fora.
export const copiarHorarioParaDias = (slots, origem) => {
  const dias = [];
  const novos = slots.map(item => {
    if (item.day === origem.day || !item.from || !item.to) return item;

    dias.push(item.day);
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

  return { slots: novos, dias };
};
