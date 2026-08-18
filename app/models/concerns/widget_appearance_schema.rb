# Schema da aparencia do widget (bloco 3.18) — irmao do de 3.02.
#
# Ate aqui, posicao / formato / texto do lancador viviam no `localStorage` do NAVEGADOR DO ADMIN
# (`constants/localStorage.js:3`, chave `widgetBubble_<id>`), que e o defeito D1: o admin A gravava,
# o admin B nao via nada, e o site do cliente nunca via nada — o produto mentia para a propria tela.
#
# Os valores casam com o vocabulario que o SDK ja entende (`sdk/constants.js`), para que a
# precedencia seja comparavel campo a campo:
#   theme         -> DARK_MODE      ['light', 'auto', 'dark']
#   launcher_type -> BUBBLE_DESIGN  ['standard', 'expanded_bubble']
#   panel_style   -> WIDGET_DESIGN  ['standard', 'flat']
#
# REGRA DE PRECEDENCIA (A1): o banco e o padrao; `chatwootSettings` no site do cliente sobrescreve;
# e a tela declara a regra. Os campos sobrescreviveis estao em OVERRIDABLE_BY_SITE, que e o
# vocabulario comum entre o backend, o SDK e a tela — para que ninguem invente um terceiro nome.
module WidgetAppearanceSchema
  extend ActiveSupport::Concern

  THEMES = %w[light auto dark].freeze
  POSITIONS = %w[left right].freeze
  LAUNCHER_TYPES = %w[standard expanded_bubble].freeze
  PANEL_STYLES = %w[standard flat].freeze
  # Bloco 3.19: `default` e o balao na cor da marca, e e o padrao de fabrica de TODA inbox nova,
  # em qualquer perfil (decisao D5 — nenhuma inbox nasce com foto).
  LAUNCHER_ICONS = %w[default image agent_photo].freeze

  # O lancador fica a no maximo 200 px da quina: mais que isso e um widget perdido no meio da pagina.
  MAX_OFFSET = 200
  # O texto do lancador expandido cabe numa linha; 200 caracteres nao cabem em lancador nenhum.
  MAX_LAUNCHER_TEXT = 64

  # As opcoes de intencao nomeadas da tela inicial (plano 22 §B.4, perfil `marketing`): a NN/g mede
  # que com 3 exemplos nomeados o visitante decide em 5 s se a ferramenta serve. Duas e o minimo para
  # existir escolha; quatro e o teto antes de virar menu.
  MIN_HOME_INTENTS = 2
  MAX_HOME_INTENTS = 4
  MAX_HOME_INTENT_LABEL = 48
  # `id` e valor gravado: ingles snake_case (A2), estavel, e o que a telemetria de 4.21 agrupa.
  # `label` e o texto que o VISITANTE le — conteudo do cliente, na lingua dele, nunca i18n do produto.
  HOME_INTENT_ID_PATTERN = '^[a-z][a-z0-9_]{0,31}$'.freeze

  DEFAULTS = {
    'theme' => 'light',
    'position' => 'right',
    'offset_x' => 0,
    'offset_y' => 0,
    'launcher_type' => 'standard',
    'launcher_text' => '',
    'hide_bubble' => false,
    'panel_style' => 'standard',
    'launcher_icon' => 'default',
    # Ausente e o mesmo que vazio: a tela inicial de hoje, sem opcoes nomeadas. Sem migration,
    # sem backfill, e nenhuma inbox existente muda de comportamento (A4).
    'home_intents' => [].freeze
  }.freeze

  # O que o snippet do site pode sobrescrever, e sob que nome ele aparece no `chatwootSettings`.
  OVERRIDABLE_BY_SITE = {
    'theme' => 'darkMode',
    'position' => 'position',
    'launcher_type' => 'type',
    'launcher_text' => 'launcherTitle',
    'hide_bubble' => 'hideMessageBubble',
    'panel_style' => 'widgetStyle'
  }.freeze

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'theme' => { 'type' => 'string', 'enum' => THEMES },
      'position' => { 'type' => 'string', 'enum' => POSITIONS },
      'offset_x' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => MAX_OFFSET },
      'offset_y' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => MAX_OFFSET },
      'launcher_type' => { 'type' => 'string', 'enum' => LAUNCHER_TYPES },
      'launcher_text' => { 'type' => 'string', 'maxLength' => MAX_LAUNCHER_TEXT },
      'hide_bubble' => { 'type' => 'boolean' },
      'panel_style' => { 'type' => 'string', 'enum' => PANEL_STYLES },
      'launcher_icon' => { 'type' => 'string', 'enum' => LAUNCHER_ICONS },
      'home_intents' => {
        'type' => 'array',
        'maxItems' => MAX_HOME_INTENTS,
        'items' => {
          'type' => 'object',
          'properties' => {
            'id' => { 'type' => 'string', 'pattern' => HOME_INTENT_ID_PATTERN },
            'label' => { 'type' => 'string', 'minLength' => 1, 'maxLength' => MAX_HOME_INTENT_LABEL }
          },
          'required' => %w[id label],
          'additionalProperties' => false
        }
      }
    },
    'additionalProperties' => false
  }.freeze

  module_function

  # Plano 22 §B.4: "2 a 4 opcoes de intencao nomeadas". Duas regras que nao cabem em JSON Schema
  # legivel: uma opcao sozinha nao e escolha, e ids repetidos quebram a telemetria por intencao
  # (4.21) sem que o visitante veja erro nenhum. O teto de 4 e o formato ficam no SCHEMA.
  def home_intents_violations(intents)
    return [] unless intents.is_a?(Array)

    [single_intent_violation(intents), duplicated_intent_ids_violation(intents)].compact
  end

  def single_intent_violation(intents)
    return unless intents.size == 1

    I18n.t('errors.inbox.widget_config.home_intents_need_two',
           minimum: MIN_HOME_INTENTS, maximum: MAX_HOME_INTENTS)
  end

  def duplicated_intent_ids_violation(intents)
    ids = intents.filter_map { |intent| intent['id'] if intent.is_a?(Hash) }
    duplicated = ids.tally.select { |_id, count| count > 1 }.keys
    return if duplicated.empty?

    I18n.t('errors.inbox.widget_config.home_intents_duplicated_id', ids: duplicated.join(', '))
  end
end
