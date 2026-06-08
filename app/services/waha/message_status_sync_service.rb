# frozen_string_literal: true

class Waha::MessageStatusSyncService
  ACK_TO_STATUS = { 1 => 'sent', 2 => 'delivered', 3 => 'read', 4 => 'read' }.freeze

  def initialize(conversation)
    @conversation = conversation
    @inbox = conversation.inbox
  end

  def perform
    return unless waha_inbox?

    waha_messages = fetch_waha_messages
    return if waha_messages.blank?

    sync_statuses(waha_messages)
  end

  private

  def waha_inbox?
    @inbox.channel_type == 'Channel::Api' && @inbox.waha_session_name.present?
  end

  def fetch_waha_messages
    api = Waha::ApiService.new
    api.get_messages(@inbox.waha_session_name, chat_id, limit: 20)
  rescue StandardError => e
    Rails.logger.warn("[WAHA] Failed to fetch messages for status sync: #{e.message}")
    nil
  end

  def sync_statuses(waha_messages)
    @outgoing_messages = @conversation.messages
                                      .includes(:attachments)
                                      .where(message_type: :outgoing, status: %w[sent delivered]).to_a
    return if @outgoing_messages.empty?

    waha_messages.select { |m| m['fromMe'] }.each { |waha_msg| sync_single_message(waha_msg) }
  end

  def sync_single_message(waha_msg)
    status = ACK_TO_STATUS[waha_msg['ack'].to_i]
    waha_id = extract_message_id(waha_msg)
    return if status.blank? || waha_id.blank?

    message = find_matching_message(@outgoing_messages, waha_msg, waha_id)
    return unless message

    backfill_source_id(message, waha_id)
    Messages::StatusUpdateService.new(message, status).perform
  end

  def backfill_source_id(message, waha_id)
    message.update!(source_id: waha_id) if message.source_id.blank?
  end

  def find_matching_message(outgoing_messages, waha_msg, waha_id)
    # Match by source_id first (most reliable)
    by_source = outgoing_messages.find { |m| m.source_id == waha_id }
    return by_source if by_source

    waha_timestamp = waha_msg['timestamp'].to_i
    return if waha_timestamp.zero?

    match_by_content(outgoing_messages, waha_msg, waha_timestamp) ||
      match_by_media(outgoing_messages, waha_msg, waha_timestamp)
  end

  # Match by content + timestamp (text messages), same logic as UpdateContentService
  def match_by_content(outgoing_messages, waha_msg, waha_timestamp)
    waha_content = extract_content(waha_msg)
    return if waha_content.blank?

    outgoing_messages.find do |m|
      content_matches?(m.content, waha_content) && timestamp_matches?(m.created_at, waha_timestamp)
    end
  end

  # Match media (audio/video/image/doc) by attachment + timestamp.
  # Midia sem legenda nao tem content -> antes nunca casava e a mensagem ficava presa em
  # 'sent' sem source_id MESMO quando entregue. Casamos a mensagem outgoing com anexo, sem
  # texto e ainda sem source_id, mais proxima no tempo -> backfill de source_id + status real
  # (delivered/read). So confirma entrega quando o WAHA REPORTA a midia; nunca marca falha
  # (evita falso-positivo em midia sem legenda).
  def match_by_media(outgoing_messages, waha_msg, waha_timestamp)
    return unless waha_media_message?(waha_msg)

    outgoing_messages
      .select { |m| m.content.blank? && m.source_id.blank? && m.attachments.present? }
      .select { |m| timestamp_matches?(m.created_at, waha_timestamp) }
      .min_by { |m| (m.created_at.to_i - waha_timestamp).abs }
  end

  def waha_media_message?(waha_msg)
    return true if waha_msg['hasMedia']

    %w[image audio video document ptt voice sticker].include?(waha_msg['type'].to_s.downcase)
  end

  def content_matches?(chatwoot_content, waha_content)
    return false if chatwoot_content.blank? || waha_content.blank?

    chatwoot_clean = chatwoot_content.strip
    waha_clean = waha_content.strip
    chatwoot_clean.include?(waha_clean) || waha_clean.include?(chatwoot_clean)
  end

  def timestamp_matches?(created_at, waha_timestamp)
    (created_at.to_i - waha_timestamp).abs < 900
  end

  def extract_message_id(waha_msg)
    waha_msg.dig('key', 'id') || waha_msg['id']
  end

  def extract_content(waha_msg)
    waha_msg['body'] || waha_msg['text'] || waha_msg.dig('content', 'text')
  end

  def chat_id
    contact = @conversation.contact
    waha_chat_id = contact.custom_attributes&.[]('waha_whatsapp_chat_id')
    return waha_chat_id if waha_chat_id.present?

    jid = @conversation.contact_inbox&.source_id
    return jid if jid.present? && jid.include?('@')

    phone = contact.phone_number.to_s.gsub(/\D/, '')
    "#{phone}@c.us"
  end
end
