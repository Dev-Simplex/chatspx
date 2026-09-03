/**
 * Validação de rótulo acessível dos primitivos.
 *
 * Emoji dentro da string vira nome acessível ruim: o leitor de tela anuncia o
 * símbolo ("Enviar carinha piscando") em vez do rótulo. O visual é papel do
 * conteúdo visível — do slot —, não do texto que o leitor lê.
 *
 * Fica no primitivo pela mesma razão do `isComposing` no `WComposer`: defesa
 * que cada consumidor precisa lembrar de repetir funciona só enquanto quem
 * escreve conhece a história.
 */
const PICTOGRAFICO = /\p{Extended_Pictographic}/u;

/** Rótulo opcional: pode ser vazio, não pode conter emoji. */
export const rotuloLimpo = valor =>
  typeof valor === 'string' && !PICTOGRAFICO.test(valor);

/** Rótulo obrigatório: precisa ter texto de verdade, e sem emoji. */
export const rotuloObrigatorio = valor =>
  rotuloLimpo(valor) && valor.trim().length > 0;
