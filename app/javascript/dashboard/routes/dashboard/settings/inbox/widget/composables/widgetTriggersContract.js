/**
 * O contrato de `widget_triggers`, do lado da tela.
 *
 * A autoridade e o SERVIDOR: `app/models/concerns/widget_triggers_schema.rb`
 * (blocos 3.02 e 3.20) valida o jsonb com `json_schemer` e devolve 422. Aqui
 * ficam os mesmos enums, tetos e defaults para a tela poder avisar ANTES — e
 * `specs/widgetTriggersContract.spec.js` le o arquivo Ruby e falha nomeando o
 * campo que se separou.
 *
 * A DUREZA QUE JUSTIFICA O ARQUIVO: o schema tem `additionalProperties: false`
 * em todos os niveis. Uma chave a mais nao e ignorada — ela faz o PATCH INTEIRO
 * voltar 422. A tela salva, o banco nao muda, e o administrador so descobre ao
 * recarregar.
 */

/** Os sete gatilhos, na ordem em que a tela os mostra. */
export const TRIGGER_IDS = Object.freeze([
  'time_on_page',
  'scroll_depth',
  'exit_intent',
  'idle',
  'element_click',
  'element_visible',
  'return_visit',
]);

/** Os tres niveis de abordagem (3.20 / decisao D1). */
export const APPROACHES = Object.freeze(['discreet', 'bold', 'aggressive']);

/**
 * Em celular o painel cobre a tela inteira, que e onde auto-open e mais
 * hostil: `aggressive` nao e oferecido, e quem recusa e o schema (422), nao a
 * tela.
 */
export const MOBILE_APPROACHES = Object.freeze(['discreet', 'bold']);

export const DEFAULT_APPROACH = 'bold';
export const DEFAULT_DEGRADE_ON_RETURN = true;

export const URL_OPERATORS = Object.freeze([
  'contains',
  'not_contains',
  'equals',
  'starts_with',
  'ends_with',
]);

export const DEVICES = Object.freeze(['desktop', 'mobile']);

export const TRIGGER_LIMITS = Object.freeze({
  /** `value` e sempre segundos ou porcento; o teto de um dia mata o typo. */
  valueMin: 0,
  valueMax: 86_400,
  selectorMinLength: 1,
  selectorMaxLength: 200,
  cooldownMin: 0,
  cooldownMax: 2_592_000,
  maxPerSessionMin: 0,
  maxPerSessionMax: 20,
  maxTriggers: 20,
  urlValuesMax: 50,
  urlValueMaxLength: 500,
  utmValuesMax: 50,
  utmValueMaxLength: 200,
});

/**
 * Os gatilhos que NAO tem valor numerico — ligar e desligar e tudo o que eles
 * oferecem. `exit_intent` ainda nao existe em celular (nao ha cursor saindo da
 * viewport), e a tela precisa dizer isso em vez de mostrar um controle morto.
 */
export const TRIGGERS_WITHOUT_VALUE = Object.freeze([
  'exit_intent',
  'return_visit',
]);
export const DESKTOP_ONLY_TRIGGERS = Object.freeze(['exit_intent']);
export const TRIGGERS_WITH_SELECTOR = Object.freeze([
  'element_click',
  'element_visible',
]);

/**
 * O preset "Recomendado": teaser depois de 8 s de permanencia E 30% de
 * rolagem. Nao e enfeite — e a prescricao do estudo (16 §3.2): gatilho
 * composto, nunca so tempo.
 */
export const RECOMMENDED_TRIGGERS = Object.freeze([
  {
    id: 'time_on_page',
    desktop: { enabled: true, value: 8 },
    mobile: { enabled: true, value: 8 },
  },
  {
    id: 'scroll_depth',
    desktop: { enabled: true, value: 30 },
    mobile: { enabled: true, value: 30 },
  },
]);

/** A resolucao da abordagem em celular, igual a do servidor. */
export const resolveMobileApproach = (approachMobile, approach) => {
  const herdado = approachMobile || approach || DEFAULT_APPROACH;
  return MOBILE_APPROACHES.includes(herdado) ? herdado : DEFAULT_APPROACH;
};
