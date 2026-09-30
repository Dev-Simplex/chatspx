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

    return if template_fora_do_canal?(name, lang_code)

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
    resolve_conversa_de_disparo
  end

  # A conversa que NASCEU deste disparo sai da fila. Conversa que já existia antes fica
  # como está, mesmo que ninguém tenha falado nela: a #519 da Fábrica é assim, existe desde
  # a véspera e serve para empurrar relatório em PDF.
  #
  # Não se perde nada: só mensagem de ENTRADA reabre conversa resolvida, então se o cliente
  # responder ela volta sozinha para a fila.
  #
  # O marcador no Current existe para o encerramento não mentir o motivo: sem ele, o
  # ActivityMessageHandler cai no ramo de auto-resolução por inatividade e escreve
  # "resolvida pelo sistema por ter 0 minutos de inatividade", que é falso.
  def resolve_conversa_de_disparo
    return unless Spx::SecretTemplateParams.protected?(message)
    return if message.conversation.resolved?
    return unless Spx::SecretTemplateParams.born_from_dispatch?(message)

    Current.secret_dispatch_resolve = true
    message.conversation.update!(status: :resolved)
  ensure
    Current.secret_dispatch_resolve = nil
  end

  # O template existe NESTE numero? Cada numero e um WABA proprio, e o mesmo texto costuma
  # existir nos dois com nomes diferentes (na Fabrica, `ae1a2_iniciaratendimentosuport` e
  # `54b13_iniciaratendimentosuport`). Mandar o do vizinho volta da Meta como
  # `(#132001) Template name does not exist in the translation`, que nao diz nada a quem
  # atende.
  #
  # A checagem de cima parece cobrir isso e NAO cobre: o `name` que o processor devolve vem
  # dos parametros que a tela mandou, nao do template encontrado no canal. Ou seja, ele
  # nunca fica em branco por template inexistente, e a mensagem seguia para a Meta com
  # `components` vazio. Medido na Fabrica em 10/09.
  def template_fora_do_canal?(name, lang_code)
    return false if channel.message_templates.blank?

    existe = channel.message_templates.any? do |t|
      t['name'] == name && (lang_code.blank? || t['language'].to_s.casecmp?(lang_code.to_s))
    end
    return false if existe

    message.update!(status: :failed,
                    external_error: I18n.t('errors.whatsapp.template_outside_channel',
                                           name: name, phone_number: channel.phone_number))
    true
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
