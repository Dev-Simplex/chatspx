# Prepara a conta quando o app "Captador" é ligado em Integrações: a label que marca as conversas
# abertas pelo Captador e as definições de atributo, para que CNPJ e id do lead apareçam no painel
# da conversa e nos filtros. Idempotente: religar o app não duplica nada.
class Crm::Captador::SetupService
  LABEL = 'captador'.freeze
  ATTRIBUTES = [
    { attribute_key: 'cnpj', attribute_display_name: 'CNPJ', attribute_model: 'contact_attribute' },
    { attribute_key: 'captador_lead_id', attribute_display_name: 'Lead no Captador', attribute_model: 'contact_attribute' },
    { attribute_key: 'captador_lead_id', attribute_display_name: 'Lead no Captador', attribute_model: 'conversation_attribute' }
  ].freeze

  def initialize(hook)
    @account = hook.account
  end

  def setup
    @account.labels.find_or_create_by!(title: LABEL)
    ATTRIBUTES.each do |attrs|
      @account.custom_attribute_definitions
              .create_with(attribute_display_name: attrs[:attribute_display_name], attribute_display_type: 'text')
              .find_or_create_by!(attribute_key: attrs[:attribute_key], attribute_model: attrs[:attribute_model])
    end
  end
end
