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
  install_tags: {},
  consent_mode: '',
  test_mode: {},
  lead_value: {},
});

/**
 * Valores de fabrica de `widget_exit` (bloco 4.08).
 *
 * Uma chave so, e ela nasce VAZIA: sem numero configurado o widget nao renderiza
 * a saida (um botao que abre `wa.me/` sem destino leva o visitante para uma tela
 * de erro do WhatsApp, que e pior que nao ter botao). O servidor concorda por
 * ausencia — `WidgetExitSchema::DEFAULTS`, sem migration e sem backfill (A4) —, e
 * `specs/widgetExitContract.spec.js` le o arquivo Ruby e falha se os dois lados
 * se separarem.
 *
 * SO DIGITOS no valor gravado. O schema do servidor recusa o resto com 422; a
 * tela normaliza antes de escrever no rascunho, para o administrador poder
 * colar `+55 (65) 99999-8888` sem levar um erro que ele nao entende.
 */
export const DEFAULT_EXIT = Object.freeze({
  whatsapp_number: '',
});

/**
 * `nil` e lido como `support` — a arbitragem A4 cortou o backfill de propósito:
 * escrever "support" em toda inbox da frota produz zero diferenca de
 * comportamento e toda escrita em massa e risco sem contrapartida.
 */
export const DEFAULT_PROFILE = 'support';

/**
 * Os recursos do canal que a aba Aparencia oferece como caixa de marcar, na
 * ordem em que aparecem.
 *
 * Mora AQUI, e nao dentro do `.vue`, para poder ser lida por
 * `specs/widgetChannelWireNames.spec.js`, que compara esta lista com o
 * `has_flags` de `Channel::WebWidget`. Sem esse cruzamento, uma flag existe de
 * um lado e nao do outro sem barulho nenhum: foi o que aconteceu com o som, que
 * o `IFrameHelper` ja consultava (`notification_sound` em `enabledFeatures`) e
 * que o servidor recusava com `ArgumentError: Invalid flag` — recurso invisivel
 * para sempre, sem erro e sem teste vermelho.
 */
export const WIDGET_FEATURE_CHECKBOXES = Object.freeze([
  'attachments',
  'emoji_picker',
  'end_conversation',
  'use_inbox_avatar_for_bot',
  // Bloco 4.11 — som DESLIGADO por default (nenhuma inbox nasce com este bit) e
  // ligavel por inbox. O consumidor e `sdk/IFrameHelper.js`: sem esta string em
  // `enabledFeatures` ele nao baixa o mp3 nem registra ouvinte.
  'notification_sound',
]);

/**
 * Flags do mesmo `has_flags` que NAO sao caixa nesta lista, e onde elas moram.
 *
 * Ficar de fora e declaracao, nao esquecimento — e por isso a lista existe: o
 * cruzamento com o Ruby compara a SOMA das duas, entao uma flag nova nao pode
 * simplesmente sumir da tela.
 *
 * `allow_mobile_webview`: interruptor proprio em
 * `settingsPage/ConfigurationPage.vue`, porque e configuracao de instalacao
 * (webview de app nativo), nao recurso que o visitante ve no widget.
 */
export const WIDGET_FEATURES_ELSEWHERE = Object.freeze([
  'allow_mobile_webview',
]);

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
  // O `path` e `selected_feature_flags`, e nao `selectedFeatureFlags`, porque o
  // `save()` do rascunho manda `formData: false` — JSON cru. `buildInboxData`,
  // o unico lugar que traduzia o nome em camelCase para
  // `channel[selected_feature_flags][]`, so roda no caminho de `FormData` e nao
  // esta neste. O `permit` do servidor so conhece `selected_feature_flags`
  // (`Channel::WebWidget::EDITABLE_ATTRS`) e descarta em SILENCIO o que nao
  // conhece: quando as flags eram a unica mudanca, o sub-hash do canal chegava
  // vazio, `channel_update_required?` nem chamava o update, e a tela mostrava
  // "salvo" com o banco intacto — o checkbox voltava sozinho no proximo eco.
  {
    key: 'featureFlags',
    scope: 'channel',
    path: 'selected_feature_flags',
    read: inbox => [...(inbox?.selected_feature_flags ?? [])],
  },
  {
    key: 'profile',
    scope: 'additional',
    path: 'widget_profile',
    read: inbox =>
      inbox?.additional_attributes?.widget_profile ?? DEFAULT_PROFILE,
  },
  // Os dois abaixo entraram com o bloco 3.07, e a razao e uma so: sao campos
  // que a TROCA DE PERFIL propoe (`PROFILE_PROPOSALS`). Sem descritor aqui, a
  // proposta aceita nao tinha onde ser escrita e caia no chao — a tela dizia
  // que a troca fora aplicada e o PATCH saia sem ela.
  //
  // `csat_survey_enabled` e coluna da INBOX (raiz do payload,
  // `inboxes_controller.rb:257`); `continuity_via_email` e coluna do CANAL
  // (`Channel::WebWidget::EDITABLE_ATTRS`). Os dois voltam no `GET` pelo
  // `_inbox.json.jbuilder` (linhas 10 e 59), entao o `read` le do mesmo objeto
  // que o store guarda.
  {
    key: 'continuityViaEmail',
    scope: 'channel',
    path: 'continuity_via_email',
    read: inbox => Boolean(inbox?.continuity_via_email),
  },
  {
    key: 'csatSurveyEnabled',
    scope: 'inbox',
    path: 'csat_survey_enabled',
    read: inbox => Boolean(inbox?.csat_survey_enabled),
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
  // Bloco 4.08 — a quinta chave de `additional_attributes`. `group: true` pelo
  // mesmo motivo das outras tres: o update da inbox faz merge de PRIMEIRO NIVEL,
  // entao o objeto viaja inteiro e a contagem de alteracoes e por subcampo.
  {
    key: 'exit',
    scope: 'additional',
    path: 'widget_exit',
    group: true,
    read: inbox => ({
      ...DEFAULT_EXIT,
      ...(inbox?.additional_attributes?.widget_exit ?? {}),
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
