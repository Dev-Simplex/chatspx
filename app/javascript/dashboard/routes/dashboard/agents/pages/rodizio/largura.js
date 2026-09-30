// Largura de barra em degraus de 5%, com as classes escritas por extenso: o Tailwind só gera a
// classe que ENXERGA no código-fonte, e a regra do projeto proíbe `style` inline. Degrau de 5% é
// fino o bastante para barra de comparação — ninguém lê 42% contra 44% no olho.
const LARGURAS = [
  'w-0',
  'w-[5%]',
  'w-[10%]',
  'w-[15%]',
  'w-[20%]',
  'w-[25%]',
  'w-[30%]',
  'w-[35%]',
  'w-[40%]',
  'w-[45%]',
  'w-[50%]',
  'w-[55%]',
  'w-[60%]',
  'w-[65%]',
  'w-[70%]',
  'w-[75%]',
  'w-[80%]',
  'w-[85%]',
  'w-[90%]',
  'w-[95%]',
  'w-full',
];

// `fracao` de 0 a 1. Qualquer valor acima de zero aparece com pelo menos um degrau: barra que
// some passa a impressão de "nada", e o número ao lado continua contando a verdade.
export const larguraDe = fracao => {
  const limitada = Math.min(Math.max(fracao || 0, 0), 1);
  const degrau = Math.round(limitada * 20);
  return LARGURAS[limitada > 0 ? Math.max(degrau, 1) : 0];
};
