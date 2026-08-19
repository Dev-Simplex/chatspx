export const CHATWOOT_ERROR = 'chatwoot:error';
export const CHATWOOT_ON_MESSAGE = 'chatwoot:on-message';
// O contrato de eventos (docs/tracking/contrato-de-eventos.md §2) ja declarava
// este nome para o fato "visitante enviou mensagem", marcado ali como sinal
// INTERNO. Ele nasce aqui porque o 4.19 precisa dele: e a conversao que zera o
// contador de familiaridade. O site do cliente passa a receber de graca.
export const CHATWOOT_MESSAGE_SENT = 'chatwoot:message-sent';
export const CHATWOOT_ON_START_CONVERSATION = 'chatwoot:on-start-conversation';
export const CHATWOOT_POSTBACK = 'chatwoot:postback';
export const CHATWOOT_READY = 'chatwoot:ready';
export const CHATWOOT_OPENED = 'chatwoot:opened';
export const CHATWOOT_CLOSED = 'chatwoot:closed';
