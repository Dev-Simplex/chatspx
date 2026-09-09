class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    should_send_template_message = template_params.present? || !message.conversation.can_reply?
    if should_send_template_message
      send_template_message
    else
      send_session_message
    end
  end

  def send_template_message
    params = revealed_template_params
    return if params.nil?

    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    deliver_template(name, namespace, lang_code, processed_parameters)
  end

  def deliver_template(name, namespace, lang_code, parameters)
    message_id = channel.send_template(message.conversation.contact_inbox.source_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: parameters
                                       }, message)
    return if message_id.blank?

    message.update!(source_id: message_id)
    # A mensagem saiu: o valor real já cumpriu a função e some do banco, ficando só a
    # máscara. Só depois do envio, porque é daqui que o payload da Meta é montado.
    Spx::SecretTemplateParams.forget!(message)
  end

  # Os parâmetros com o valor real, para montar o payload. Template comum passa direto.
  #
  # `nil` quer dizer "não dá para enviar": existe blob sigiloso e ele não decifrou. Nesse
  # caso a mensagem FALHA em vez de seguir, porque seguir mandaria a máscara como se fosse
  # o código, e o cliente receberia algo inválido sem ninguém saber por quê.
  def revealed_template_params
    Spx::SecretTemplateParams.reveal(template_params)
  rescue Spx::SecretTemplateParams::RevealError => e
    message.update!(status: :failed, external_error: e.message)
    nil
  end

  def send_session_message
    message_id = channel.send_message(message.conversation.contact_inbox.source_id, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
