/**
 * Mensagem de obrigatoriedade do pré-chat — bloco 2.17.
 *
 * O QUE ESTAVA ERRADO
 *
 * `PreChat/Form.vue` mandava ao FormKit `required: $t('PRE_CHAT_FORM.REQUIRED')`
 * — a string "Obrigatório", igual para TODOS os campos. Com três campos em
 * branco, o visitante via a mesma palavra três vezes e o leitor de tela
 * anunciava a mesma coisa três vezes, sem dizer de qual campo se tratava.
 *
 * Ao mesmo tempo, `PRE_CHAT_FORM.FIELDS.<CAMPO>.REQUIRED_ERROR` já existia
 * traduzido nos 40 locales e NENHUM componente lia a chave. Este helper fecha
 * essa distância: dicionário e marcação passam a apontar para o mesmo lugar.
 *
 * CONTRATO
 *
 *   getRequiredMessage({ field, t }) -> string
 *
 *   · `field.name` ∈ {fullName, emailAddress, phoneNumber}
 *       → `PRE_CHAT_FORM.FIELDS.<CHAVE>.REQUIRED_ERROR` (mensagem própria).
 *   · qualquer outro `name` COM `field.label`
 *       → `PRE_CHAT_FORM.FIELD_IS_REQUIRED`, interpolando `{label}`.
 *   · qualquer outro `name` SEM `field.label`
 *       → `PRE_CHAT_FORM.REQUIRED` — o comportamento de hoje. É degradação
 *         deliberada: sem rótulo não há como nomear o campo, e "O campo  é
 *         obrigatório", com o buraco no meio, é pior que a genérica.
 *
 * POR QUE `{label}` E NÃO CONCATENAÇÃO
 *
 * A tradução mecânica de `{label} is required` seria `{label} é obrigatório`, e
 * em pt-BR o adjetivo concordaria com o rótulo: "Empresa é obrigatório" está
 * errado. Prefixar "O campo" prende a concordância no masculino de "campo" e
 * vale para qualquer rótulo, sem precisar de uma chave por gênero.
 */

// `name` do campo (camelCase, como chega do banco) → ramo do dicionário
// (UPPER_SNAKE). O descasamento entre as duas convenções já produziu um defeito
// antes — ver `dashboard/helper/specs/preChatI18n.spec.js` —, por isso o mapa é
// explícito em vez de derivado por regex.
const CHAVE_POR_CAMPO = {
  fullName: 'FULL_NAME',
  emailAddress: 'EMAIL_ADDRESS',
  phoneNumber: 'PHONE_NUMBER',
};

export const getRequiredMessage = ({ field = {}, t }) => {
  const chave = CHAVE_POR_CAMPO[field.name];

  if (chave) {
    // A chave sai de `CHAVE_POR_CAMPO`, mapa fechado e literal logo acima: o
    // conjunto de chaves possíveis é estático e conferível por leitura, que é
    // o que a regra `no-dynamic-keys` protege. Escrever os três `t()` à mão só
    // duplicaria o mapa.
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    return t(`PRE_CHAT_FORM.FIELDS.${chave}.REQUIRED_ERROR`);
  }

  if (field.label) {
    return t('PRE_CHAT_FORM.FIELD_IS_REQUIRED', { label: field.label });
  }

  return t('PRE_CHAT_FORM.REQUIRED');
};

export default { getRequiredMessage };
