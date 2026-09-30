# frozen_string_literal: true

# Mensagem de saída que carrega um cartão de contato: anexo `file_type: :contact` mais
# `additional_attributes['contact']`, que é o que o envio de cada canal lê
# (Whatsapp::Providers::WhatsappCloudService#send_contacts_message e
# Waha::OutboundSpecialMessageService#send_contact).
#
# Usado pelo compartilhamento manual (share_contact) e pela ferramenta enviar_contato_unidade, para
# os dois não divergirem no formato que o envio espera.
#
# O anexo é construído ANTES do save!: o envio dispara no after_create_commit da mensagem, e criar
# o anexo numa segunda etapa seria corrida com o job de envio.
class Messages::ContactCardBuilder
  # `contact`: { name:, phone:, source:, ref: } — o que vai em additional_attributes['contact'].
  def initialize(conversation:, sender:, contact:, additional_attributes: {})
    @conversation = conversation
    @sender = sender
    @contact = contact.compact
    @additional_attributes = additional_attributes
  end

  def perform
    message = @conversation.messages.build(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :outgoing,
      content: "#{@contact[:name]} — #{@contact[:phone]}",
      sender: @sender,
      additional_attributes: @additional_attributes.merge(contact: @contact)
    )
    message.attachments.build(
      account_id: @conversation.account_id,
      file_type: :contact,
      fallback_title: @contact[:phone],
      meta: { firstName: @contact[:name], lastName: '' }
    )
    message.save!
    message
  end
end
