class MessageTemplates::Template::NpsSurvey
  pattr_initialize [:conversation!]

  def perform
    return unless should_send_nps_survey?

    # Don't reopen conversation - let it stay resolved
    # The NPS message will be sent even if conversation is resolved
    # Similar to CSAT behavior
    ActiveRecord::Base.transaction do
      message = conversation.messages.create!(nps_survey_message_params)
      create_nps_response(message)
    end
  end

  private

  delegate :contact, :account, :inbox, to: :conversation

  def should_send_nps_survey?
    return true unless blocklist_configured?

    labels_to_check = labels_to_check_for_blocklist
    blocklist_labels = nps_config['blocklist_labels'] || []

    return true if blocklist_labels.empty?

    blocklist_labels.none? { |label| labels_to_check.include?(label) }
  end

  def blocklist_configured?
    return false if nps_config.blank?
    return false if nps_config['blocklist_labels'].blank?

    true
  end

  def labels_to_check_for_blocklist
    scope = nps_config['blocklist_scope'] || 'both'
    case scope
    when 'contact'
      contact.label_list
    when 'conversation'
      conversation.label_list
    else # 'both'
      (contact.label_list + conversation.label_list).uniq
    end
  end

  def message_content
    content = nps_config['message'] || default_message
    processed_content = process_placeholders(content)
    # Remove any signature patterns that might have been added
    processed_content.gsub(/\*\*:\s*/, '').gsub(/\n\n--\s*\n\n\*\*:.*$/m, '').strip
  end

  def default_message
    company_name = account.name || 'our company'
    "On a scale of 0 to 10, how likely are you to recommend #{company_name} to a friend or colleague?"
  end

  def process_placeholders(content)
    content
      .gsub('{contact_name}', contact.name || 'you')
      .gsub('{agent_name}', conversation.assignee&.name || 'our team')
      .gsub('{inbox_name}', inbox.name || 'support')
      .gsub('{company_name}', account.name || 'our company')
      .gsub('{conversation_id}', conversation.display_id.to_s)
      .gsub('{brand_name}', account.name || 'nossa empresa')
  end

  def nps_survey_message_params
    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content_type: nps_message_content_type,
      content: message_content,
      content_attributes: content_attributes
    }
  end

  def nps_config
    inbox.nps_config || {}
  end

  def nps_message_content_type
    return :text if %w[Channel::Whatsapp Channel::WebWidget Channel::Api].include?(inbox.channel_type)

    :input_nps
  end

  def content_attributes
    { nps_survey: true }
  end

  def create_nps_response(message)
    nps_response = NpsResponse.create!(
      account_id: conversation.account_id,
      conversation_id: conversation.id,
      contact_id: conversation.contact_id,
      inbox_id: conversation.inbox_id,
      assigned_agent_id: conversation.assignee_id,
      status: :sent,
      sent_at: Time.current,
      metadata: {
        message_id: message.id,
        channel_type: inbox.channel_type
      }
    )

    # Create activity message
    create_sent_activity_message
    nps_response
  end

  def create_sent_activity_message
    content = I18n.t('conversations.activity.nps.sent', default: 'NPS survey sent')
    activity_message_params = {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
    ::Conversations::ActivityMessageJob.perform_later(conversation.id, activity_message_params) if content
  end
end
