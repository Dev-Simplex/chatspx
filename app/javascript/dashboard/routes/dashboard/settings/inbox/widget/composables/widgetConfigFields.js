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

/**
 * Valores de fabrica de `widget_appearance`.
 *
 * Sao os do SERVIDOR (`WidgetAppearanceSchema::DEFAULTS`, bloco 3.18), e nao
 * uma segunda opiniao: uma inbox sem a chave gravada vale exatamente isto, e a
 * tela que mostrasse outro valor mentiria sobre o estado atual. O cruzamento e
 * verificado em `specs/widgetAppearanceContract.spec.js`, que le o arquivo Ruby.
 *
 * `home_intents` viaja no rascunho para nao ser APAGADO por um PATCH que so
 * mexeu na posicao (o objeto do grupo vai inteiro); a UI dele e de outro bloco.
 */
export const DEFAULT_APPEARANCE = Object.freeze({
  theme: 'light',
  position: 'right',
  offset_x: 0,
  offset_y: 0,
  launcher_type: 'standard',
  launcher_text: '',
  hide_bubble: false,
  panel_style: 'standard',
  launcher_icon: 'default',
  home_intents: [],
});

/**
 * Valores de fabrica de `widget_triggers`.
 *
 * Sao os do SERVIDOR (`WidgetTriggersSchema`, blocos 3.02 e 3.20), conferidos
 * por `specs/widgetTriggersContract.spec.js`, que le o arquivo Ruby. Tres
 * escolhas aqui nao sao obvias e tem razao:
 *
 *  · **`enabled: false`.** Inbox que nunca abriu a tela nao dispara nada, e
 *    salvar qualquer outro campo nao pode ligar o teaser sem alguem pedir (A4).
 *  · **`approach_mobile` NAO entra.** O servidor resolve o celular herdando o
 *    desktop (e recusando `aggressive`); fixar um valor aqui faria o admin
 *    escolher "Chamativo" no computador e o celular ficar "Discreto" sozinho.
 *  · **`triggers`, e nao `rules`.** O nome e do schema. Com
 *    `additionalProperties: false`, uma chave a mais nao e ignorada: derruba o
 *    PATCH INTEIRO com 422 — a tela diria "salvo" com o banco intacto.
 */
export const DEFAULT_TRIGGERS = Object.freeze({
  enabled: false,
  approach: 'bold',
  degrade_on_return: true,
  triggers: [],
});

/**
 * Valores de fabrica de `widget_tracking`.
 *
 * As chaves sao as de `WidgetTrackingProjection::PUBLIC_KEYS` — e so elas. O
 * que estiver fora da projecao PODE ser gravado (o jsonb aceita), mas nunca
 * chega ao widget: viraria lixo no banco com a tela parecendo funcionar. O
 * spec `specs/widgetTrackingContract.spec.js` le o arquivo Ruby e falha
 * nomeando a chave que sobrar.
 *
 * `event_map` nasce vazio e e gravado COMPLETO quando o administrador salva
 * (os doze eventos): quem consome le o que esta la, sem precisar conhecer os
 * defaults da tela — o mesmo principio de `resolved_widget_appearance`.
 *
 * NENHUM SEGREDO AQUI. `widget_tracking` e publicado no HTML de toda pagina do
 * site do cliente; access token e api secret moram em tabela cifrada (5.02) e
 * a gravacao os recusa com 422 (`SECRET_KEY_PATTERN`).
 */
export const DEFAULT_TRACKING = Object.freeze({
  meta_pixel_id: '',
  ga4_measurement_id: '',
  google_ads_send_to: '',
  event_map: {},
  consent_mode: '',
  test_mode: {},
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
  // Os dois do pre-chat (bloco 3.14), acrescentados pela trilha PRE-CHAT com
  // aval do coordenador e o contrato confirmado pela trilha TELAS.
  //
  // Nenhum dos dois e `group: true`, de proposito: `group` existe para as
  // quatro chaves de `additional_attributes`, onde o update faz merge de
  // primeiro nivel e a contagem por subcampo importa. `pre_chat_form_options`
  // e coluna jsonb do CANAL e viaja INTEIRA no PATCH — nao ha merge raso a
  // proteger. A consequencia esta declarada: mexer em cinco campos do pre-chat
  // conta UMA alteracao nao salva, nao cinco. Contagem por subcampo aqui
  // exigiria mudar a estrutura do mapa, que e territorio da trilha TELAS.
  {
    key: 'preChatEnabled',
    scope: 'channel',
    path: 'pre_chat_form_enabled',
    read: inbox => Boolean(inbox?.pre_chat_form_enabled),
  },
  {
    key: 'preChat',
    scope: 'channel',
    path: 'pre_chat_form_options',
    // Inbox sem `pre_chat_form_options` nao existe na pratica — o modelo semeia
    // o default em `before_validation` —, mas o rascunho nao pode nascer
    // `undefined` e quebrar a tela no primeiro `.pre_chat_fields`.
    read: inbox => ({
      pre_chat_message: '',
      pre_chat_fields: [],
      ...(inbox?.pre_chat_form_options ?? {}),
    }),
  },
];

export const FIELD_BY_KEY = Object.fromEntries(
  WIDGET_CONFIG_FIELDS.map(field => [field.key, field])
);
