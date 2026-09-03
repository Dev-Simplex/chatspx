/**
 * A tesoura de PII do painel de diagnostico (bloco 5.14).
 *
 * O ACEITE do bloco e uma busca: `@` no painel RENDERIZADO tem de dar vazio.
 * Um painel que so desenha `field_names` passaria nesse teste sem esforco — e
 * passaria no VACUO, porque a coluna `field_names` ja e uma lista de nomes por
 * validacao do modelo (`TrackingDelivery#ensure_field_names_are_names`).
 *
 * O vazamento real nao mora ali. Mora em `error_message`, que e TEXTO LIVRE
 * devolvido pelo destino — e os destinos desta frente ecoam o payload ofensivo
 * na mensagem de erro. A Graph API da Meta responde coisas como
 * "Invalid parameter: em (fulano@empresa.com.br) is not a valid hash", e essa
 * string cai inteira em `tracking_deliveries.error_message`. Renderizar o campo
 * cru transforma o painel de auditoria num vazamento com interface.
 *
 * Por isso a limpeza acontece AQUI, na fronteira de leitura, e nao no template:
 * o componente nao pode ter um caminho que desenhe texto do servidor sem passar
 * por esta funcao. As duas camadas:
 *
 *  1. `redactPii` troca e-mail, telefone e sequencia longa de digitos (cartao,
 *     CPF, telefone sem formato) por um marcador visivel — o agente de suporte
 *     PRECISA ver que havia um valor ali, senao a mensagem de erro mente;
 *  2. o `@` remanescente e removido como ultima barreira, porque o aceite e
 *     literal e um formato de e-mail que a expressao nao previu nao pode
 *     atravessar mesmo assim.
 *
 * `keepFieldNames` e a mesma ideia do outro lado: nome de campo e
 * `snake_case`, entao qualquer entrada que nao caiba nesse formato e valor
 * disfarcado e nao chega a ser desenhada.
 */

/** O que aparece no lugar do que foi cortado — visivel de proposito. */
export const REDACTED_MARK = '[oculto]';

// Deliberadamente mais largas que o RFC: aqui um falso positivo custa uma
// palavra escondida, e um falso negativo custa o e-mail de um lead na tela.
const EMAIL = /[^\s<>()[\]{},;:"']+@[^\s<>()[\]{},;:"']+/g;
const PHONE = /\+?\d[\d\s().-]{7,}\d/g;
const LONG_DIGITS = /\d{9,}/g;

/** Nome de campo e `snake_case` — o resto e valor disfarcado. */
const FIELD_NAME = /^[A-Za-z0-9_.]{1,64}$/;

/**
 * Texto livre vindo do servidor, pronto para ser desenhado.
 *
 * A ordem importa: e-mail primeiro (senao a regra de telefone comeria os
 * digitos de dentro do endereco e o `@` sobreviveria sozinho).
 */
export const redactPii = (text = '') => {
  if (typeof text !== 'string' || !text) return '';

  return text
    .replace(EMAIL, REDACTED_MARK)
    .replace(PHONE, REDACTED_MARK)
    .replace(LONG_DIGITS, REDACTED_MARK)
    .replace(/@/g, '');
};

/**
 * Fica so o que E nome de campo.
 *
 * O servidor ja valida isso na escrita; a tela repete porque uma linha gravada
 * por outro caminho (console, importacao, bug futuro) chegaria aqui do mesmo
 * jeito, e o painel nao pode depender de o dado estar limpo para nao vazar.
 *
 * Quando chega `{ em: 'ana@exemplo.com' }` no lugar de `'em'`, a CHAVE ainda e
 * o nome do campo e o suporte precisa dela — entao ela e aproveitada e o valor
 * fica de fora. Mas a chave passa pelo mesmo crivo do resto, e essa e a
 * diferenca que importa: `Object.keys(...)[0]` sozinho desenharia
 * `{ 'ana@exemplo.com': true }` inteiro, porque ali o e-mail E a chave. Cortar
 * so o valor resolve o caso que se imagina; validar o nome resolve os dois.
 */
export const keepFieldNames = (names = []) => {
  if (!Array.isArray(names)) return [];

  return names
    .map(name => {
      if (typeof name === 'string') return name;
      if (name && typeof name === 'object') return Object.keys(name)[0] ?? '';
      return '';
    })
    .filter(name => FIELD_NAME.test(name));
};

/**
 * Uma entrega, reduzida ao que pode ser desenhado.
 *
 * Lista branca, nunca lista negra: o que o servidor mandar de novo — uma coluna
 * acrescentada depois, um `properties` que alguem resolveu incluir no
 * serializer — nao atravessa por omissao.
 */
export const sanitizeDelivery = (delivery = {}) => ({
  event_id: redactPii(String(delivery.event_id ?? '')),
  name: redactPii(String(delivery.name ?? '')),
  destination: redactPii(String(delivery.destination ?? '')),
  status: redactPii(String(delivery.status ?? '')),
  http_status: Number.isFinite(Number(delivery.http_status))
    ? Number(delivery.http_status)
    : null,
  error_code: redactPii(String(delivery.error_code ?? '')),
  error_message: redactPii(String(delivery.error_message ?? '')),
  emq:
    delivery.emq === null || delivery.emq === undefined
      ? null
      : Number(delivery.emq),
  attempts: Number(delivery.attempts ?? 0),
  last_attempted_at: redactPii(String(delivery.last_attempted_at ?? '')),
  field_names: keepFieldNames(delivery.field_names),
});

export const sanitizeDeliveries = (deliveries = []) =>
  (Array.isArray(deliveries) ? deliveries : []).map(sanitizeDelivery);
