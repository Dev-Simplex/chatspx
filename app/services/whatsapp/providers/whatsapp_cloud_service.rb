class Whatsapp::Providers::WhatsappCloudService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    @message = message
    # Passthrough genérico de interativo (F3): qualquer ação do Flow que monte um objeto `interactive`
    # Meta e o persista em content_attributes['interactive_payload'] (cta_url, location_request, Flow
    # nativo) sai por AQUI — um POST cru, sem caminho hardcoded por tipo. Precede os ramos
    # attachment/input_select(F1)/text, que NÃO carregam essa chave.
    return send_raw_interactive(phone_number, message) if message.content_attributes&.dig('interactive_payload').present?

    if message.attachments.present?
      attachment = message.attachments.first
      case attachment.file_type.to_s
      when 'location'
        send_location_message(phone_number, attachment)
      when 'contact'
        send_contacts_message(phone_number, message, attachment)
      else
        send_attachment_message(phone_number, message)
      end
    elsif message.content_type == 'input_select'
      send_interactive_text_message(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  end

  def send_template(phone_number, template_info, message)
    template_body = template_body_parameters(template_info)

    request_body = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual', # Only individual messages supported (not group messages)
      to: phone_number,
      type: 'template',
      template: template_body
    }

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: request_body.to_json
    )

    process_response(response, message)
  end

  def sync_templates
    # ensuring that channels with wrong provider config wouldn't keep trying to sync templates
    whatsapp_channel.mark_message_templates_updated
    templates = fetch_whatsapp_templates("#{business_account_path}/message_templates?access_token=#{whatsapp_channel.provider_config['api_key']}")
    whatsapp_channel.update(message_templates: templates, message_templates_last_updated: Time.now.utc) if templates.present?
  end

  def fetch_whatsapp_templates(url)
    response = HTTParty.get(url)
    return [] unless response.success?

    next_url = next_url(response)

    return response['data'] + fetch_whatsapp_templates(next_url) if next_url.present?

    response['data']
  end

  def next_url(response)
    response['paging'] ? response['paging']['next'] : ''
  end

  def validate_provider_config?
    response = HTTParty.get("#{business_account_path}/message_templates?access_token=#{whatsapp_channel.provider_config['api_key']}")
    response.success?
  end

  def api_headers
    { 'Authorization' => "Bearer #{whatsapp_channel.provider_config['api_key']}", 'Content-Type' => 'application/json' }
  end

  def create_csat_template(template_config)
    csat_template_service.create_template(template_config)
  end

  def delete_csat_template(template_name = nil)
    template_name ||= CsatTemplateNameService.csat_template_name(whatsapp_channel.inbox.id)
    csat_template_service.delete_template(template_name)
  end

  def get_template_status(template_name)
    csat_template_service.get_template_status(template_name)
  end

  def media_url(media_id)
    "#{api_base_path}/v13.0/#{media_id}"
  end

  # Marca a ultima mensagem recebida como lida E mostra "digitando..." pro cliente
  # (ate ~25s, ou ate enviarmos uma mensagem). Best-effort: nunca levanta.
  # Requer Graph API v21.0+ (o endpoint padrao de mensagens usa v13.0, que nao
  # suporta typing_indicator).
  def send_typing_indicator(source_id, show_typing = true)
    return if source_id.blank?

    body = { messaging_product: 'whatsapp', status: 'read', message_id: source_id }
    body[:typing_indicator] = { type: 'text' } if show_typing

    HTTParty.post(
      "#{api_base_path}/v21.0/#{whatsapp_channel.provider_config['phone_number_id']}/messages",
      headers: api_headers,
      body: body.to_json
    )
  rescue StandardError => e
    Rails.logger.warn("[WhatsApp Cloud] typing_indicator falhou: #{e.class}: #{e.message}")
    nil
  end

  private

  def csat_template_service
    @csat_template_service ||= Whatsapp::CsatTemplateService.new(whatsapp_channel)
  end

  def api_base_path
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end

  # TODO: See if we can unify the API versions and for both paths and make it consistent with out facebook app API versions
  def phone_id_path
    "#{api_base_path}/v13.0/#{whatsapp_channel.provider_config['phone_number_id']}"
  end

  def business_account_path
    "#{api_base_path}/v14.0/#{whatsapp_channel.provider_config['business_account_id']}"
  end

  def send_text_message(phone_number, message)
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        to: phone_number,
        text: { body: message.outgoing_content },
        type: 'text'
      }.to_json
    )

    process_response(response, message)
  end

  # WhatsApp Cloud API — Location message.
  # Spec: https://developers.facebook.com/docs/whatsapp/cloud-api/messages/location-messages
  def send_location_message(phone_number, attachment)
    location_payload = {
      latitude: attachment.coordinates_lat,
      longitude: attachment.coordinates_long
    }
    name = attachment.fallback_title.to_s.presence
    location_payload[:name] = name if name
    location_payload[:address] = name if name

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(@message),
        to: phone_number,
        type: 'location',
        location: location_payload
      }.compact.to_json
    )

    process_response(response, @message)
  end

  # WhatsApp Cloud API — Contacts message.
  # Spec: https://developers.facebook.com/docs/whatsapp/cloud-api/messages/contacts-messages
  # We accept either a single contact saved via the share_contact controller
  # (additional_attributes.contact = { name, phone, source }) or fall back to
  # the attachment's meta.firstName / fallback_title.
  def send_contacts_message(phone_number, message, attachment)
    contact_data = (message.additional_attributes || {})['contact'] || {}
    contact_name = contact_data['name'].presence || attachment.meta&.[]('firstName').presence || attachment.fallback_title.to_s
    contact_phone = contact_data['phone'].presence || attachment.fallback_title.to_s
    digits = contact_phone.to_s.gsub(/[^\d+]/, '')
    digits = "+#{digits}" unless digits.start_with?('+')

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        to: phone_number,
        type: 'contacts',
        contacts: [{
          name: { formatted_name: contact_name, first_name: contact_name },
          phones: [{ phone: digits, type: 'CELL', wa_id: digits.gsub(/\D/, '') }]
        }]
      }.compact.to_json
    )

    process_response(response, message)
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    type = %w[image audio video].include?(attachment.file_type) ? attachment.file_type : 'document'
    type_content = {
      'link': attachment.download_url
    }
    type_content['caption'] = message.outgoing_content unless %w[audio sticker].include?(type)
    type_content['filename'] = attachment.file.filename if type == 'document'
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        :messaging_product => 'whatsapp',
        :context => whatsapp_reply_context(message),
        'to' => phone_number,
        'type' => type,
        type.to_s => type_content
      }.to_json
    )

    process_response(response, message)
  end

  def error_message(response)
    # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response
    response.parsed_response&.dig('error', 'message')
  end

  def template_body_parameters(template_info)
    template_body = {
      name: template_info[:name],
      language: {
        policy: 'deterministic',
        code: template_info[:lang_code]
      }
    }

    # Enhanced template parameters structure
    # Note: Legacy format support (simple parameter arrays) has been removed
    # in favor of the enhanced component-based structure that supports
    # headers, buttons, and authentication templates.
    #
    # Expected payload format from frontend:
    # {
    #   processed_params: {
    #     body: { '1': 'John', '2': '123 Main St' },
    #     header: {
    #       media_url: 'https://...',
    #       media_type: 'image',
    #       media_name: 'filename.pdf' # Optional, for document templates only
    #     },
    #     buttons: [{ type: 'url', parameter: 'otp123456' }]
    #   }
    # }
    # This gets transformed into WhatsApp API component format:
    # [
    #   { type: 'body', parameters: [...] },
    #   { type: 'header', parameters: [...] },
    #   { type: 'button', sub_type: 'url', parameters: [...] }
    # ]
    template_body[:components] = template_info[:parameters] || []

    template_body
  end

  def whatsapp_reply_context(message)
    reply_to = message.content_attributes[:in_reply_to_external_id]
    return nil if reply_to.blank?

    {
      message_id: reply_to
    }
  end

  # Passthrough F3: POSTa um objeto `interactive` Meta JÁ montado pela ação do Flow
  # (content_attributes['interactive_payload']). Um único caminho serve cta_url,
  # location_request_message e flow (nativo) — zero acoplamento entre os tipos. Espelha
  # send_interactive_text_message, mas o payload vem pronto em vez de derivado dos items.
  def send_raw_interactive(phone_number, message)
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        to: phone_number,
        interactive: message.content_attributes['interactive_payload'],
        type: 'interactive'
      }.to_json
    )

    process_response(response, message)
  end

  def send_interactive_text_message(phone_number, message)
    payload = create_payload_based_on_items(message)

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        to: phone_number,
        interactive: payload,
        type: 'interactive'
      }.to_json
    )

    process_response(response, message)
  end
end
