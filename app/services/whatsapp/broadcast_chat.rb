# frozen_string_literal: true

# CHAT-170: o WhatsApp entrega como chat `...@broadcast` duas coisas que não são atendimento:
# os status/stories dos contatos (`status@broadcast`) e as listas de transmissão de terceiros
# (`<id>@broadcast`). A app `chatwoot` da WAHA grava esse JID no contato (`identifier` e
# `custom_attributes`); o `source_id` do contact_inbox costuma ser um UUID e não ajuda.
module Whatsapp::BroadcastChat
  SUFFIX = '@broadcast'

  def self.contact?(contact, source_id = nil)
    return false if contact.blank?

    custom = contact.custom_attributes.is_a?(Hash) ? contact.custom_attributes : {}
    [source_id, contact.identifier, *custom.values_at('waha_whatsapp_chat_id', 'waha_whatsapp_jid')]
      .any? { |jid| jid.to_s.end_with?(SUFFIX) }
  end
end
