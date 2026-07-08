# frozen_string_literal: true

# Service responsible for deciding if a message is a response to an active NPS survey.
# When it returns true, the conversation should NOT be reopened (prevents reopening for valid/invalid NPS responses).
#
# Rules aligned with inbox configuration (nps_config):
# - Only considers it an "NPS response" if there is an active survey: status :sent, answered_at nil.
# - Survey expiration uses nps_config['expiration_hours'] (via NpsResponse#expired?).
# - Message must be after the survey was sent (created_at >= sent_at).
# - Content must clearly look like a response attempt (score 0-10, or "skip" patterns).
# - When in doubt, does NOT block reopening (reopens so the customer can be served).
#
# Flow: Message created -> reopen_conversation -> calls prevent_reopen?(message) ->
#   if true: conversation stays resolved; NpsSurveyListener then processes and marks NPS as answered.
#
class NpsSurveys::ReopenGuard
  pattr_initialize [:message!]

  # Returns true if the message is a response to an active NPS survey and the conversation should NOT reopen.
  def prevent_reopen? # rubocop:disable Metrics/CyclomaticComplexity
    return false unless message.incoming?
    return false unless message.conversation.resolved?

    active_nps = find_active_nps_response
    return false unless active_nps

    return false if nps_expired_or_message_before_survey?(active_nps)
    return false if agent_responded_after_nps?(active_nps)
    return true if content_looks_like_nps_response?
    return true if content_looks_like_wrong_or_skip_nps_attempt?

    false
  end

  private

  delegate :conversation, :content, :content_attributes, :created_at, to: :message

  def find_active_nps_response
    conversation.nps_responses
                .where(status: :sent, answered_at: nil)
                .order(created_at: :desc)
                .first
  end

  def agent_responded_after_nps?(active_nps)
    nps_message_id = active_nps.metadata&.dig('message_id')
    return false unless nps_message_id

    conversation.messages
                .where(message_type: :outgoing)
                .where('id > ?', nps_message_id)
                .where.not("content_attributes ->> 'nps_survey' = 'true'")
                .exists?
  end

  def nps_expired_or_message_before_survey?(active_nps)
    return true if active_nps.expired?
    return true if active_nps.sent_at.present? && created_at.present? && created_at < active_nps.sent_at

    false
  end

  # Widget sends score via content_attributes; channels (WhatsApp etc.) send text in content.
  def content_looks_like_nps_response?
    return true if content_attributes.dig('submitted_values', 'nps_response', 'score').present?

    normalized = normalize_content(content)
    return true if NpsSurveys::ScoreValidator.validate_and_extract(normalized).present?
    return true if nps_score_like_content?(normalized)

    false
  end

  # Invalid or "skip" responses should also not reopen (e.g., "11", "don't know", "?", "abc").
  # Fonte unica compartilhada com o ResponseBuilder (NpsSurveys::ScoreValidator).
  def content_looks_like_wrong_or_skip_nps_attempt?(text = content)
    NpsSurveys::ScoreValidator.looks_like_failed_attempt?(text)
  end

  def nps_score_like_content?(normalized)
    return false if normalized.blank?

    # Delegate to ScoreValidator — single source of truth for score extraction
    NpsSurveys::ScoreValidator.validate_and_extract(normalized).present?
  end

  # Remove invisible characters and normalize encoding for reliable detection (e.g., "10" with zero-width chars).
  def normalize_content(text)
    return '' if text.blank?

    text.to_s
        .encode('UTF-8', invalid: :replace, undef: :replace)
        .strip
        .gsub(/[\u200B-\u200D\uFEFF]/, '')
  end
end
