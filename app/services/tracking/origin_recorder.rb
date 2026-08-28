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

    writing = from_catalog(Tracking::OriginAttributes::CONVERSATION_BASE_KEYS)
    writing.each { |base_key, value| conversation.custom_attributes[Tracking::OriginAttributes.conversation_key(base_key)] = value }
    writing
  end

  # Roda em `after_create`. Duas regras, nesta ordem:
  #
  #  1. **Só chave do catálogo do contato** (`CONTACT_BASE_KEYS`), que exclui os click ids de
  #     propósito — a razão está em `origin_attributes.rb:13`: click id é da SESSÃO, não da
  #     pessoa, e a regra do plano para ele no contato (C9, "mais recente não vazio") é o oposto
  #     de write-once. Gravar `first_gclid` custava duas coisas ao mesmo tempo: a chave não é
  #     semeada pelo 1.18, então o valor entrava no banco e **não aparecia no painel**; e o
  #     `first_*` passava a mentir, porque o `first_origin_kind=busca_paga` da 1ª visita saía
  #     acompanhado do `fbclid` da 2ª (write-once é por chave, e a chave ainda não existia).
  #  2. **Write-once por chave**: chave que já existe no contato não é tocada, nem quando a nova
  #     conversa traz valor diferente — é isso que `first_` quer dizer.
  def record_contact
    return {} if parsed.blank? || !campaign_signal?

    contact = conversation.contact
    return {} if contact.blank?

    new_keys = from_catalog(Tracking::OriginAttributes::CONTACT_BASE_KEYS).each_with_object({}) do |(base_key, value), acc|
      key = Tracking::OriginAttributes.contact_key(base_key)
      acc[key] = value unless contact.custom_attributes.key?(key)
    end
    return {} if new_keys.blank?

    contact.update!(custom_attributes: contact.custom_attributes.merge(new_keys))
    new_keys
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

  # Quem manda no que se escreve é o CATÁLOGO (1.18), não o parser. A inversão é o ponto: chave
  # sem definição grava e some da vista, que é a mesma experiência de não existir [R19 §D.3].
  # Assim, campo novo só chega ao painel depois de entrar no catálogo — onde a definição nasce.
  def from_catalog(base_keys)
    base_keys.each_with_object({}) do |base_key, acc|
      value = parsed[base_key]
      acc[base_key] = value if value.present?
    end
  end

  def referer
    conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes['referer'] : nil
  end

  # Sem sinal de campanha, o contato não é carimbado: gravar `first_origin_kind=nao_disponivel` na
  # primeira visita travaria o write-once para sempre, e a campanha que trouxe a pessoa na segunda
  # visita nunca mais entraria. A conversa continua registrando o que houve; o contato espera.
  #
  # O click id conta como sinal mesmo não sendo gravado no contato, e não é contradição: uma
  # visita só com `?gclid=` veio mesmo de anúncio pago, e `first_origin_kind=busca_paga` é
  # verdade sobre a pessoa. O que não é dela é o identificador daquele clique.
  def campaign_signal?
    (Tracking::OriginAttributes::UTM_KEYS + Tracking::OriginAttributes::CLICK_ID_KEYS).any? { |key| parsed[key].present? }
  end
end
