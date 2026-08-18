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

  DEFAULTS = {
    'theme' => 'light',
    'position' => 'right',
    'offset_x' => 0,
    'offset_y' => 0,
    'launcher_type' => 'standard',
    'launcher_text' => '',
    'hide_bubble' => false,
    'panel_style' => 'standard',
    'launcher_icon' => 'default'
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
      'launcher_icon' => { 'type' => 'string', 'enum' => LAUNCHER_ICONS }
    },
    'additionalProperties' => false
  }.freeze
end
