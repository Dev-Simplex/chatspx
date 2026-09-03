# frozen_string_literal: true

# Bloco 5.11/5.12 — o que a base SABE sobre a pessoa, no vocabulario canonico de T-C5.3.
#
# Existe separado do payload de proposito: o log de auditoria precisa dizer "tinhamos `em` e `ph` e
# NAO mandamos" — e isso exige saber o que estava disponivel, nao so o que saiu. Uma lista fixa de
# campos suprimidos mentiria na direcao oposta: diria que suprimimos o telefone de um contato que
# nunca teve telefone.
#
# Os valores CRUS ficam aqui e nao viajam: quem os transforma e o destino, sempre pelo
# `IdentityNormalizer`, sempre normalizando antes de hashear — e so quando `PiiPolicy` permitir,
# que hoje e nunca.
class Tracking::PersonData
  def initialize(contact)
    @contact = contact
  end

  # { 'em' => 'Alguem@Exemplo.com', 'ph' => '+5511...', 'fn' => 'Maria', ... }, so o que existe.
  def available
    @available ||= {
      'em' => contact&.email.presence,
      'ph' => contact&.phone_number.presence,
      'fn' => first_name,
      'ln' => last_name,
      'ct' => attribute('city'),
      'st' => attribute('state') || attribute('region'),
      'zp' => attribute('postal_code') || attribute('zipcode'),
      'country' => attribute('country_code') || attribute('country')
    }.compact
  end

  def available_names
    available.keys
  end

  def [](canonical_name)
    available[canonical_name.to_s]
  end

  private

  attr_reader :contact

  # `Contact#name` e um campo so. A Meta quer `fn` e `ln` separados, e o corte no primeiro espaco e
  # o que a propria doc dela sugere para bases que guardam nome cheio.
  def first_name
    parts = name_parts
    parts.first
  end

  def last_name
    parts = name_parts
    parts.length > 1 ? parts.last : nil
  end

  def name_parts
    @name_parts ||= contact&.name.to_s.strip.split(/\s+/)
  end

  def attribute(key)
    return nil unless contact&.additional_attributes.is_a?(Hash)

    contact.additional_attributes[key].presence
  end
end
