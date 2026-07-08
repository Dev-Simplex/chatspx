# frozen_string_literal: true

# Direct WAHA outbound dispatcher for message types the external WAHA Chatwoot
# App does not handle correctly (location, contact). Bypasses the inbox webhook
# pipeline and calls Waha::ApiService REST endpoints straight from Rails.
#
# WAHA docs:
# - Location: https://waha.devlike.pro/docs/how-to/send-messages/#location
# - Contact vCard: https://waha.devlike.pro/docs/how-to/send-messages/#contact-vcard
class Waha::OutboundSpecialMessageService
  def initialize(message)
    @message = message
    @inbox = message.inbox
    @conversation = message.conversation
  end

  # Returns true when this service successfully (or attempted to) dispatch
  # the message via WAHA REST. Returns false when not applicable — caller should
  # then fall through to the normal webhook delivery.
  def perform
    return false unless applicable?
    # Idempotência: se já temos source_id, a mensagem já foi enviada via WAHA REST.
    # Protege contra reentrância (status updates: sent → delivered → read) e retries.
    return false if @message.source_id.present?

    # Free-form interactive messages (buttons / list) carry no attachment — the
    # options live in content_attributes['items'].
    if interactive_message?
      send_interactive
      return true
    end

    dispatch_attachment
  rescue Waha::ApiService::Error => e
    Rails.logger.error("[Waha::OutboundSpecialMessageService] failed: #{e.message}")
    @message.update(status: :failed, external_error: e.message)
    true # we handled it (failed) — don't fall back to webhook to avoid double send
  end

  private

  def dispatch_attachment
    attachment = @message.attachments.first
    case attachment.file_type.to_s
    when 'location'
      send_location(attachment)
      true
    when 'contact'
      send_contact(attachment)
      true
    else
      false
    end
  end

  def applicable?
    return false unless @message.outgoing? && !@message.private?
    return false unless @inbox&.channel_type == 'Channel::Api'
    return false if @inbox.waha_session_name.blank?

    interactive_message? || attachment_applicable?
  end

  def attachment_applicable?
    file_type = @message.attachments.first&.file_type.to_s
    %w[location contact].include?(file_type)
  end

  # An outgoing interactive menu: content_type input_select with a non-empty
  # items list. WAHA WEBJS renders <=3 items as reply buttons, more as a list.
  def interactive_message?
    @message.content_type == 'input_select' && interactive_items.present?
  end

  def interactive_items
    items = @message.content_attributes&.dig('items') || @message.content_attributes&.dig(:items)
    Array(items).select { |i| i.is_a?(Hash) && (i['title'] || i[:title]).present? }
  end

  def waha
    @waha ||= Waha::ApiService.new
  end

  # Normaliza source_id (que pode ser LID ou phone-JID com '9 extra' fora do
  # canônico) via WAHA /api/contacts/check-exists, que retorna o chatId real
  # cadastrado no WhatsApp. Resolve simultaneamente:
  #  - LID → phone JID (LIDs não recebem mensagem)
  #  - números BR antigos sem "9 extra" (ex: DDD 66) ficando 12 vs 13 dígitos
  #  - Channel::Api genérico onde source_id é UUID — fallback para contact.phone_number
  def chat_id
    return @chat_id if defined?(@chat_id)

    raw = @conversation.contact_inbox&.source_id.to_s
    digits = candidate_digits(raw)
    digits = candidate_digits(@conversation.contact&.phone_number.to_s) if digits.blank?

    raise Waha::ApiService::Error, "destinatário sem número válido (source_id=#{raw.inspect})" if digits.blank?

    check = waha.check_contact_exists(session_name: @inbox.waha_session_name, phone: digits)
    exists = if check.is_a?(Hash)
               check['numberExists'].nil? ? check[:numberExists] : check['numberExists']
             end
    resolved = check.is_a?(Hash) ? (check['chatId'] || check[:chatId]) : nil

    raise Waha::ApiService::Error, "WhatsApp não cadastrado: #{digits}" if exists == false

    @chat_id = resolved.presence || (raw.include?('@') ? raw : "#{digits}@c.us")
  end

  # Extrai dígitos só se a string parecer JID WhatsApp ou telefone real.
  # UUIDs (com hífens, alfanuméricos) retornam blank.
  def candidate_digits(str)
    return '' if str.blank?

    return str.split('@').first.to_s.gsub(/\D/, '') if /@(c\.us|s\.whatsapp\.net|lid)\z/.match?(str)

    cleaned = str.gsub(/\D/, '')
    return cleaned if str.match?(/\A\+?\d[\d\s\-()]*\z/) && cleaned.length >= 10

    ''
  end

  def send_location(attachment)
    resp = waha.send_location(
      session: @inbox.waha_session_name,
      chat_id: chat_id,
      latitude: attachment.coordinates_lat.to_f,
      longitude: attachment.coordinates_long.to_f
    )
    mark_sent(resp)
  end

  def send_contact(attachment)
    contact_data = (@message.additional_attributes || {})['contact'] || {}
    name = contact_data['name'].presence || attachment.meta&.[]('firstName').presence || attachment.fallback_title.to_s
    phone = contact_data['phone'].presence || attachment.fallback_title.to_s

    # Sempre via /api/sendText com vCard inline — /api/sendContactVcard quebra
    # na engine GoWS PLUS (TypeError interno mesmo com payload correto).
    resp = waha.send_text_with_vcard(
      session: @inbox.waha_session_name,
      chat_id: chat_id,
      name: name,
      phone: phone
    )
    mark_sent(resp)
  end

  # Interactive menus are delivered as a native WhatsApp POLL. On the GOWS PLUS
  # engine, list/button messages are accepted (201) but WhatsApp renders them
  # inconsistently (Meta deprecated them for non-official senders) — polls are
  # the only "tap an option" format that renders reliably for every recipient.
  # The recipient taps an option to vote; the vote comes back as a poll update.
  #
  # WhatsApp polls require 2..12 unique options. When the menu carries fewer than
  # 2 distinct options we can't build a poll, so we fall back to a numbered text
  # menu (always works) instead of silently failing.
  def send_interactive
    body = @message.outgoing_content.presence || @message.content.to_s
    options = poll_options(interactive_items)

    if options.length < 2
      mark_sent(send_text_menu(body, interactive_items))
    else
      mark_sent(send_interactive_poll(body, options))
    end
  end

  # Distinct, non-empty option labels, capped at WhatsApp's 12-option limit.
  def poll_options(items)
    items.map { |item| item_title(item) }.map(&:strip).reject(&:blank?).uniq.first(12)
  end

  def send_interactive_poll(body, options)
    waha.send_poll(
      session: @inbox.waha_session_name,
      chat_id: chat_id,
      name: body.presence || I18n.t('conversations.messages.whatsapp.poll_default_name', default: 'Escolha uma opção'),
      options: options,
      multiple_answers: false
    )
  end

  # Fallback for degenerate menus (0/1 distinct option): a plain numbered text
  # menu. Always renders on any WhatsApp.
  def send_text_menu(body, items)
    lines = items.map.with_index(1) { |item, idx| "#{idx}. #{item_title(item)}" }
    text = [body.presence, *lines].compact.join("\n")
    waha.send_text(session: @inbox.waha_session_name, chat_id: chat_id, text: text)
  end

  def item_title(item)
    (item['title'] || item[:title]).to_s
  end

  def mark_sent(response = nil)
    return if @message.destroyed?

    ext_id = response.is_a?(Hash) ? (response['id'] || response[:id]) : nil
    @message.update(status: :sent, source_id: ext_id.presence)
  end
end
