export const ATTRIBUTE_MODELS = [
  { id: 0, key: 'CONVERSATION' },
  { id: 1, key: 'CONTACT' },
];

export const ATTRIBUTE_TYPES = [
  { id: 0, key: 'TEXT' },
  { id: 1, key: 'NUMBER' },
  { id: 4, key: 'LINK' },
  { id: 5, key: 'DATE' },
  { id: 6, key: 'LIST' },
  { id: 7, key: 'CHECKBOX' },
  { id: 8, key: 'CPF' },
];

// Catálogo (modelo 2) não entra em ATTRIBUTE_MODELS de propósito: campo de item é gerido na aba
// Campos do catálogo, e a tela de Atributos não oferece essa opção.
export const CATALOG_ATTRIBUTE_MODEL = 2;

// Tipos que o campo de item do catálogo aceita: sem CPF, com Moeda.
export const CATALOG_ATTRIBUTE_TYPES = [
  { id: 0, key: 'TEXT' },
  { id: 1, key: 'NUMBER' },
  { id: 2, key: 'CURRENCY' },
  { id: 4, key: 'LINK' },
  { id: 5, key: 'DATE' },
  { id: 6, key: 'LIST' },
  { id: 7, key: 'CHECKBOX' },
];
