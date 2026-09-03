# frozen_string_literal: true

# Bloco 1.19 — grava o que o parser leu.
#
#   conversa → `last_*`   (o que trouxe ESTA conversa)
#   contato  → `first_*`  (write-once, o que trouxe a pessoa da primeira vez)
#
# Escreve em `custom_attributes`, não em `additional_attributes` — é o caminho que o painel
# mostra e que o filtro alcança [R15 §B12.3].
class Tracking::OriginRecorder
  def initialize(conversation)
    @conversation = conversation
  end

  # Roda em `before_create`: as chaves entram no mesmo INSERT da conversa, então o painel já as
  # tem na primeira leitura — "na mesma sessão", que é o aceite.
  def record_conversation
    return {} if parsed.blank?

    parsed.each { |base_key, value| conversation.custom_attributes[Tracking::OriginAttributes.conversation_key(base_key)] = value }
    parsed
  end

  # Roda em `after_create`. Write-once **por chave**: chave que já existe no contato não é tocada,
  # nem quando a nova conversa traz valor diferente — é isso que `first_` quer dizer.
  def record_contact
    return {} if parsed.blank? || !campaign_signal?

    contact = conversation.contact
    return {} if contact.blank?

    novos = parsed.each_with_object({}) do |(base_key, value), acc|
      key = Tracking::OriginAttributes.contact_key(base_key)
      acc[key] = value unless contact.custom_attributes.key?(key)
    end
    return {} if novos.blank?

    contact.update!(custom_attributes: contact.custom_attributes.merge(novos))
    novos
  end

  # As definições precisam existir, senão o valor grava e não aparece no painel (bloco 1.18).
  def ensure_definitions
    return if parsed.blank?

    Tracking::OriginDefinitionsSeeder.new(conversation.account).perform
  end

  private

  attr_reader :conversation

  def parsed
    @parsed ||= Tracking::OriginParser.new(referer).attributes
  end

  def referer
    conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes['referer'] : nil
  end

  # Sem sinal de campanha, o contato não é carimbado: gravar `first_origin_kind=nao_disponivel` na
  # primeira visita travaria o write-once para sempre, e a campanha que trouxe a pessoa na segunda
  # visita nunca mais entraria. A conversa continua registrando o que houve; o contato espera.
  def campaign_signal?
    (Tracking::OriginAttributes::UTM_KEYS + Tracking::OriginAttributes::CLICK_ID_KEYS).any? { |key| parsed[key].present? }
  end
end
