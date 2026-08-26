/**
 * Bloco 5.23 — o vocabulário de origem do lado do painel.
 *
 * As listas NÃO foram inventadas aqui: são as de `app/services/tracking/origin_attributes.rb`
 * (bloco 1.18), que é o catálogo canônico. A duplicação existe porque este código roda no
 * navegador e não alcança o Ruby — e ela é **guardada**: `specs/originAttributes.spec.js` lê o
 * arquivo Ruby e reprova se as duas listas divergirem. Sem essa guarda, a próxima chave de
 * origem entraria de um lado só, e o lado que faltasse seria justamente o que o agente vê.
 *
 * POR QUE UMA LISTA, E NÃO "TUDO QUE COMEÇA COM first_/last_": um atributo que o AGENTE criou
 * chamado `last_contato` entraria na seção do site e mentiria sobre quem escreveu o quê — que é
 * exatamente a distinção que este bloco existe para fazer.
 */

/** Parâmetros de campanha. Iguais a `Tracking::OriginAttributes::UTM_KEYS`. */
export const UTM_KEYS = [
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'utm_id',
];

/** Identificadores de clique. Iguais a `CLICK_ID_KEYS`. Só existem no escopo da conversa. */
export const CLICK_ID_KEYS = [
  'gclid',
  'gbraid',
  'wbraid',
  'fbclid',
  'msclkid',
  'ttclid',
];

/** Derivadas pelo parser (1.19). Iguais a `DERIVED_KEYS`. */
export const DERIVED_KEYS = ['page_host', 'page_path', 'origin_kind'];

/** Prefixos de escopo. Iguais a `CONTACT_PREFIX` / `CONVERSATION_PREFIX`. */
export const CONTACT_PREFIX = 'first_';
export const CONVERSATION_PREFIX = 'last_';

/**
 * O contato guarda a PRIMEIRA origem (quem trouxe a pessoa); a conversa guarda a ÚLTIMA (o que
 * trouxe esta conversa). Os identificadores de clique só existem na conversa — é a divisão que
 * `Tracking::OriginRecorder` faz ao gravar, e o painel a espelha em vez de reinventar.
 */
export const CONTACT_BASE_KEYS = [...UTM_KEYS, ...DERIVED_KEYS];
export const CONVERSATION_BASE_KEYS = [
  ...UTM_KEYS,
  ...CLICK_ID_KEYS,
  ...DERIVED_KEYS,
];

export const contactOriginKeys = () =>
  CONTACT_BASE_KEYS.map(key => `${CONTACT_PREFIX}${key}`);

export const conversationOriginKeys = () =>
  CONVERSATION_BASE_KEYS.map(key => `${CONVERSATION_PREFIX}${key}`);

/**
 * Os valores que `origin_kind` pode ter. Iguais a `ORIGIN_KINDS`.
 *
 * `nao_disponivel` está na lista e é o ponto do bloco 1.19: quando não sabemos de onde a pessoa
 * veio, o dado **diz que não sabe**. Chamar ausência de "origem direta" é a mentira que o 1.22
 * proibiu no relatório, e ela começaria aqui, no vocabulário.
 */
export const ORIGIN_KINDS = [
  'busca_paga',
  'busca_organica',
  'social',
  'ia_generativa',
  'email',
  'referencia',
  'nao_disponivel',
];
