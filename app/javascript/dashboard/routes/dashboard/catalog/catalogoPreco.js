// O preço é guardado em CENTAVOS com a moeda ao lado — é o formato que a Meta recebe. A tela
// converte só na hora de mostrar; dividir por 100 em cada template espalharia o mesmo arredondamento
// por toda parte.
export const formatarPreco = (centavos, moeda = 'BRL') => {
  if (centavos === null || centavos === undefined) return '';

  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: moeda || 'BRL',
  }).format(centavos / 100);
};

// O caminho de volta: o cadastro digita REAIS e a API só aceita CENTAVOS. Fica ao lado do
// `formatarPreco` porque é a mesma regra lida ao contrário — separá-las deixaria a tela arredondar
// de um jeito na entrada e de outro na saída.
export const paraCentavos = texto => {
  if (texto === null || texto === undefined) return null;

  const limpo = String(texto).replace(/[^\d,.]/g, '');
  if (!limpo) return null;

  // Em pt-BR a vírgula é o decimal e o ponto é o milhar ("1.299,90"). Sem trocar os dois de lugar
  // antes do parse, "1.299" viraria R$ 1,29 — o erro caro é esse, não o centavo perdido. Vale
  // também sem vírgula: "450.000" é quatrocentos e cinquenta mil, não quatrocentos e cinquenta.
  const soMilhar = /^\d{1,3}(\.\d{3})+$/.test(limpo);
  const normalizado =
    limpo.includes(',') || soMilhar
      ? limpo.replace(/\./g, '').replace(',', '.')
      : limpo;

  const valor = Number.parseFloat(normalizado);

  return Number.isNaN(valor) ? null : Math.round(valor * 100);
};

// O que o campo de preço mostra ao abrir um produto já salvo: número puro com vírgula, sem "R$",
// para o atendente editar o valor sem precisar apagar o símbolo antes.
export const paraCampoDeReais = centavos => {
  if (centavos === null || centavos === undefined) return '';

  return (centavos / 100).toFixed(2).replace('.', ',');
};
