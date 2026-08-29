# Schema dos gatilhos do widget (bloco 3.02), ampliado pela abordagem em tres niveis (bloco 3.20).
#
# Mora em `inbox.additional_attributes['widget_triggers']` e e validado por `json_schemer`
# (`Gemfile:38`, mesmo padrao de `integrations/hook.rb:102`). Sem tabela propria: a cardinalidade e
# fixa e pequena, o objeto e sempre lido inteiro e sempre escrito inteiro (plano 24 §10.3).
#
# TUDO AQUI E PUBLICO (A5): o objeto vai inteiro no payload de boot e a avaliacao e do SDK, no
# navegador do visitante. Segmentacao por atributo de contato nao entra — vazaria dado de negocio.
module WidgetTriggersSchema
  extend ActiveSupport::Concern

  # Os sete gatilhos do teardown, plano 24 §10.1.
  TRIGGER_IDS = %w[time_on_page scroll_depth exit_intent idle element_click element_visible return_visit].freeze

  # Bloco 3.20 (decisao D1): tres niveis de intensidade. Valores em ingles snake_case pela A2 —
  # o rotulo em pt-BR e do i18n do dashboard.
  APPROACHES = %w[discreet bold aggressive].freeze
  # Em celular o painel cobre a tela inteira, que e onde auto-open e mais hostil: `aggressive`
  # nao e oferecido, e a recusa e do schema (422), nao da tela (A15).
  MOBILE_APPROACHES = %w[discreet bold].freeze

  DEFAULT_APPROACH = 'bold'.freeze
  DEFAULT_DEGRADE_ON_RETURN = true

  URL_OPERATORS = %w[contains not_contains equals starts_with ends_with].freeze
  DEVICES = %w[desktop mobile].freeze

  # Bloco 4.04 / T3.2 — os cinco parametros de UTM, e so eles. A lista e fechada de proposito: o
  # `utm` nasceu como objeto de chave livre e a tela nunca o escreveu, entao nao ha dado gravado a
  # preservar; deixa-lo aberto significaria aceitar `utm_sorce` com 200 no PATCH e um gatilho que
  # nunca dispara, sem uma linha de aviso. Fechado, o erro sai no 422 NOMEANDO a chave.
  UTM_PARAMS = %w[utm_source utm_medium utm_campaign utm_term utm_content].freeze

  # Bloco 4.04 / T3.2 — visitante novo ou recorrente. E cookie do HOST (plano 23 §B.3.1): o
  # navegador ja sabe a resposta, entao o criterio cabe na v1 sem endpoint nenhum.
  VISITOR_KINDS = %w[any new returning].freeze
  DEFAULT_VISITOR = 'any'.freeze

  # Bloco 4.04 / T3.5 — "quando nao aparecer". O corte de largura e o BREAKPOINT UNICO da spec do
  # widget (plano 22, W2.13): abaixo de 768 px o painel e tela cheia, e convite proativo em cima de
  # tela cheia e a reclamacao que o estudo documenta.
  DEFAULT_MIN_VIEWPORT_WIDTH = 768
  # Acima disso nao e tela, e digito a mais — o mesmo motivo do teto de um dia em `value`.
  MAX_VIEWPORT_WIDTH = 4096

  # `outside_business_hours` NAO precisa de dado novo: o payload de boot ja leva `working_hours`,
  # `working_hours_enabled`, `timezone` e `utc_off_set`
  # (`api/v1/widget/configs/create.json.jbuilder:24,40,46-47` e `widgets/show.html.erb:57-62`), o
  # que mantem a arbitragem A5 de pe — a avaliacao continua sendo do SDK, no navegador.
  SUPPRESS_SCHEMA = {
    'type' => 'object',
    'properties' => {
      'cookie_banner' => { 'type' => 'boolean' },
      'min_viewport_width' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => MAX_VIEWPORT_WIDTH },
      'outside_business_hours' => { 'type' => 'boolean' }
    },
    'additionalProperties' => false
  }.freeze

  # `value` e sempre segundos ou porcento; o teto de um dia impede que um typo vire um gatilho
  # que nunca dispara. `selector` vazio e o erro que o aceite de 3.02 cobra nominalmente.
  PLATFORM_SCHEMA = {
    'type' => 'object',
    'properties' => {
      'enabled' => { 'type' => 'boolean' },
      'value' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => 86_400 },
      'selector' => { 'type' => 'string', 'minLength' => 1, 'maxLength' => 200 }
    },
    'additionalProperties' => false
  }.freeze

  TRIGGER_SCHEMA = {
    'type' => 'object',
    'properties' => {
      'id' => { 'type' => 'string', 'enum' => TRIGGER_IDS },
      'desktop' => PLATFORM_SCHEMA,
      'mobile' => PLATFORM_SCHEMA,
      'cooldown_seconds' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => 2_592_000 }
    },
    'required' => ['id'],
    'additionalProperties' => false
  }.freeze

  AUDIENCE_SCHEMA = {
    'type' => 'object',
    'properties' => {
      'url' => {
        'type' => 'object',
        'properties' => {
          'operator' => { 'type' => 'string', 'enum' => URL_OPERATORS },
          'values' => { 'type' => 'array', 'maxItems' => 50, 'items' => { 'type' => 'string', 'minLength' => 1, 'maxLength' => 500 } }
        },
        'additionalProperties' => false
      },
      'utm' => {
        'type' => 'object',
        'properties' => UTM_PARAMS.index_with do
          { 'type' => 'array', 'maxItems' => 50, 'items' => { 'type' => 'string', 'minLength' => 1, 'maxLength' => 200 } }
        end,
        'additionalProperties' => false
      },
      'device' => { 'type' => 'array', 'maxItems' => 2, 'items' => { 'type' => 'string', 'enum' => DEVICES } },
      'visitor' => { 'type' => 'string', 'enum' => VISITOR_KINDS }
    },
    'additionalProperties' => false
  }.freeze

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'version' => { 'type' => 'integer', 'minimum' => 1 },
      'enabled' => { 'type' => 'boolean' },
      'defaults' => {
        'type' => 'object',
        'properties' => {
          'cooldown_seconds' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => 2_592_000 },
          'max_per_session' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => 20 }
        },
        'additionalProperties' => false
      },
      'triggers' => { 'type' => 'array', 'maxItems' => 20, 'items' => TRIGGER_SCHEMA },
      'audience' => AUDIENCE_SCHEMA,
      # Bloco 4.04 / T3.5. Chave PROPRIA, irma de `audience`, e nao um campo dentro dela: `audience`
      # responde ONDE o convite pode aparecer, `suppress` responde QUANDO ele se cala mesmo estando
      # no lugar certo. Sao perguntas diferentes, e a tela as separa pelo mesmo motivo.
      'suppress' => SUPPRESS_SCHEMA,
      # --- bloco 3.20, decisao D1 ---
      'approach' => { 'type' => 'string', 'enum' => APPROACHES },
      'approach_mobile' => { 'type' => 'string', 'enum' => MOBILE_APPROACHES },
      'degrade_on_return' => { 'type' => 'boolean' }
    },
    'additionalProperties' => false
  }.freeze
end
