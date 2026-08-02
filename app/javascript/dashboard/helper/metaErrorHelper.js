/**
 * Traduz o erro cru de envio da Cloud API do WhatsApp (Meta) numa razao curta
 * que o atendente entende. O texto cru continua sendo exibido junto, porque e
 * o que o suporte precisa pra abrir chamado.
 *
 * As familias de codigo espelham o mapa ja usado no backend em
 * `app/listeners/spx/tozi/funnel_automation_listener.rb` — mesma semantica,
 * mesmos codigos. Se um lado mudar, mudar o outro junto.
 *
 * Referencia: https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes
 */

// Cada chave vira `CHAT_LIST.SEND_ERROR.<chave>` no i18n.
const REASON_BY_CODE = {
  // Numero nao tem WhatsApp — a mensagem nunca chega.
  131026: 'NO_WHATSAPP',
  131030: 'NO_WHATSAPP',
  // Numero esta OK, mas a Meta segurou a entrega (qualidade/experimento).
  131049: 'DELIVERY_BLOCKED',
  130472: 'DELIVERY_BLOCKED',
  // Problema da CONTA, nao do contato: bloqueio, pagamento, spam-pause.
  131031: 'ACCOUNT',
  131042: 'ACCOUNT',
  131048: 'ACCOUNT',
  // Passou da janela de 24h: so template aprovado passa.
  131047: 'WINDOW_EXPIRED',
  // Template recusado (nome, idioma, variaveis).
  132000: 'TEMPLATE',
  132001: 'TEMPLATE',
  132005: 'TEMPLATE',
  132007: 'TEMPLATE',
  132012: 'TEMPLATE',
  132015: 'TEMPLATE',
};

// O `external_error` chega em formatos diferentes conforme a origem:
//  - webhook de status  -> "131026: Message undeliverable"  (base service monta "code: title")
//  - resposta de envio  -> "(#131047) Message failed to send because ..."  (error.message da Meta)
const CODE_PATTERNS = [
  /\(#(\d{3,6})\)/, // "(#131047) ..."
  /^\s*(\d{3,6})\s*[:-]/, // "131026: ..." / "131026 - ..."
  /\b(13\d{4})\b/, // ultimo recurso: codigo 13xxxx solto no texto
];

/**
 * Extrai o codigo de erro da Meta de dentro do texto cru.
 *
 * @param {string|null|undefined} rawError texto cru de `external_error`
 * @returns {string|null} o codigo (ex: '131047') ou null se nao houver
 */
export const metaErrorCode = rawError => {
  if (!rawError) return null;

  const text = String(rawError);
  const matched = CODE_PATTERNS.map(pattern => text.match(pattern)).find(
    Boolean
  );
  return matched ? matched[1] : null;
};

/**
 * Descobre a razao provavel da falha a partir do texto cru.
 *
 * So devolve uma razao quando o codigo e reconhecido — assim a UI nunca afirma
 * "erro da Meta" em cima de um erro que veio de outro canal (e-mail, Telegram)
 * ou do proprio SPX.
 *
 * @param {string|null|undefined} rawError texto cru de `external_error`
 * @returns {{ code: string, reasonKey: string }|null}
 */
export const metaErrorReason = rawError => {
  const code = metaErrorCode(rawError);
  if (!code) return null;

  const reasonKey = REASON_BY_CODE[code];
  if (!reasonKey) return null;

  return { code, reasonKey };
};
