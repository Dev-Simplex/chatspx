# Como uma violacao de JSON Schema vira uma frase que o administrador entende (blocos 3.02, 3.18, 3.20).
#
# O `json_schemer` devolve `data_pointer` + `type` — util para um log, inutil para quem esta na tela.
# Este modulo traduz os dois em "tem valor invalido em <campo>: <o que ele esperava>", nos dois idiomas.
module WidgetSchemaErrorMessage
  # Cada violacao de schema vira uma frase que NOMEIA o campo e diz o que ele espera. O mapa evita
  # um `case` de nove ramos e deixa obvio o que acontece com um tipo de erro ainda nao mapeado.
  SCHEMA_DETAIL_BUILDERS = {
    'enum' => ->(error) { ['detail_enum', { allowed: Array(error['schema']['enum']).join(', ') }] },
    'required' => ->(error) { ['detail_required', { keys: Array(error.dig('details', 'missing_keys')).join(', ') }] },
    'minimum' => ->(error) { ['detail_minimum', { limit: error['schema']['minimum'] }] },
    'maximum' => ->(error) { ['detail_maximum', { limit: error['schema']['maximum'] }] },
    'minLength' => ->(error) { ['detail_min_length', { count: error['schema']['minLength'] }] },
    'maxLength' => ->(error) { ['detail_max_length', { count: error['schema']['maxLength'] }] },
    'maxItems' => ->(error) { ['detail_max_items', { count: error['schema']['maxItems'] }] },
    'schema' => ->(_error) { ['detail_unknown_field', {}] }
  }.freeze

  # Tipo nao mapeado cai no nome do proprio tipo — 'boolean', 'integer', 'object'.
  SCHEMA_DETAIL_FALLBACK = ->(error) { ['detail_type', { type: error['type'] }] }

  module_function

  # Ponto de entrada: um erro do json_schemer entra, uma frase sai.
  def for(error)
    I18n.t('errors.inbox.widget_config.schema_violation',
           field: schema_error_field(error),
           detail: schema_error_detail(error))
  end

  # `data_pointer` vem como "/triggers/0/desktop/value"; o caminho sem a barra inicial e o que o
  # administrador reconhece na tela. Vazio significa que o erro e do objeto inteiro.
  def schema_error_field(error)
    pointer = error['data_pointer'].to_s.delete_prefix('/')
    pointer.presence || 'root'
  end

  def schema_error_detail(error)
    # Um enum que responde "valor nao permitido (aceitos: discreet, bold)" a quem tentou `aggressive`
    # em celular esconde a razao. A recusa e do schema (A15), mas a explicacao tem de vir junto.
    return I18n.t('errors.inbox.widget_config.detail_mobile_aggressive') if mobile_auto_open_attempt?(error)

    key, options = SCHEMA_DETAIL_BUILDERS.fetch(error['type'], SCHEMA_DETAIL_FALLBACK).call(error)

    I18n.t("errors.inbox.widget_config.#{key}", **options)
  end

  def mobile_auto_open_attempt?(error)
    error['data_pointer'] == '/approach_mobile' && error['data'] == 'aggressive'
  end
end
