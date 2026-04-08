class NpsSurveys::ResponseBuilder
  pattr_initialize [:message]

  def perform
    return unless message.incoming?

    conversation = message.conversation
    nps_response = find_active_nps_response(conversation)
    return unless nps_response
    return if agent_responded_after_nps?(conversation, nps_response)

    score = extract_score_from_message

    if score.nil?
      # Only send "invalid response" for short messages that look like NPS attempts
      # (e.g. "onze", "abc", "?"), and cap at 2 retries to avoid annoying loops.
      send_invalid_response_message(nps_response) if looks_like_nps_attempt? && retry_count_within_limit?(nps_response)
      return
    end

    process_nps_response(nps_response, score)
  end

  private

  def agent_responded_after_nps?(conversation, nps_response)
    nps_message_id = nps_response.metadata&.dig('message_id')
    return false unless nps_message_id

    conversation.messages
                .where(message_type: :outgoing)
                .where('id > ?', nps_message_id)
                .where.not("content_attributes ->> 'nps_survey' = 'true'")
                .exists?
  end

  def find_active_nps_response(conversation)
    # Find the most recent NPS response with status "sent" that has not yet been answered
    nps_response = conversation.nps_responses
                               .where(status: :sent)
                               .where(answered_at: nil)
                               .order(created_at: :desc)
                               .first

    return nil if nps_response.blank?
    return nil if nps_response.expired?

    nps_response
  end

  def extract_score_from_message
    # Try to get score from content_attributes first (widget submission)
    score = message.content_attributes.dig('submitted_values', 'nps_response', 'score')
    return score.to_i if score.present? && valid_score?(score.to_i)

    # Try to extract from message content (text response)
    score = NpsSurveys::ScoreValidator.validate_and_extract(message.content)
    return score if score.present? && valid_score?(score)

    nil
  end

  def valid_score?(score)
    score.is_a?(Integer) && score >= 0 && score <= 10
  end

  def process_nps_response(nps_response, score)
    comment = extract_comment

    # Update NPS response first to mark it as answered
    # This prevents conversation from reopening when response_to_active_survey? is checked
    nps_response.update!(
      score: score,
      comment: comment,
      status: :responded,
      answered_at: Time.current
    )

    # Create activity message (only if one doesn't already exist for this NPS response)
    create_responded_activity_message(nps_response, score) unless activity_message_exists?(nps_response, score)

    # Optionally send thank you message
    send_thank_you_message(nps_response) if should_send_thank_you?(nps_response)

    nps_response
  end

  def create_responded_activity_message(nps_response, score)
    content = I18n.t('conversations.activity.nps.responded',
                     score: score,
                     default: "NPS survey responded with score #{score}")
    activity_message_params = {
      account_id: nps_response.account_id,
      inbox_id: nps_response.inbox_id,
      message_type: :activity,
      content: content
    }
    conversation = nps_response.conversation
    ::Conversations::ActivityMessageJob.perform_later(conversation.id, activity_message_params) if content
  end

  def activity_message_exists?(nps_response, score)
    # Check if an activity message with the same content was created recently (within last 5 minutes)
    # This prevents duplicate activity messages when the job is retried
    expected_content = I18n.t('conversations.activity.nps.responded',
                              score: score,
                              default: "NPS survey responded with score #{score}")
    conversation = nps_response.conversation
    conversation.messages
                .where(message_type: :activity)
                .where(content: expected_content)
                .exists?(['created_at >= ?', 5.minutes.ago])
  end

  def extract_comment
    # Try to get comment from content_attributes first
    comment = message.content_attributes.dig('submitted_values', 'nps_response', 'comment')
    return comment if comment.present?

    # If no score was found in content, the entire message might be a comment
    # But we should only treat it as comment if it's not a score
    score_in_content = NpsSurveys::ScoreValidator.validate_and_extract(message.content)
    return nil if score_in_content.present?

    # If message doesn't contain a score, it might be a comment
    (message.content.presence)
  end

  def should_send_thank_you?(nps_response)
    nps_config = nps_response.inbox.nps_config || {}
    thank_you_message = nps_config['thank_you_message']
    thank_you_message.present?
  end

  def send_thank_you_message(nps_response)
    inbox = nps_response.inbox
    nps_config = inbox.nps_config || {}
    thank_you_message = nps_config['thank_you_message'] || I18n.t('conversations.templates.nps_thank_you', default: 'Thank you for your feedback!')

    # Remove any signature patterns that might have been added
    thank_you_message = thank_you_message.gsub(/\*\*:\s*/, '').gsub(/\n\n--\s*\n\n\*\*:.*$/m, '').strip

    conversation = nps_response.conversation
    # Create message without signature by setting content_attributes to skip signature
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content_type: :text,
      content: thank_you_message,
      content_attributes: { skip_signature: true }
    )
  end

  MAX_INVALID_RETRIES = 2

  # Cap retries: count incoming messages after the NPS survey that didn't produce a valid score.
  # After 2 failed attempts, stop sending "invalid response" to avoid annoying the customer.
  def retry_count_within_limit?(nps_response)
    nps_message_id = nps_response.metadata&.dig('message_id')
    return true unless nps_message_id

    failed_attempts = message.conversation.messages
                             .where(message_type: :incoming)
                             .where('id > ?', nps_message_id)
                             .where('id < ?', message.id)
                             .count
    failed_attempts < MAX_INVALID_RETRIES
  end

  # Short messages that look like failed NPS attempts (number out of range, single char, "?", etc.)
  # We send "invalid response" only for these — not for normal conversation messages.
  def looks_like_nps_attempt?
    text = NpsSurveys::ScoreValidator.normalize(message.content)
    return false if text.blank?
    return false if text.length > 25

    # Bare number outside 0-10 range (e.g. "11", "100", "-1")
    return true if text.match?(/\A\s*-?\d+\s*\z/)

    # Short skip/confusion patterns (single char, punctuation, "nao sei", etc.)
    short_patterns = [
      /\A(n[ãa]o\s*)?sei\z/i,
      %r{\An/a\z}i,
      /\A\?+\z/,
      /\A\.+\z/,
      /\A(nao|não)\z/i,
      /\A[a-z]\z/i,
      /\A[\s\?\.,!\-]+\z/
    ]
    short_patterns.any? { |p| text.match?(p) }
  end

  def send_invalid_response_message(nps_response)
    inbox = nps_response.inbox
    nps_config = inbox.nps_config || {}
    invalid_message = nps_config['invalid_response_message'] ||
                      I18n.t('conversations.templates.nps_invalid_response',
                             default: 'Please respond with a number from 0 to 10.')

    conversation = nps_response.conversation
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content_type: :text,
      content: invalid_message
    )
  end
end
