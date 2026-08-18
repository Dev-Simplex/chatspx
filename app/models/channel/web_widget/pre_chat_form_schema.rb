# frozen_string_literal: true

# Bloco 3.12 da Onda 2 — a forma de `channel_web_widgets.pre_chat_form_options`.
#
# POR QUE UM SCHEMA E NAO SO STRONG PARAMS: `EDITABLE_ATTRS` decide quais CHAVES
# entram; ele nao olha VALOR nenhum. Sem este arquivo, `mask: "banana"` e
# `step: 99` sobem, gravam e so quebram no navegador do visitante — que e o
# lugar mais caro possivel para descobrir o erro. A regra da onda ("validacao no
# servidor, com json_schemer, que ja e dependencia") mora aqui.
#
# POR QUE `additionalProperties` FICA ABERTO no campo: a tela antiga
# (`PreChatForm/Settings.vue:78`) grava o array inteiro de volta, incluindo o que
# ja estava la. Fechar a forma do campo transformaria qualquer chave legada de
# qualquer conta da frota num 422 no proximo save — o schema recusaria dado que
# ele mesmo nunca aceitou gravar.
#
# POR QUE NAO EXISTE `maxItems`: o teto de 8 do plano e sobre campo HABILITADO.
# O array carrega tambem todo atributo personalizado da conta com
# `enabled: false` (`helper/preChat.js#getCustomFields`), entao uma conta com 12
# atributos tem 12 entradas ha anos. `maxItems: 8` aqui seria um 422 em massa na
# frota. O teto de 8 e regra da tela (bloco 3.14) e conta `enabled`.
module Channel::WebWidget::PreChatFormSchema
  # Vocabulario unico do pre-chat: estes mesmos nomes sao os do helper de
  # front `shared/helpers/brMasks.js` (bloco 3.13). Nome que existir de um lado
  # so e campo que a tela oferece e o widget ignora.
  MASKS = %w[cpf cnpj cpf_cnpj cep uf phone].freeze

  # `junk_*` sao as tres regras anti-lixo da §B.4.3 do plano 23. Elas sao
  # SUAVES no front (avisam, nao travam o envio) — a severidade e declarada no
  # helper de front, nao aqui; o schema so decide se o nome existe.
  VALIDATORS = %w[cpf cnpj cpf_cnpj cep uf email corporate_email phone junk_name junk_phone junk_email].freeze

  CONDITION_OPERATORS = %w[is is_not contains filled].freeze

  # Teto de etapas = teto de campos. Mais etapas do que campos possiveis nao e
  # configuracao, e engano.
  MAX_STEP = 8
  MAX_TEXT_LENGTH = 160

  CONDITION = {
    'type' => 'object',
    'properties' => {
      'field' => { 'type' => 'string', 'minLength' => 1, 'maxLength' => 100 },
      'operator' => { 'type' => 'string', 'enum' => CONDITION_OPERATORS },
      'value' => { 'type' => %w[string null], 'maxLength' => 200 }
    },
    # Fechado de proposito: `show_if` nasce neste bloco, entao nao existe dado
    # legado para proteger. E o que barra `E`/`OU` aninhado, que a §B.4.4
    # deliberadamente nao entrega na primeira versao.
    'additionalProperties' => false,
    'required' => %w[field operator]
  }.freeze

  FIELD = {
    'type' => 'object',
    'properties' => {
      'step' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => MAX_STEP },
      'position' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => 99 },
      'mask' => { 'type' => %w[string null], 'enum' => MASKS + [nil, ''] },
      'validator' => { 'type' => %w[string null], 'enum' => VALIDATORS + [nil, ''] },
      'help_text' => { 'type' => %w[string null], 'maxLength' => MAX_TEXT_LENGTH },
      'error_message' => { 'type' => %w[string null], 'maxLength' => MAX_TEXT_LENGTH },
      'show_if' => CONDITION
    },
    'additionalProperties' => true
  }.freeze

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'pre_chat_message' => { 'type' => %w[string null] },
      'pre_chat_fields' => { 'type' => 'array', 'items' => FIELD }
    },
    'additionalProperties' => true
  }.freeze

  def self.validator
    @validator ||= JSONSchemer.schema(SCHEMA)
  end

  # A mensagem cita o caminho ate o campo (`pre_chat_fields/1/show_if`), e nao
  # so "invalido": quem recebe o 422 e uma tela com ate oito campos, e um erro
  # sem endereco obriga a adivinhar qual deles esta errado.
  def self.humanize(error)
    pointer = error['data_pointer'].to_s.delete_prefix('/').presence || 'pre_chat_form_options'
    return "#{pointer}: falta #{Array(error.dig('details', 'missing_keys')).join(', ')}" if error['type'] == 'required'
    return "#{pointer}: valor fora dos aceitos" if error['type'] == 'enum'
    return "#{pointer}: chave nao reconhecida" if error['type'] == 'schema'

    "#{pointer}: valor invalido (#{error['type']})"
  end
end
