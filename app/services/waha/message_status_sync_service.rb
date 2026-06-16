# frozen_string_literal: true

class Waha::MessageStatusSyncService
  ACK_TO_STATUS = { 1 => 'sent', 2 => 'delivered', 3 => 'read', 4 => 'read' }.freeze

  # WAHA (engine GOWS) serializes get_messages per session and stalls past ~8
  # simultaneous reads on a single session. We cap inflight reads per session and
  # short-circuit failing sessions to protect the WAHA process under load.
  MAX_INFLIGHT_READS = 8
  INFLIGHT_TTL = 30 # seconds — staleness window; in-flight slots older than this are pruned (crash-safe)
  CIRCUIT_TTL = 60 # seconds — cool-off window after a WAHA timeout/conn error
  MESSAGES_LIMIT = 8 # small payload: limit=25 stalls on heavy chats, limit<=8 is instant
  MESSAGES_LOOKBACK = 2.hours # only recent messages — kills the heavy-history stall

  # Atomic per-session admission: prune stale slots, reject if full, else claim a
  # slot — all in one round-trip so the <=MAX_INFLIGHT_READS bound holds under races.
  # KEYS[1]=zset; ARGV: now, ttl, max, member. Returns 1 (claimed) or 0 (full).
  INFLIGHT_ACQUIRE = <<~LUA
    redis.call('ZREMRANGEBYSCORE', KEYS[1], 0, tonumber(ARGV[1]) - tonumber(ARGV[2]))
    if redis.call('ZCARD', KEYS[1]) >= tonumber(ARGV[3]) then return 0 end
    redis.call('ZADD', KEYS[1], ARGV[1], ARGV[4])
    redis.call('EXPIRE', KEYS[1], tonumber(ARGV[2]) + 5)
    return 1
  LUA

  def initialize(conversation)
    @conversation = conversation
    @inbox = conversation.inbox
  end

  def perform
    return unless waha_inbox?
    return if circuit_open?

    with_inflight_slot do
      waha_messages = fetch_waha_messages
      return if waha_messages.blank?

      sync_statuses(waha_messages)
    end
  end

  private

  def waha_inbox?
    @inbox.channel_type == 'Channel::Api' && @inbox.waha_session_name.present?
  end

  # Per-session inflight gate backed by a Redis sorted set (one member per in-flight
  # read, scored by start time). Admission is atomic (INFLIGHT_ACQUIRE), and stale
  # members from crashed workers are pruned by score on every acquire — so there is
  # no counter to underflow and no leaked slot to wedge the session. Over the cap we
  # re-enqueue with jittered backoff instead of blocking a Sidekiq thread.
  def with_inflight_slot
    now = Time.now.to_f
    member = "#{now}:#{SecureRandom.hex(6)}"
    acquired = $alfred.with do |r| # rubocop:disable Style/GlobalVars
      r.eval(INFLIGHT_ACQUIRE, keys: [inflight_key], argv: [now, INFLIGHT_TTL, MAX_INFLIGHT_READS, member])
    end

    if acquired != 1
      requeue_for_backpressure
      return
    end

    begin
      yield
    ensure
      $alfred.with { |r| r.zrem(inflight_key, member) } # rubocop:disable Style/GlobalVars
    end
  end

  def requeue_for_backpressure
    Rails.logger.info("[WAHA] status sync backpressure for session #{@inbox.waha_session_name}; re-enqueuing")
    Waha::MessageStatusSyncJob.set(wait: rand(5..14).seconds).perform_later(@conversation.id)
  end

  def fetch_waha_messages
    api = Waha::ApiService.new
    messages = api.get_messages(@inbox.waha_session_name, chat_id, limit: MESSAGES_LIMIT, timestamp_gte: MESSAGES_LOOKBACK.ago.to_i)
    close_circuit
    messages
  rescue Waha::ApiService::ConnectionError => e
    open_circuit
    Rails.logger.warn("[WAHA] status sync timeout/conn error for session #{@inbox.waha_session_name}; circuit open #{CIRCUIT_TTL}s: #{e.message}")
    nil
  rescue StandardError => e
    Rails.logger.warn("[WAHA] Failed to fetch messages for status sync: #{e.message}")
    nil
  end

  def circuit_open?
    Redis::Alfred.get(circuit_key).present?
  end

  def open_circuit
    Redis::Alfred.setex(circuit_key, '1', CIRCUIT_TTL)
  end

  def close_circuit
    Redis::Alfred.delete(circuit_key)
  end

  def circuit_key
    "waha:status_sync:circuit:#{@inbox.waha_session_name}"
  end

  def inflight_key
    "waha:read:inflight:#{@inbox.waha_session_name}"
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
