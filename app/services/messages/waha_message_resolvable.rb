# frozen_string_literal: true

# Shared WAHA message-resolution helpers used by both UpdateContentService (edit)
# and DeleteContentService (delete-for-everyone). Both need to map a Chatwoot
# Message onto its WhatsApp message id before talking to WAHA, share the same
# chat_id derivation, and the same "is this a WAHA inbox / sent by me" checks.
#
# Including classes are expected to expose an `@message` instance variable.
module Messages::WahaMessageResolvable # rubocop:disable Metrics/ModuleLength
  SUPPORTED_CHANNEL = 'Channel::Api'
  # Window (seconds) used when matching Chatwoot messages against WAHA history.
  # Mirrors WhatsApp's ~15 minute edit limitation but is reused for lookup on delete too.
  LOOKUP_WINDOW_SECONDS = 900
  # Tight window for the timestamp-only fallback. Within 60s of send + only one
  # fromMe candidate in that window is treated as a definitive match even if content diverges.
  TIGHT_TIME_WINDOW_SECONDS = 60

  AGENT_PREFIX_REGEX = /\A\*[^*]*\*:\n/

  # Match strategy (in order):
  # 1. Exact content equality (fast path) within LOOKUP_WINDOW_SECONDS
  # 2. Whitespace-normalized equality
  # 3. Substring containment after normalization (covers stray escape chars / partial diffs)
  # 4. Timestamp-only when there is exactly ONE fromMe candidate inside TIGHT_TIME_WINDOW_SECONDS
  MATCH_STRATEGIES = %i[exact_match? normalized_match? substring_match?].freeze

  private

  def waha_inbox?
    inbox.channel_type == SUPPORTED_CHANNEL && inbox.waha_session_name.present?
  end

  def sent_by_current_user?
    Current.user && @message.sender_id == Current.user.id && @message.sender_type == 'User'
  end

  # Returns the WAHA message ID to use. Uses source_id if available, otherwise
  # fetches from the WAHA API. Raises ArgumentError when no match can be found.
  def resolve_waha_message_id
    return @message.source_id if @message.source_id.present?

    find_waha_message_id_from_api
  end

  def find_waha_message_id_from_api # rubocop:disable Metrics/AbcSize
    Rails.logger.info("[#{self.class.name}] Looking up WAHA message for message_id=#{@message.id}, chat_id=#{chat_id}, " \
                      "session=#{inbox.waha_session_name}, content=#{@message.content.to_s.truncate(100).inspect}")

    messages = fetch_waha_messages
    return nil if messages.nil?

    match = pick_match(collect_fromme_candidates(messages))
    raise_no_match!(messages.size) if match.nil?

    extract_waha_id(match)
  rescue Waha::ApiService::Error => e
    Rails.logger.error("[#{self.class.name}] WAHA API error: #{e.message}")
    raise ArgumentError, "WAHA API error: #{e.message}"
  end

  def fetch_waha_messages
    messages = Waha::ApiService.new.get_messages(inbox.waha_session_name, chat_id, limit: 20)
    unless messages.is_a?(Array)
      Rails.logger.warn("[#{self.class.name}] WAHA API returned non-array: #{messages.class} => #{messages.inspect.truncate(500)}")
      return nil
    end
    Rails.logger.info("[#{self.class.name}] WAHA returned #{messages.size} messages")
    messages
  end

  def raise_no_match!(message_count)
    Rails.logger.warn("[#{self.class.name}] No match found among #{message_count} messages " \
                      "for content=#{@message.content.to_s.truncate(100).inspect}")
    raise ArgumentError, 'Message not found on WhatsApp. It may still be sending.'
  end

  def extract_waha_id(match)
    waha_id = match.dig('key', 'id') || match['id']
    Rails.logger.info("[#{self.class.name}] Match found! waha_message_id=#{waha_id}")
    waha_id
  end

  def collect_fromme_candidates(messages)
    created_at_ts = @message.created_at.to_i
    messages.filter_map do |m|
      next unless from_me?(m)

      build_candidate(m, created_at_ts)
    end
  end

  def from_me?(message_hash)
    message_hash['fromMe'] == true || message_hash['key']&.[]('fromMe') == true
  end

  def build_candidate(message_hash, created_at_ts)
    body = message_hash['body'] || message_hash['text'] || message_hash.dig('content', 'text') || ''
    timestamp = message_hash['timestamp'].to_i
    time_diff = (timestamp - created_at_ts).abs
    candidate = {
      raw: message_hash,
      body: body,
      stripped_body: body.sub(AGENT_PREFIX_REGEX, ''),
      timestamp: timestamp,
      time_diff: time_diff,
      time_match: time_diff < LOOKUP_WINDOW_SECONDS
    }
    Rails.logger.info("[#{self.class.name}] Candidate fromMe message: body=#{body.truncate(100).inspect}, " \
                      "timestamp=#{timestamp}, chatwoot_ts=#{created_at_ts}, time_diff=#{time_diff}s, " \
                      "time_match=#{candidate[:time_match]}")
    candidate
  end

  # Returns the matched candidate's raw WAHA message hash, or nil.
  def pick_match(candidates)
    in_window = candidates.select { |c| c[:time_match] }
    return nil if in_window.empty?

    targets = match_targets

    match = MATCH_STRATEGIES.lazy.filter_map do |strategy|
      in_window.find { |c| send(strategy, c, targets) }
    end.first

    match ||= timestamp_only_match(in_window)
    match&.[](:raw)
  end

  def match_targets
    targets = [@message.content]
    previous = @message.content_attributes&.[]('previous_content')
    targets << previous if previous.present?
    targets.compact
  end

  def exact_match?(candidate, targets)
    targets.any? { |t| candidate[:body] == t || candidate[:stripped_body] == t }
  end

  def normalized_match?(candidate, targets)
    body_norm = normalize_for_match(candidate[:stripped_body])
    targets.any? { |t| normalize_for_match(t) == body_norm }
  end

  def substring_match?(candidate, targets)
    body_norm = normalize_for_match(candidate[:stripped_body])
    return false if body_norm.blank?

    targets.any? do |t|
      target_norm = normalize_for_match(t)
      next false if target_norm.blank?

      body_norm.include?(target_norm) || target_norm.include?(body_norm)
    end
  end

  def timestamp_only_match(in_window)
    tight = in_window.select { |c| c[:time_diff] < TIGHT_TIME_WINDOW_SECONDS }
    return nil unless tight.size == 1

    Rails.logger.info("[#{self.class.name}] Falling back to timestamp-only match (single fromMe candidate within tight window)")
    tight.first
  end

  # Strip residual escape backslashes that some clients emit (e.g. Shift+Enter producing
  # a stray "\\n" the WhatsApp server normalizes away) and collapse all whitespace runs.
  def normalize_for_match(text)
    return '' if text.nil?

    text.gsub(/\\(?=\s|\z)/, '').gsub(/\s+/, ' ').strip
  end

  def inbox
    @inbox ||= @message.conversation.inbox
  end

  def chat_id
    # Prefer the explicit WAHA chat ID stored in contact custom attributes
    waha_chat_id = @message.conversation.contact.custom_attributes&.[]('waha_whatsapp_chat_id')
    return waha_chat_id if waha_chat_id.present?

    # Fallback: contact_inbox source_id (may be the WhatsApp JID)
    jid = @message.conversation.contact_inbox.source_id
    return jid if jid.present? && jid.include?('@')

    # Last resort: build from phone number
    phone = @message.conversation.contact.phone_number.to_s.gsub(/\D/, '')
    "#{phone}@c.us"
  end
end
