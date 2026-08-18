/**
 * O mapa canonico dos campos que as quatro telas novas do widget editam.
 *
 * Existe um mapa so, e nao um por tela, porque `isDirty`, a contagem de
 * alteracoes pendentes, o diagnostico nominal do que mudou e a montagem do
 * payload sao a MESMA conta para as quatro telas (23-plano-config-dashboard
 * §B.0.2). Uma tela que precise de um campo novo acrescenta um descritor aqui.
 *
 * `scope` decide onde o valor mora no PATCH da inbox:
 *   - 'inbox'      -> raiz do payload             (`{ name: … }`)
 *   - 'channel'    -> sub-hash do canal           (`{ channel: { widget_color: … } }`)
 *   - 'additional' -> `additional_attributes`     (`{ additional_attributes: { widget_profile: … } }`)
 *
 * Por que o grupo de `additional` viaja INTEIRO e nunca em pedaco: o update da
 * inbox faz merge de PRIMEIRO NIVEL apenas
 * (`inboxes_controller.rb`, `update`: `(@inbox.additional_attributes || {}).merge(...)`).
 * Mandar `widget_appearance: { position: 'left' }` substitui o objeto inteiro e
 * apaga tema, offsets e o resto. Entao o rascunho guarda o objeto completo e o
 * payload manda o objeto completo — o merge raso preserva as OUTRAS tres chaves,
 * que e exatamente o que a arbitragem A1 comprou ao declarar quatro chaves de
 * topo em vez de um `widget_config` unico.
 */
import { DEFAULT_WIDGET_COLOR } from 'dashboard/constants/widget';

/** Valores de fabrica de `widget_appearance` (PLANO-MESTRE 3.18). */
export const DEFAULT_APPEARANCE = Object.freeze({
  theme: 'auto',
  position: 'right',
  offset_x: 20,
  offset_y: 20,
  launcher_type: 'standard',
  launcher_text: '',
  hide_bubble: false,
  panel_style: 'standard',
  launcher_icon: 'default',
});

/** Valores de fabrica de `widget_triggers` (PLANO-MESTRE 3.02 e 3.20). */
export const DEFAULT_TRIGGERS = Object.freeze({
  approach: 'bold',
  approach_mobile: 'discreet',
  degrade_on_return: true,
  rules: [],
});

/** Valores de fabrica de `widget_tracking` (PLANO-MESTRE 5.01). */
export const DEFAULT_TRACKING = Object.freeze({
  destinations: [],
  events: {},
});

/**
 * `nil` e lido como `support` — a arbitragem A4 cortou o backfill de propósito:
 * escrever "support" em toda inbox da frota produz zero diferenca de
 * comportamento e toda escrita em massa e risco sem contrapartida.
 */
export const DEFAULT_PROFILE = 'support';

export const WIDGET_CONFIG_FIELDS = [
  {
    key: 'name',
    scope: 'inbox',
    path: 'name',
    read: inbox => inbox?.name ?? '',
  },
  {
    key: 'widgetColor',
    scope: 'channel',
    path: 'widget_color',
    read: inbox => inbox?.widget_color || DEFAULT_WIDGET_COLOR,
  },
  {
    key: 'welcomeTitle',
    scope: 'channel',
    path: 'welcome_title',
    read: inbox => inbox?.welcome_title ?? '',
  },
  {
    key: 'welcomeTagline',
    scope: 'channel',
    path: 'welcome_tagline',
    read: inbox => inbox?.welcome_tagline ?? '',
  },
  {
    key: 'replyTime',
    scope: 'channel',
    path: 'reply_time',
    read: inbox => inbox?.reply_time || 'in_a_few_minutes',
  },
  {
    key: 'featureFlags',
    scope: 'channel',
    path: 'selectedFeatureFlags',
    read: inbox => [...(inbox?.selected_feature_flags ?? [])],
  },
  {
    key: 'profile',
    scope: 'additional',
    path: 'widget_profile',
    read: inbox =>
      inbox?.additional_attributes?.widget_profile ?? DEFAULT_PROFILE,
  },
  {
    key: 'appearance',
    scope: 'additional',
    path: 'widget_appearance',
    group: true,
    read: inbox => ({
      ...DEFAULT_APPEARANCE,
      ...(inbox?.additional_attributes?.widget_appearance ?? {}),
    }),
  },
  {
    key: 'triggers',
    scope: 'additional',
    path: 'widget_triggers',
    group: true,
    read: inbox => ({
      ...DEFAULT_TRIGGERS,
      ...(inbox?.additional_attributes?.widget_triggers ?? {}),
    }),
  },
  {
    key: 'tracking',
    scope: 'additional',
    path: 'widget_tracking',
    group: true,
    read: inbox => ({
      ...DEFAULT_TRACKING,
      ...(inbox?.additional_attributes?.widget_tracking ?? {}),
    }),
  },
];

export const FIELD_BY_KEY = Object.fromEntries(
  WIDGET_CONFIG_FIELDS.map(field => [field.key, field])
);
