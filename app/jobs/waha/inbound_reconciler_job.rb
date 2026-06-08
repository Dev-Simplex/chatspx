# frozen_string_literal: true

# Safety net for the WAHA freeze #1482 (API stays UP but webhook/chatwoot-app
# stops delivering inbound). Periodically polls each WAHA session for recent
# inbound messages and re-injects any that never reached Chatwoot.
#
# CONSERVATIVE BY DESIGN — this job can duplicate a message if dedup fails, so:
# - it is OFF unless WAHA_RECONCILER_ENABLED is truthy (run in homologacao first);
# - dedup is source_id-first, then a content+timestamp heuristic (same logic as
#   Waha::MessageStatusSyncService) to close the race window;
# - MVP is TEXT-ONLY (media is skipped, see TODO);
# - rescue is PER CHAT because GOWS #1968 returns empty/422 for some groups.
class Waha::InboundReconcilerJob < ApplicationJob
  queue_as :low

  # How far back to look on each poll. Generous enough to cover a freeze window
  # without scanning the whole history.
  LOOKBACK = 15.minutes
  # Per-inbox cooldown so overlapping cron ticks don't double-scan.
  COOLDOWN = 2.minutes
  # Heuristic match window (seconds) — mirrors MessageStatusSyncService.
  TIMESTAMP_WINDOW = 900
  MESSAGES_PER_CHAT = 30

  def perform
    return unless enabled?

    Inbox.where.not(waha_session_name: [nil, '']).find_each do |inbox|
      reconcile_inbox(inbox)
    rescue StandardError => e
      Rails.logger.warn("[InboundReconciler] inbox #{inbox.id} failed: #{e.message}")
    end
  end

  private

  def enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('WAHA_RECONCILER_ENABLED', false))
  end

  def reconcile_inbox(inbox)
    cache_key = "waha_inbound_reconciler:inbox:#{inbox.id}"
    return if Rails.cache.exist?(cache_key)

    Rails.cache.write(cache_key, true, expires_in: COOLDOWN)

    since = LOOKBACK.ago.to_i
    inbox.conversations.includes(:contact, :contact_inbox).find_each do |conversation|
      reconcile_chat(inbox, conversation, since)
    rescue StandardError => e
      # Per-chat rescue: GOWS #1968 returns empty/422 for some groups; one bad
      # chat must not abort the whole inbox.
      Rails.logger.warn("[InboundReconciler] conv #{conversation.id} (inbox #{inbox.id}) failed: #{e.message}")
    end
  end

  def reconcile_chat(inbox, conversation, since)
    chat_id = chat_id_for(conversation)
    return if chat_id.blank?

    waha_messages = fetch_inbound(inbox.waha_session_name, chat_id, since)
    return if waha_messages.blank?

    waha_messages.reject { |m| m['fromMe'] }.each do |waha_msg|
      reinject_message(conversation, waha_msg)
    end
  end

  def fetch_inbound(session_name, chat_id, since)
    Waha::ApiService.new.get_messages(
      session_name, chat_id,
      limit: MESSAGES_PER_CHAT, timestamp_gte: since, from_me: false
    )
  end

  def reinject_message(conversation, waha_msg)
    waha_id = extract_message_id(waha_msg)
    content = extract_content(waha_msg)
    timestamp = waha_msg['timestamp'].to_i
    # MVP: text-only. TODO: handle media (attachments) once dedup is validated in prod.
    return if content.blank?
    return if already_present?(conversation, waha_id, content, timestamp)

    inject(conversation, waha_id, content, timestamp)
  end

  # source_id-first dedup, then content+timestamp heuristic to close the race
  # window where the inbound is mid-flight without a source_id yet.
  def already_present?(conversation, waha_id, content, timestamp)
    return true if waha_id.present? && Message.find_by(source_id: waha_id).present?
    return false if timestamp.zero?

    conversation.messages.incoming
                .where(created_at: window(timestamp))
                .any? { |m| content_matches?(m.content, content) }
  end

  def inject(conversation, waha_id, content, timestamp)
    Messages::MessageBuilder.new(
      nil, conversation,
      {
        content: content,
        message_type: :incoming,
        source_id: waha_id,
        # WAHA sends a unix epoch (seconds); the column is a datetime, so wrap it
        # in Time.zone.at — a raw Integer makes save! raise an invalid-literal error.
        external_created_at: timestamp.zero? ? nil : Time.zone.at(timestamp)
      }
    ).perform
    Rails.logger.info("[InboundReconciler] reinjected inbound #{waha_id} into conv #{conversation.id}")
  end

  def window(timestamp)
    base = Time.zone.at(timestamp)
    (base - TIMESTAMP_WINDOW.seconds)..(base + TIMESTAMP_WINDOW.seconds)
  end

  def content_matches?(chatwoot_content, waha_content)
    return false if chatwoot_content.blank? || waha_content.blank?

    a = chatwoot_content.strip
    b = waha_content.strip
    a.include?(b) || b.include?(a)
  end

  def chat_id_for(conversation)
    contact = conversation.contact
    return if contact.blank?

    chat_id = contact.custom_attributes['waha_whatsapp_chat_id'] if contact.custom_attributes.present?
    return chat_id if chat_id.present?

    jid = conversation.contact_inbox&.source_id
    return jid if jid.to_s.include?('@')

    phone = contact.phone_number.to_s.gsub(/\D/, '')
    phone.present? ? "#{phone}@c.us" : nil
  end

  def extract_message_id(waha_msg)
    waha_msg.dig('key', 'id') || waha_msg['id']
  end

  def extract_content(waha_msg)
    waha_msg['body'] || waha_msg['text'] || waha_msg.dig('content', 'text')
  end
end
