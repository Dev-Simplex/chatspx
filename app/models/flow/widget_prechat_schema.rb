# frozen_string_literal: true

# Bloco 4.02 (BK-21/22/23) — a forma de `flows.trigger_config` quando `trigger_type` e
# `widget_prechat`, e o vocabulario do CONTRATO de resolucao "qual fluxo entregar".
#
# POR QUE VALIDAR NO SERVIDOR: o controller de autoria copia o `trigger_config` CRU do cliente
# (`flows_controller.rb#assign_jsonb_attributes`). Sem este arquivo, `operator: "regex"` ou
# `priority: "alta"` gravam e so falham no navegador de um visitante real — o lugar mais caro
# possivel para descobrir o erro. A regra da onda ("validacao no servidor, com json_schemer, que
# ja e dependencia") mora aqui.
#
# POR QUE `additionalProperties` FICA ABERTO NO TOPO: `trigger_config` e a MESMA coluna de todos
# os gatilhos. Um fluxo que muda de `keyword` (ou `external_webhook`) para `widget_prechat` chega
# aqui carregando `keywords`, `conditions`, `webhook_token`. Fechar o topo transformaria a troca
# de gatilho num 422 sobre dado que o proprio produto gravou. Dentro de `url_conditions` fecha,
# porque a estrutura nasce neste bloco e nao existe legado a proteger.
module Flow::WidgetPrechatSchema
  # Operadores de URL. Sem regex de proposito: `trigger_config` e escrito pelo admin e avaliado a
  # cada conversa nova — uma expressao patologica viraria ReDoS no caminho quente.
  URL_OPERATORS = %w[contains not_contains equals starts_with ends_with].freeze

  # Como combinar as condicoes de URL entre si. Default `all` (E) — ver DEFAULTS.
  MATCH_MODES = %w[all any].freeze

  # Categorias de dispositivo. Derivadas do que o widget ja grava em
  # `conversation.additional_attributes['browser']` (device_name/platform_name) — nao ha
  # user-agent novo a coletar.
  DEVICES = %w[desktop mobile tablet].freeze

  # Teto de campos coletados por fluxo de captura (BK-23, [R06 §14.3 R14]).
  # Campo coletado == no `wait_for_reply`: e exatamente uma pergunta respondida pelo visitante.
  MAX_COLLECTED_FIELDS = 8

  # O que vale quando a chave NAO vem. Publicado porque "o que acontece na ausencia" e a metade
  # do contrato que costuma ficar so na cabeca de quem escreveu.
  DEFAULTS = {
    'inbox_ids' => [],        # [] => vale para qualquer inbox Website da conta
    'url_conditions' => [],   # [] => catch-all: casa qualquer URL, inclusive URL ausente
    'match' => 'all',         # todas as condicoes de URL precisam casar
    'utm' => {},              # {} => nao filtra por UTM
    'devices' => [],          # [] => qualquer dispositivo
    'business_hours_only' => false,
    'priority' => 0,          # desempate declarado pelo admin; maior vence
    # Bloco 6.05 — teste A/B. `nil` => o fluxo NAO participa de experimento nenhum, que e o
    # estado de toda a frota: o desempate acima decide sozinho, como sempre decidiu, e
    # nenhum evento de A/B e emitido. Contrato em Flow::AbExperiment.
    'experiment' => nil
  }.freeze

  URL_CONDITION = {
    'type' => 'object',
    'properties' => {
      'operator' => { 'type' => 'string', 'enum' => URL_OPERATORS },
      'value' => { 'type' => 'string', 'minLength' => 1, 'maxLength' => 2048 }
    },
    'additionalProperties' => false,
    'required' => %w[operator value]
  }.freeze

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'inbox_ids' => { 'type' => 'array', 'items' => { 'type' => 'integer' } },
      'url_conditions' => { 'type' => 'array', 'items' => URL_CONDITION, 'maxItems' => 20 },
      'match' => { 'type' => 'string', 'enum' => MATCH_MODES },
      'utm' => { 'type' => 'object', 'additionalProperties' => { 'type' => %w[string null] } },
      'devices' => { 'type' => 'array', 'items' => { 'type' => 'string', 'enum' => DEVICES } },
      'business_hours_only' => { 'type' => 'boolean' },
      'priority' => { 'type' => 'integer', 'minimum' => -1000, 'maximum' => 1000 },
      # 6.05 — duas variantes sao dois fluxos com a MESMA `experiment.key`. `null` e
      # aceito de proposito: e como a tela desliga o experimento sem apagar a chave.
      'experiment' => Flow::AbExperiment::SCHEMA
    },
    'additionalProperties' => true
  }.freeze

  def self.validator
    @validator ||= JSONSchemer.schema(SCHEMA)
  end

  # A mensagem cita o caminho ate o ponto errado (`url_conditions/1/operator`), e nao so
  # "invalido": quem recebe o 422 e uma tela de gatilho com varias condicoes, e um erro sem
  # endereco obriga a adivinhar qual delas esta errada. Espelha PreChatFormSchema.humanize.
  def self.humanize(error)
    pointer = error['data_pointer'].to_s.delete_prefix('/').presence || 'trigger_config'
    return "#{pointer}: falta #{Array(error.dig('details', 'missing_keys')).join(', ')}" if error['type'] == 'required'
    return "#{pointer}: valor fora dos aceitos" if error['type'] == 'enum'
    return "#{pointer}: chave nao reconhecida" if error['type'] == 'schema'

    "#{pointer}: valor invalido (#{error['type']})"
  end
end
