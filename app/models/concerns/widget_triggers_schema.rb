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
        'additionalProperties' => { 'type' => 'array', 'maxItems' => 50, 'items' => { 'type' => 'string', 'maxLength' => 200 } }
      },
      'device' => { 'type' => 'array', 'maxItems' => 2, 'items' => { 'type' => 'string', 'enum' => DEVICES } }
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
      # --- bloco 3.20, decisao D1 ---
      'approach' => { 'type' => 'string', 'enum' => APPROACHES },
      'approach_mobile' => { 'type' => 'string', 'enum' => MOBILE_APPROACHES },
      'degrade_on_return' => { 'type' => 'boolean' }
    },
    'additionalProperties' => false
  }.freeze
end
