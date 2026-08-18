export const BUBBLE_DESIGN = ['standard', 'expanded_bubble'];
export const WIDGET_DESIGN = ['standard', 'flat'];
export const DARK_MODE = ['light', 'auto', 'dark'];

// Bloco 2.10. O default NÃO é `DARK_MODE[0]`: amarrar o default à ordem de um
// array de valores válidos é frágil — reordenar a lista, coisa que parece
// cosmética, trocaria silenciosamente o tema de todo cliente que não
// configurou nada. O default é uma decisão, então está escrito como tal.
//
// `auto` é o default porque o widget é conteúdo de terceiro dentro do site do
// cliente: abrir claro num sistema em modo escuro é o único caso em que o
// visitante leva um clarão na cara sem ter pedido.
export const DEFAULT_DARK_MODE = 'auto';
