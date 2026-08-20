import { storedOrigin } from './capture';
import { clickIdentifiers } from './clickIds';
import { allowedCookies } from './cookies';
import { googleIds } from './googleIds';
import { FIRST, LAST, TOUCH_KEYS } from './keys';

/**
 * Bloco 5.08 — o montador do payload, e a parte que roda **sob demanda**: só quando o chat
 * abre, e só quando a inbox tem configuração de tracking ativa (T-C2.8/T-C2.9).
 *
 * A divisão com `capture.js` é de custo, não de gosto: a captura precisa rodar em toda
 * página (senão a origem se perde na segunda), e por isso é minúscula; tudo o mais — ler
 * cookies, derivar `_fbc`/`_gcl_aw`, perguntar `client_id` ao gtag — só é útil no momento
 * em que a conversa vai nascer, e por isso não pesa no `sdk.js`.
 *
 * O DESTINO das chaves é o `custom_attributes` do `POST /api/v1/widget/conversations`
 * (T-C2.6), que o front já envia e o controller já aceita. Os prefixos `first_`/`last_` são
 * os mesmos de `Tracking::OriginAttributes` — o backend já sabe lê-los e o painel já os
 * exibe. Nada de contrato novo onde já existe um.
 */

const prefixed = (prefix, touch) =>
  TOUCH_KEYS.reduce((acc, key) => {
    if (touch?.[key]) acc[`${prefix}${key}`] = touch[key];
    return acc;
  }, {});

/**
 * As chaves de origem desta sessão, prontas para virar `custom_attributes`.
 *
 * NUNCA LANÇA e NUNCA TRAVA: o pior caso é devolver `{}`, e uma conversa sem atributo de
 * origem é infinitamente melhor que uma conversa que não nasce.
 */
export const originAttributes = async ({
  measurementId = null,
  host = window.location.host,
  now = Date.now(),
} = {}) => {
  try {
    const { first, last } = storedOrigin();
    if (!first && !last) return {};

    const cookies = allowedCookies();

    return {
      ...prefixed(FIRST, first),
      ...prefixed(LAST, last),
      ...clickIdentifiers({ touch: last || first, cookies, host, now }),
      ...(await googleIds({ measurementId, cookies })),
    };
  } catch {
    return {};
  }
};

export { captureOrigin, storedOrigin } from './capture';
// A entrega ao widget também mora aqui, e não no lado eager: ver o cabeçalho de `attach.js`.
export { attachOriginAttributes } from './attach';
// Bloco 5.10 — a ponte de tags. Ela sai por aqui pelo MESMO motivo do `attach.js`: é código de
// `window` do cliente que só serve a quem configurou tracking, e o `sdk.js` tem teto (A13).
// Quem a instancia é `IFrameHelper`, com o `isAllowed` do consentimento INJETADO — ver o
// cabeçalho de `tags.js` para o defeito de dois bundles que isso evita.
export { createTagsBridge } from './tags';
