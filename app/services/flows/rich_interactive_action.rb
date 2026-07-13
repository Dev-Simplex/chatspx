# frozen_string_literal: true

# Extras interativos "ricos" do motor Flow (F3), além da lista/botões do F1 (Flows::InteractiveAction):
#   • send_cta_url          → botão de link  (interactive type 'cta_url')
#   • send_location_request → pedir localização (interactive type 'location_request_message')
# Misturado no Flows::ActionService, ao lado de Flows::InteractiveAction. Depende do host:
# @conversation, conversation_a_tweet?, whatsapp_cloud_inbox?, enforce_compliance!, render_liquid,
# author e message_content_attributes.
#
# A SACADA (contrato F3): passthrough genérico. Cada ação monta um objeto `interactive` Meta e o
# persiste CRU em content_attributes['interactive_payload']; o provider (WhatsappCloudService#
# send_raw_interactive) faz o POST { type:'interactive', interactive:<payload> } sem caminho
# hardcoded por tipo. content_type fica 'text' (default) — o roteamento é pelo interactive_payload,
# não pelo content_type. `interactive_payload` é chave LIVRE no content_attributes (persiste no JSON
# store; ao contrário do `items` do F1, sem o gotcha do MessageBuilder).
#
# Espelha send_message: texto de SERVIÇO livre (utility, free_form) → exige a janela de 24h (fora
# dela o enforce_compliance! levanta StepSkip). O nó send_whatsapp_flow (Flows::WhatsappFlowAction)
# reusa o MESMO wrapper (create_interactive_message). Ver plano/F3-contrato-extras-interativos.md.
module Flows::RichInteractiveAction
  RICH_BODY_LIMIT = 1024 # corpo (body.text) — mesmo teto do F1 (Meta)

  private

  # Botão de link: mensagem interativa com um único botão que abre uma URL. config =
  # { body, button_text, url, header?, footer? }. Textos aceitam Liquid; a URL é renderizada e
  # precisa ser http(s) — senão skip triável (cta_url_incomplete), nunca um envio que a Meta rejeita.
  def send_cta_url(action_params)
    return if conversation_a_tweet?

    config = Array(action_params).first.to_h.with_indifferent_access
    fields = cta_url_fields(config)

    raise Flows::StepSkip.new('inbox_not_whatsapp', 'inbox is not a WhatsApp Cloud channel') unless whatsapp_cloud_inbox?
    raise Flows::StepSkip.new('cta_url_incomplete', 'body, button_text and a valid http(s) url are required') unless cta_url_valid?(fields)

    enforce_compliance!(category: 'utility', free_form: true)
    create_interactive_message(build_cta_url_payload(fields, config))
  end

  # Pedido de localização: mensagem interativa com o botão nativo "enviar localização" (a Meta pinta
  # o botão; sem parâmetros extras). config = { body }. Guard: body presente.
  def send_location_request(action_params)
    return if conversation_a_tweet?

    config = Array(action_params).first.to_h.with_indifferent_access
    body = render_liquid(config['body'].to_s).slice(0, RICH_BODY_LIMIT)

    raise Flows::StepSkip.new('inbox_not_whatsapp', 'inbox is not a WhatsApp Cloud channel') unless whatsapp_cloud_inbox?
    raise Flows::StepSkip.new('location_request_incomplete', 'body is required') if body.blank?

    enforce_compliance!(category: 'utility', free_form: true)
    create_interactive_message(build_location_request_payload(body))
  end

  # Wrapper compartilhado (também usado por Flows::WhatsappFlowAction#send_whatsapp_flow): cria a
  # Message outgoing carregando o objeto `interactive` Meta em content_attributes['interactive_payload'].
  # content = o texto do corpo do próprio payload (body.text). content_type fica 'text' (o provider
  # roteia pelo interactive_payload). Herda autor + marcador flow_id anti-loop via message_content_attributes.
  def create_interactive_message(payload)
    params = {
      content: payload.dig(:body, :text),
      private: false,
      content_attributes: message_content_attributes.merge('interactive_payload' => payload)
    }
    Messages::MessageBuilder.new(author, @conversation.reload, params).perform
  end

  # Lê e renderiza (Liquid) os campos do cta_url. body é capado no teto da Meta; url é renderizada
  # (permite {{contact.id}} etc.) e só validada como http(s) depois, em cta_url_valid?.
  def cta_url_fields(config)
    {
      body: render_liquid(config['body'].to_s).slice(0, RICH_BODY_LIMIT),
      button_text: render_liquid(config['button_text'].to_s),
      url: render_liquid(config['url'].to_s).strip
    }
  end

  def cta_url_valid?(fields)
    fields[:body].present? && fields[:button_text].present? && valid_http_url?(fields[:url])
  end

  def build_cta_url_payload(fields, config)
    payload = {
      type: 'cta_url',
      body: { text: fields[:body] },
      action: { name: 'cta_url', parameters: { display_text: fields[:button_text], url: fields[:url] } }
    }
    payload[:header] = { type: 'text', text: render_liquid(config['header'].to_s) } if config['header'].present?
    payload[:footer] = { text: render_liquid(config['footer'].to_s) } if config['footer'].present?
    payload
  end

  def build_location_request_payload(body)
    {
      type: 'location_request_message',
      body: { text: body },
      action: { name: 'send_location' }
    }
  end

  # http(s) apenas (a Meta rejeita outros esquemas no cta_url). URI::HTTPS < URI::HTTP, então o
  # is_a? cobre os dois. Malformada → false (a guarda vira skip triável).
  def valid_http_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
end
