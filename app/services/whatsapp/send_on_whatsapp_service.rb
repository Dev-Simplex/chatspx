class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    # Input NPS and CSAT surveys should always be sent as session messages
    # They are interactive messages that don't require WhatsApp templates
    if message.input_nps? || message.input_csat?
      send_session_message
      return
    end

    should_send_template_message = template_params.present? || !message.conversation.can_reply?
    if should_send_template_message
      send_template_message
    else
      send_session_message
    end
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    message_id = channel.send_template(message.conversation.contact_inbox.source_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       }, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def send_session_message
    Rails.logger.info "Whatsapp::SendOnWhatsappService: send_session_message called for message #{message.id}, phone_number: #{message.conversation.contact_inbox.source_id}"
    message_id = channel.send_message(message.conversation.contact_inbox.source_id, message)
    Rails.logger.info "Whatsapp::SendOnWhatsappService: send_session_message result: message_id=#{message_id.inspect}"
    message.update!(source_id: message_id) if message_id.present?
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
