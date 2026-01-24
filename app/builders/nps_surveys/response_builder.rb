class NpsSurveys::ResponseBuilder
  pattr_initialize [:message]

  def perform
    return unless message.incoming?

    conversation = message.conversation
    nps_response = find_active_nps_response(conversation)
    return unless nps_response

    score = extract_score_from_message
    
    if score.nil?
      send_invalid_response_message(nps_response)
      return
    end

    process_nps_response(nps_response, score)
  end

  private

  def find_active_nps_response(conversation)
    # Buscar o NPS response mais recente com status "sent" que ainda não foi respondido
    nps_response = conversation.nps_responses
      .where(status: :sent)
      .where(answered_at: nil)
      .order(created_at: :desc)
      .first
    
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
    ::Conversations::ActivityMessageJob.perform_later(conversation, activity_message_params) if content
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
      .where('created_at >= ?', 5.minutes.ago)
      .exists?
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
    message.content.present? ? message.content : nil
  end

  def should_send_thank_you?(nps_response)
    nps_config = nps_response.inbox.nps_config || {}
    thank_you_message = nps_config['thank_you_message']
    thank_you_message.present?
  end

  def send_thank_you_message(nps_response)
    inbox = nps_response.inbox
    nps_config = inbox.nps_config || {}
    thank_you_message = nps_config['thank_you_message'] || I18n.t('conversations.templates.nps_thank_you', default: 'Obrigado pela sua avaliação!')
    
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

  def send_invalid_response_message(nps_response)
    inbox = nps_response.inbox
    nps_config = inbox.nps_config || {}
    invalid_message = nps_config['invalid_response_message'] || 
                     I18n.t('conversations.templates.nps_invalid_response', 
                            default: 'Por favor, responda com um número de 0 a 10.')

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
