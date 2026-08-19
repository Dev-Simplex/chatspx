/**
 * Bloco 5.09 — consentimento: Consent Mode v2 e LGPD.
 *
 * A REGRA QUE DA NOME AO BLOCO: o padrao e NEGADO. Sob LGPD o tratamento precisa de base legal
 * antes de acontecer, e "disparar e depois perguntar" nao tem volta — o dado ja saiu do navegador.
 *
 * A ORDEM DE EXECUCAO E PARTE DO ACEITE, nao detalhe de implementacao. O Consent Mode v2 exige que
 * o `default` seja publicado ANTES de qualquer tag carregar; o `update` vem depois, quando o
 * visitante decide. Publicar o default DEPOIS e o erro que faz a tag rodar uma vez sem gate — e um
 * disparo que ja aconteceu nao volta.
 */

// Os quatro sinais do Consent Mode v2. `functionality_storage` e afins ficam de fora: o widget nao
// os usa, e declarar sinal que nao se respeita e pior que nao declarar.
import { pushToDataLayer } from './dataLayer';

export const PURPOSES = [
  'ad_storage',
  'ad_user_data',
  'ad_personalization',
  'analytics_storage',
];

export const GRANTED = 'granted';
export const DENIED = 'denied';

const allDenied = () =>
  PURPOSES.reduce((acc, purpose) => ({ ...acc, [purpose]: DENIED }), {});

const state = {
  current: allDenied(),
  defaultsPublished: false,
  mode: 'disabled',
  // O sink e injetavel para que o teste observe SEM tocar em servico externo. Em producao ele
  // empurra para o dataLayer, que e uma variavel do proprio navegador — nao uma chamada de rede.
  sink: null,
};

const push = payload => {
  if (typeof state.sink === 'function') {
    state.sink(payload);
    return;
  }
  // Mesma porta da ponte de tags (5.10): duas implementacoes do mesmo `push` sao duas chances de
  // uma delas reatribuir o `window.dataLayer` do cliente em vez de estende-lo (RC2).
  if (typeof window !== 'undefined') pushToDataLayer(payload);
};

const sanitize = partial =>
  PURPOSES.reduce((acc, purpose) => {
    const value = partial?.[purpose];
    if (value === GRANTED || value === DENIED) acc[purpose] = value;
    return acc;
  }, {});

/** Estado atual, copia — quem le nao muta. */
export const consentState = () => ({ ...state.current });

export const isGranted = purpose => state.current[purpose] === GRANTED;

export const hasAnyConsent = () => PURPOSES.some(isGranted);

export const defaultsWerePublished = () => state.defaultsPublished;

/**
 * Publica o `default`. Idempotente: chamar duas vezes nao empurra dois defaults, porque o segundo
 * seria lido pelas tags como uma redefinicao e apagaria um `update` que ja tivesse chegado.
 */
export const publishDefaults = (partial = {}) => {
  if (state.defaultsPublished) return consentState();

  state.current = { ...allDenied(), ...sanitize(partial) };
  state.defaultsPublished = true;
  push(['consent', 'default', consentState()]);

  return consentState();
};

/**
 * `update` do Consent Mode. Se o default ainda nao foi publicado, publica-o ANTES — do contrario a
 * plataforma receberia um update sem linha de base, que ela trata como estado desconhecido.
 */
export const updateConsent = (partial = {}) => {
  if (!state.defaultsPublished) publishDefaults();

  state.current = { ...state.current, ...sanitize(partial) };
  push(['consent', 'update', consentState()]);

  return consentState();
};

/**
 * O GATE. Executa `fn` somente se o proposito estiver concedido.
 *
 * Nao ha fila de eventos negados, e a ausencia e deliberada: reproduzir depois o que o visitante
 * negou na hora seria honrar a letra do consentimento e trair o sentido. O aceite diz "os
 * SEGUINTES disparam" — os anteriores ficaram para tras porque naquele momento a resposta era nao.
 */
export const withConsent = (purpose, fn) => {
  if (!isGranted(purpose)) return undefined;

  return fn();
};

/**
 * Bloco 5.09 + 5.01 — o estado por conta/inbox. `consent_mode` vem de `widget_tracking`, validado
 * pelo schema do 5.01 (`disabled` | `basic` | `advanced`), e decide se o Consent Mode opera:
 *
 *   disabled  o padrao, e o comportamento de HOJE: sem Consent Mode, sem gate. A escolha e do
 *             cliente, e ligar isso sozinho mudaria o comportamento de quem nao pediu nada.
 *   basic     gate ligado; nada dispara sem concessao.
 *   advanced  idem, e o default e publicado ainda que a CMP demore — e a recomendacao do Google
 *             para nao perder a linha de base.
 *
 * `nil`/ausente le como `disabled`, que e a regra A4: ausencia tem significado e nao ha backfill.
 */
export const CONSENT_MODES = ['disabled', 'basic', 'advanced'];

export const applyInboxConsentMode = (mode = 'disabled') => {
  state.mode = CONSENT_MODES.includes(mode) ? mode : 'disabled';
  if (state.mode === 'advanced') publishDefaults();

  return state.mode;
};

export const consentModeIsActive = () => state.mode !== 'disabled';

/**
 * O gate efetivo, ja considerando o modo da inbox. Com `disabled`, o produto se comporta como
 * antes deste bloco — que e o unico jeito de ligar consentimento sem quebrar quem nao configurou.
 */
export const isAllowed = purpose =>
  !consentModeIsActive() || isGranted(purpose);

/**
 * O gate que o produto usa: respeita o modo da inbox. `withConsent` continua existindo para quem
 * precisa do gate CRU (o proprio 5.09 testa os dois), mas o caminho do produto e este.
 */
export const withConsentForInbox = (purpose, fn) => {
  if (!isAllowed(purpose)) return undefined;

  return fn();
};

/** Só para teste: injeta o observador e zera o estado. */
export const resetConsentForTests = sink => {
  state.current = allDenied();
  state.defaultsPublished = false;
  state.mode = 'disabled';
  state.sink = sink || null;
};
