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
