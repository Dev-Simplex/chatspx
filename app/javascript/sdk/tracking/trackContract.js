/**
 * Bloco 5.16 — o vocabulário de tracking do lado do site, e a recusa que o torna confiável.
 *
 * As três regras de nome NÃO foram inventadas aqui: são as de
 * `docs/tracking/contrato-de-eventos.md` §1, as mesmas que `TrackingEvent` valida na gravação.
 * A duplicação é deliberada e tem um motivo medido: a validação do servidor só fala depois de uma
 * viagem de rede, e o contrato da API pública de dados (bloco 1.23) manda validar IMEDIATAMENTE —
 * o erro de digitação do integrador tem de aparecer ligado à linha que o causou, não 300 ms
 * depois, desligado dela. O servidor continua sendo a autoridade; isto é o aviso antecipado.
 *
 * O limite de 40 caracteres é do GA4, não preferência nossa: um nome maior é aceito por nós e
 * descartado lá, o que é a pior forma de falha — a que ninguém vê.
 */

export const NAME_PREFIX = 'chatspx_';
export const NAME_MAX_LENGTH = 40;
const SNAKE_CASE = /^[a-z][a-z0-9_]*$/;

/**
 * As chaves de PII (regra **RC5**). Lista canônica: `TrackingEvent::PII_KEYS`.
 *
 * Aqui elas são RECUSADAS, não filtradas — e a diferença é o que o integrador aprende. Filtrar em
 * silêncio faria o e-mail sumir do payload sem ninguém saber: o cliente veria o evento chegar,
 * concluiria que está tudo certo, e o campo que ele acha que mandou nunca existiu. O caminho da
 * PII é outro e é do servidor, que normaliza e hasheia (contrato §6 ponto 3).
 */
export const PII_KEYS = Object.freeze([
  'em',
  'ph',
  'fn',
  'ln',
  'email',
  'phone',
  'phone_number',
  'first_name',
  'last_name',
]);

/**
 * O nome viola alguma das três regras? Devolve a regra violada, ou `null`.
 *
 * As mensagens são curtas por um motivo medido: cada byte daqui entra no `sdk.js`, que 100% dos
 * visitantes de todos os sites baixam. Elas nomeiam a regra — que é o que o integrador precisa —
 * e a explicação longa mora no guia, que ninguém baixa por engano.
 */
export const nameViolation = name => {
  if (typeof name !== 'string' || !name) return 'Event name is required';
  if (!name.startsWith(NAME_PREFIX))
    return `Event name must start with "${NAME_PREFIX}"`;
  if (!SNAKE_CASE.test(name)) return 'Event name must be snake_case';
  if (name.length > NAME_MAX_LENGTH)
    return `Event name must be at most ${NAME_MAX_LENGTH} chars (GA4 limit)`;

  return null;
};

/** A primeira chave de PII encontrada em `properties`, ou `null`. Rasa: o payload é plano. */
export const piiViolation = (properties = {}) =>
  Object.keys(properties || {}).find(chave =>
    PII_KEYS.includes(String(chave).toLowerCase())
  ) || null;
