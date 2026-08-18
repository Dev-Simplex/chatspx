# Chave nova vinda do site do cliente era gravada no jsonb e sumia.
#
# Nao e figura de linguagem, sao dois caminhos medidos:
#   painel — CustomAttributes.vue:76-89 itera sobre as DEFINICOES, nao sobre o
#            jsonb, entao chave sem definicao nunca renderiza;
#   filtro — filters/custom_attribute_filter_helper.rb:6 devolve fragmento de
#            query VAZIO sem definicao, e filters/filter_helper.rb:22-25 traduz
#            fragmento vazio em CustomFilter::InvalidAttribute. O agente que
#            tentasse filtrar por um dado que o site ja mandou recebia erro
#            dizendo que a chave nao existe.
# O dado chegava, era guardado, e ninguem via — nem na tela, nem na busca.
#
# Este servico cria a definicao que falta, uma vez, na primeira vez que a chave
# aparece.
class CustomAttributes::AutoProvisionService
  # attribute_model do CustomAttributeDefinition -> chave de STANDARD_ATTRIBUTES
  RESERVED_KEYS_BY_MODEL = {
    'contact_attribute' => :contact,
    'conversation_attribute' => :conversation,
    'company_attribute' => :company
  }.freeze

  # Mesmo formato que CustomAttributeDefinition valida (custom_attribute_definition.rb:39).
  # Chave que nao casa seria recusada no create!; aqui ela e ignorada em silencio,
  # porque o widget nao pode quebrar por causa de um nome que o site escolheu.
  ATTRIBUTE_KEY_FORMAT = /\A[\p{L}\p{N}_.\-]+\z/

  def initialize(account:, attribute_model:, custom_attributes:)
    @account = account
    @attribute_model = attribute_model.to_s
    @custom_attributes = custom_attributes
  end

  def perform
    return if @account.blank?
    return unless RESERVED_KEYS_BY_MODEL.key?(@attribute_model)
    return if provisionable.blank?

    provisionable.each { |key, value| provision(key, value) }
  end

  private

  def provisionable
    @provisionable ||= begin
      candidates = normalized_attributes.reject { |key, _value| skip_key?(key) }
      candidates.blank? ? {} : candidates.except(*existing_keys(candidates.keys))
    end
  end

  def normalized_attributes
    return {} if @custom_attributes.blank?

    @custom_attributes.to_h.stringify_keys
  rescue StandardError
    {}
  end

  def skip_key?(key)
    key.blank? || reserved_keys.include?(key) || !ATTRIBUTE_KEY_FORMAT.match?(key)
  end

  def reserved_keys
    @reserved_keys ||= CustomAttributeDefinition::STANDARD_ATTRIBUTES.fetch(RESERVED_KEYS_BY_MODEL[@attribute_model], [])
  end

  def existing_keys(keys)
    @account.custom_attribute_definitions
            .where(attribute_model: @attribute_model, attribute_key: keys)
            .pluck(:attribute_key)
  end

  def provision(key, value)
    @account.custom_attribute_definitions.create!(
      attribute_key: key,
      attribute_display_name: key.tr('_.-', '   ').squish.upcase_first,
      attribute_display_type: display_type_for(value),
      attribute_model: @attribute_model,
      attribute_description: I18n.t('custom_attributes.auto_provisioned.description')
    )
  rescue ActiveRecord::RecordNotUnique
    # Corrida: outra requisicao commitou a mesma chave entre o nosso SELECT e o
    # INSERT. O indice unico (attribute_key, attribute_model, account_id) e quem
    # garante que sobra uma so — nao ha nada a fazer aqui alem de seguir.
    nil
  rescue ActiveRecord::RecordInvalid => e
    # Auto-provisionar e conveniencia. Se falhar, o atributo ainda foi gravado
    # no jsonb; o que nao pode acontecer e o widget do cliente receber 500.
    Rails.logger.warn("[CustomAttributes::AutoProvisionService] #{@attribute_model} #{key}: #{e.message}")
    nil
  end

  def display_type_for(value)
    case value
    when Numeric then :number
    when TrueClass, FalseClass then :checkbox
    else :text
    end
  end
end
