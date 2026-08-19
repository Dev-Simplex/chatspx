/**
 * Bloco 5.17 — a traducao entre o que o SITE manda e o que a API do contato recebe.
 *
 * Existe como modulo proprio porque e uma juncao: o vocabulario publico (o que o cliente escreve
 * no snippet dele) e o vocabulario da API sao dois contratos, e o lugar onde eles se encontram
 * precisa ser um so. Enquanto isso viveu inline no store, cada campo novo virou uma linha copiada
 * — e foi assim que `phone_number` acabou fora do hash de dedupe do SDK.
 */

// Campos de topo do contato: viajam como colunas.
const TOP_LEVEL_KEYS = ['email', 'name', 'avatar_url', 'phone_number'];

// Campos que moram em `additional_attributes`. `company_name` continua aceito no topo por ser o
// nome legado; `company: { name }` e a forma nova (objeto), e vence quando os dois vierem.
const ADDITIONAL_KEYS = [
  'company_name',
  'city',
  'country_code',
  'description',
  'social_profiles',
  'signed_up_at',
];

const pickDefined = (source, keys) =>
  keys.reduce((acc, key) => {
    if (source[key] !== undefined) acc[key] = source[key];
    return acc;
  }, {});

/**
 * `company` como objeto (5.17). O site manda `{ company: { name: 'Simplex', id: 'acc_1' } }`;
 * o que a API entende hoje e `company_name`. O `id` e o resto ficam em atributos personalizados,
 * com prefixo, para nao colidirem com chave do cliente.
 */
export const flattenCompany = company => {
  if (!company || typeof company !== 'object') return {};

  const { name, ...resto } = company;
  const extras = Object.entries(resto).reduce((acc, [key, value]) => {
    if (value !== undefined) acc[`company_${key}`] = value;
    return acc;
  }, {});

  return { ...(name === undefined ? {} : { company_name: name }), ...extras };
};

/**
 * Monta o corpo que a API de contato recebe.
 *
 * `merge: true` (verbo `update…`) omite do payload o que o site NAO mandou, para o servidor nao
 * receber `undefined` e apagar o que ja estava. `merge: false` (verbo `set…`) manda os campos de
 * topo declarados, inclusive vazios — e essa e a diferenca de verbo que o bloco 5.17 pede que
 * seja explicita, em vez de deduzida.
 */
export const buildContactPayload = (
  userObject = {},
  { merge = false } = {}
) => {
  const daEmpresa = flattenCompany(userObject.company);
  const adicionais = {
    ...pickDefined(userObject, ADDITIONAL_KEYS),
    ...daEmpresa,
  };

  const topo = merge
    ? pickDefined(userObject, TOP_LEVEL_KEYS)
    : TOP_LEVEL_KEYS.reduce(
        (acc, key) => ({ ...acc, [key]: userObject[key] }),
        {}
      );

  const payload = {
    ...topo,
    identifier_hash: userObject.identifier_hash,
  };

  if (Object.keys(adicionais).length)
    payload.additional_attributes = adicionais;
  if (userObject.custom_attributes !== undefined) {
    payload.custom_attributes = userObject.custom_attributes;
  }

  return payload;
};
