class Instagram::BaseSendService < Base::SendOnChannelService
  pattr_initialize [:message!]

  # Tetos da Meta: 30 imagens por mensagem e 10 cards por generic template.
  MAX_IMAGES_PER_MESSAGE = 30
  MAX_CARDS = 10

  private

  delegate :additional_attributes, to: :contact

  def perform_reply
    # A vitrine SUBSTITUI texto e anexo: o card já carrega título, foto e botão. Quem não
    # desenha card não chega aqui e recebe o `content` como texto.
    return send_cards if channel.supports_card_carousel? && cards.any?

    send_attachments if message.attachments.present?
    send_content if message.content.present?
  rescue StandardError => e
    handle_error(e)
  end

  def send_attachments
    return send_grouped_images if group_images?

    message.attachments.each do |attachment|
      send_message(attachment_message_params(attachment))
    end
  end

  # Agrupa só quando TODO anexo é imagem: `attachments[]` aceita `image` e mais nada, e um
  # tipo diferente no meio derrubaria a requisição inteira. Nesse caso o envio cai no
  # caminho de sempre, um POST por anexo.
  def group_images?
    return false unless channel.supports_multi_image_message?
    return false if message.attachments.size < 2

    message.attachments.all? { |attachment| attachment_type(attachment) == 'image' }
  end

  def send_grouped_images
    message.attachments.each_slice(MAX_IMAGES_PER_MESSAGE) do |group|
      send_message(multi_image_message_params(group))
    end
  end

  def multi_image_message_params(attachments)
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        attachments: attachments.map { |attachment| { type: 'image', payload: { url: attachment_url(attachment) } } }
      }
    }

    merge_human_agent_tag(params)
  end

  def cards
    list = message.content_attributes&.dig('cards')
    list.is_a?(Array) ? list : []
  end

  def send_cards
    send_message(cards_message_params)
  end

  def cards_message_params
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        attachment: {
          type: 'template',
          payload: {
            template_type: 'generic',
            elements: cards.first(MAX_CARDS).map { |card| card_element(card) }
          }
        }
      }
    }

    merge_human_agent_tag(params)
  end

  # Traduz o card agnóstico pro formato do Instagram. Card sem botão vira só a vitrine
  # (foto + texto), sem clique de volta.
  def card_element(card)
    card = card.with_indifferent_access
    element = { title: card[:title], image_url: card[:image_url], subtitle: card[:subtitle] }.compact_blank
    button = card[:button]
    return element if button.blank?

    element.merge(buttons: [{ type: 'postback', title: button[:title], payload: button[:payload] }])
  end

  def send_content
    send_message(message_params)
  end

  def handle_error(error)
    ChatwootExceptionTracker.new(error, account: message.account, user: message.sender).capture_exception
  end

  def message_params
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        text: message.outgoing_content
      }
    }

    merge_human_agent_tag(params)
  end

  def attachment_message_params(attachment)
    params = {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        attachment: {
          type: attachment_type(attachment),
          payload: {
            url: attachment_url(attachment)
          }
        }
      }
    }

    merge_human_agent_tag(params)
  end

  def process_response(response, message_content)
    parsed_response = response.parsed_response
    if response.success? && parsed_response['error'].blank?
      message.update!(source_id: parsed_response['message_id'])
      parsed_response
    else
      external_error = external_error(parsed_response)
      Rails.logger.error("Instagram response: #{external_error} : #{message_content}")
      Messages::StatusUpdateService.new(message, 'failed', external_error).perform
      nil
    end
  end

  def external_error(response)
    error_message = response.dig('error', 'message')
    error_code = response.dig('error', 'code')

    # https://developers.facebook.com/docs/messenger-platform/error-codes
    # Access token has expired or become invalid. This may be due to a password change,
    # removal of the connected app from Instagram account settings, or other reasons.
    channel.authorization_error! if error_code == 190

    "#{error_code} - #{error_message}"
  end

  # A Meta busca a mídia pela URL. Anexo sem arquivo local (só `external_url`) devolvia
  # string vazia no `download_url` e a requisição saía com url em branco.
  def attachment_url(attachment)
    attachment.download_url.presence || attachment.external_url
  end

  def attachment_type(attachment)
    return attachment.file_type if %w[image audio video file].include? attachment.file_type

    'file'
  end

  # Methods to be implemented by child classes
  def send_message(message_content)
    raise NotImplementedError, 'Subclasses must implement send_message'
  end

  def merge_human_agent_tag(params)
    raise NotImplementedError, 'Subclasses must implement merge_human_agent_tag'
  end
end
