/**
 * FONTE ÚNICA dos eventos de `window` que o site do cliente escuta.
 *
 * Bloco 5.04 do PLANO-MESTRE (origem T-C3.2–T-C3.7, BK-17, T-I4.2, T-I4.4, T-I4.5).
 *
 * DOIS VOCABULÁRIOS, UMA EMISSÃO (arbitragem A9, e está escrito em
 * `docs/tracking/contrato-de-eventos.md` §1):
 *
 *   · `chatwoot:*` — o evento de `window`. É o contrato com o SITE do cliente,
 *     lido por qualquer `addEventListener` da página. Os sete primeiros nomes
 *     já estão em produção: renomear qualquer um derruba o GTM de todo cliente
 *     que os escuta, em silêncio. Por isso os nomes vivem AQUI e em lugar
 *     nenhum mais — nem repetidos em teste, nem digitados no emissor.
 *   · `chatspx_*` — o evento de TRACKING (GA4, Meta, `dataLayer`), que é
 *     server-side e pertence ao bloco 5.03. Este arquivo guarda o mapa 1:1
 *     entre os dois, que é o que o bloco 5.10 (ponte de tags) vai consumir.
 *
 * A GUARDA CONTRA RENOMEAÇÃO é `specs/sdkEventContract.spec.js`: ele lê os
 * nomes do DOCUMENTO de contrato (que é de outra trilha) e exige que batam
 * com o que está aqui. Duas fontes independentes; renomear de um lado só
 * reprova o CI nomeando o evento.
 */

// ── Os sete que já existiam. Não mexer nos valores. ─────────────────────────
export const CHATWOOT_ERROR = 'chatwoot:error';
export const CHATWOOT_ON_MESSAGE = 'chatwoot:on-message';
export const CHATWOOT_ON_START_CONVERSATION = 'chatwoot:on-start-conversation';
export const CHATWOOT_POSTBACK = 'chatwoot:postback';
export const CHATWOOT_READY = 'chatwoot:ready';
export const CHATWOOT_OPENED = 'chatwoot:opened';
export const CHATWOOT_CLOSED = 'chatwoot:closed';

// ── Os que faltavam (5.04) ──────────────────────────────────────────────────
//
// `chatwoot:on-start-conversation` continua existindo e continua sendo emitido
// de onde sempre foi (T-I4.4: "mantendo o evento antigo por compatibilidade").
// Ele é INTENÇÃO — dispara no clique, antes de existir conversa nenhuma. Quem
// quer a CONCLUSÃO passa a ter `chatwoot:conversation-created`, que só sai
// quando o servidor respondeu e traz o `conversation_id`.
export const CHATWOOT_CONVERSATION_CREATED = 'chatwoot:conversation-created';
export const CHATWOOT_PRECHAT_SUBMITTED = 'chatwoot:prechat-submitted';
// `chatwoot:message-sent` é NOVO — não estava entre os sete de produção. Ele
// nasce no 5.04 e o 4.19 depende dele: é a conversão que zera o contador de
// familiaridade do host (`IFrameHelper.events.onEvent`). Uma declaração só:
// declarar o mesmo nome duas vezes neste módulo é `SyntaxError` de ESM, e o
// merge das duas trilhas já chegou a produzir exatamente isso.
export const CHATWOOT_MESSAGE_SENT = 'chatwoot:message-sent';
export const CHATWOOT_CSAT_SUBMITTED = 'chatwoot:csat-submitted';
export const CHATWOOT_CAMPAIGN_SHOWN = 'chatwoot:campaign-shown';
export const CHATWOOT_LEAD_IDENTIFIED = 'chatwoot:lead-identified';
export const CHATWOOT_RESET_COMPLETED = 'chatwoot:reset-completed';

/**
 * O contrato de cada evento novo, campo por campo.
 *
 * `payload` lista as CHAVES que o evento carrega — e a lista é curta de
 * propósito: o `window` do cliente é legível por qualquer script de terceiro
 * na página, então **nome de campo sim, valor de PII nunca** (regra dura de
 * `24-plano-backend-dados.md` §17.1 e RC5 do plano 25). É por isso que
 * `prechat-submitted` leva `fields` (os NOMES dos campos preenchidos) e
 * `lead-identified` leva `identifiers` (quais identificadores passaram a
 * existir), e nenhum dos dois leva o e-mail nem o telefone.
 *
 * `tracking` é o nome do evento de tracking correspondente, `null` quando o
 * fato não tem contrapartida no vocabulário `chatspx_`. `null` NÃO é omissão:
 * é o estado declarado no contrato de 5.03 e o teste o verifica.
 */
export const SDK_EVENT_CONTRACT = Object.freeze({
  [CHATWOOT_CONVERSATION_CREATED]: Object.freeze({
    tracking: 'chatspx_conversation_started',
    payload: Object.freeze(['conversation_id', 'inbox_id']),
  }),
  [CHATWOOT_PRECHAT_SUBMITTED]: Object.freeze({
    tracking: 'chatspx_prechat_submitted',
    payload: Object.freeze(['fields']),
  }),
  [CHATWOOT_MESSAGE_SENT]: Object.freeze({
    // Sinal interno: mede engajamento, não vai a destino de anúncio.
    tracking: null,
    payload: Object.freeze(['conversation_id']),
  }),
  [CHATWOOT_CSAT_SUBMITTED]: Object.freeze({
    // `chatspx_csat_submitted` NÃO existe, e a ausência é decisão registrada:
    // `docs/tracking/contrato-de-eventos.md` §6 ponto 1 manda não implementar
    // antes de o produto decidir parâmetros, canais e política de PII. O
    // evento de `window` sai (o site do cliente o pediu); o de tracking, não.
    tracking: null,
    payload: Object.freeze(['rating']),
  }),
  [CHATWOOT_CAMPAIGN_SHOWN]: Object.freeze({
    tracking: null,
    payload: Object.freeze(['campaign_id']),
  }),
  [CHATWOOT_LEAD_IDENTIFIED]: Object.freeze({
    tracking: 'chatspx_lead',
    payload: Object.freeze(['conversation_id', 'identifiers']),
  }),
  [CHATWOOT_RESET_COMPLETED]: Object.freeze({
    tracking: null,
    payload: Object.freeze([]),
  }),
});
