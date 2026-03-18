class NpsSurveyService
  def initialize(conversation:, mode: nil)
    @conversation = conversation
    @mode = mode || 'auto'
  end

  def perform
    Rails.logger.info "NpsSurveyService: Starting for conversation #{conversation.id}, mode: #{mode}"

    # Reload inbox association to ensure we have the latest NPS configuration
    # This is important because the inbox config may have been updated after the conversation was loaded
    conversation.association(:inbox).reload if conversation.association(:inbox).loaded?
    conversation.association(:contact).reload if conversation.association(:contact).loaded?

    Rails.logger.info "NpsSurveyService: Inbox #{inbox.id}, nps_survey_enabled: #{inbox.nps_survey_enabled}, nps_config: #{inbox.nps_config.inspect}"

    # Check if blocked by labels first and create dismissed record
    if blocked_by_labels?
      Rails.logger.info "NpsSurveyService: Conversation #{conversation.id} is blocked by labels"
      handle_blocked_nps
      return
    end

    unless should_send_nps_survey?
      Rails.logger.info "NpsSurveyService: Should not send NPS survey for conversation #{conversation.id} (check logs above for details)"
      create_nps_not_sent_activity_message_if_applicable
      return
    end

    Rails.logger.info "NpsSurveyService: All checks passed, sending NPS survey for conversation #{conversation.id}"

    if within_messaging_window?
      Rails.logger.info "NpsSurveyService: Within messaging window, creating NPS survey message"
      ::MessageTemplates::Template::NpsSurvey.new(conversation: conversation).perform
      Rails.logger.info "NpsSurveyService: NPS survey message created successfully"
    else
      Rails.logger.info "NpsSurveyService: Outside messaging window, creating activity message"
      create_nps_not_sent_activity_message
    end
  rescue StandardError => e
    Rails.logger.error "NpsSurveyService failed for conversation #{conversation.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Don't raise - fail silently to avoid breaking the conversation flow
  end

  private

  attr_reader :conversation, :mode

  delegate :inbox, :contact, to: :conversation

  def should_send_nps_survey?
    Rails.logger.info "NpsSurveyService: Checking conditions for conversation #{conversation.id}:"
    
    nps_enabled_result = nps_enabled?
    Rails.logger.info "NpsSurveyService:   nps_enabled? = #{nps_enabled_result}"
    
    conversation_allows_result = conversation_allows_nps?
    Rails.logger.info "NpsSurveyService:   conversation_allows_nps? = #{conversation_allows_result} (conversation.status = #{conversation.status}, is_tweet? = #{conversation.tweet?})"
    
    nps_already_sent_result = nps_already_sent?
    Rails.logger.info "NpsSurveyService:   nps_already_sent? = #{nps_already_sent_result}"
    
    mode_allows_result = mode_allows_sending?
    Rails.logger.info "NpsSurveyService:   mode_allows_sending? = #{mode_allows_result} (configured_mode = #{nps_config['mode']}, requested_mode = #{@mode})"
    
    cooldown_result = cooldown_respected?
    Rails.logger.info "NpsSurveyService:   cooldown_respected? = #{cooldown_result}"
    
    blocked_result = blocked_by_labels?
    Rails.logger.info "NpsSurveyService:   blocked_by_labels? = #{blocked_result}"
    
    optional_rules_result = optional_rules_met?
    Rails.logger.info "NpsSurveyService:   optional_rules_met? = #{optional_rules_result}"
    
    result = nps_enabled_result &&
             conversation_allows_result &&
             !nps_already_sent_result &&
             mode_allows_result &&
             cooldown_result &&
             !blocked_result &&
             optional_rules_result

    Rails.logger.info "NpsSurveyService: Final result for conversation #{conversation.id}: #{result}"

    result
  end

  def nps_enabled?
    # Reload inbox to ensure we have the latest data
    inbox.reload
    result = inbox.nps_survey_enabled?
    Rails.logger.info "NpsSurveyService: nps_enabled? = #{result} (inbox.nps_survey_enabled = #{inbox.nps_survey_enabled.inspect})"
    result
  end

  def conversation_allows_nps?
    conversation.resolved? && !conversation.tweet?
  end

  def nps_already_sent?
    # Only block if an NPS was sent in this conversation in the last 5 minutes (avoid duplicate on same resolution).
    # Re-sending in the same conversation is allowed after cooldown (see cooldown_respected?).
    # Verificar se já foi enviado um NPS recentemente (últimos 5 minutos)
    # Isso permite múltiplos envios quando a conversa é resolvida e reaberta várias vezes
    # mas evita envios duplicados na mesma resolução
    recent_time_threshold = 5.minutes.ago

    # Buscar o último NPS response enviado recentemente
    last_nps_response = conversation.nps_responses
      .where('created_at >= ?', recent_time_threshold)
      .where(status: :sent)
      .order(created_at: :desc)
      .first
    
    return false unless last_nps_response.present?

    # Verificar se existe uma mensagem NPS associada e se ela tem conteúdo
    message_id = last_nps_response.metadata&.dig('message_id')
    if message_id
      message = Message.find_by(id: message_id)
      if message.nil?
        Rails.logger.info "NpsSurveyService: nps_already_sent? = false (NPS response exists but message is missing. Response ID: #{last_nps_response.id}, Message ID: #{message_id})"
        return false
      end
      # Treat deleted messages as still sent (prevent duplicate NPS after deletion)
      if message.content_attributes&.dig('deleted')
        Rails.logger.info "NpsSurveyService: nps_already_sent? = true (NPS message was deleted but still counts as sent. Response ID: #{last_nps_response.id}, Message ID: #{message_id})"
        return true
      end
      Rails.logger.info "NpsSurveyService: nps_already_sent? = true (NPS response ID: #{last_nps_response.id}, status: #{last_nps_response.status}, message ID: #{message_id}, message content present: #{message.content.present?}, sent recently: #{last_nps_response.created_at >= recent_time_threshold})"
      return true
    end

    # Se não há message_id no metadata, verificar se existe alguma mensagem NPS válida criada recentemente
    nps_message = conversation.messages
      .where('created_at >= ?', recent_time_threshold)
      .where.not(content: [nil, ''])
      .where(
        "content_type = :input_nps OR (content_type = :text AND content_attributes ->> 'nps_survey' = 'true')",
        input_nps: Message.content_types[:input_nps],
        text: Message.content_types[:text]
      )
      .order(created_at: :desc)
      .first
    
    if nps_message.present?
      Rails.logger.info "NpsSurveyService: nps_already_sent? = true (NPS response exists and valid NPS message found recently. Response ID: #{last_nps_response.id}, Message ID: #{nps_message.id})"
      return true
    end

    # Se não há mensagem válida, considerar como não enviado
    Rails.logger.info "NpsSurveyService: nps_already_sent? = false (NPS response exists but no valid NPS message found recently. Response ID: #{last_nps_response.id})"
    false
  end

  def mode_allows_sending?
    configured_mode = nps_config['mode'] || 'auto'
    requested_mode = @mode || 'auto'

    case configured_mode
    when 'auto'
      requested_mode == 'auto'
    when 'manual'
      requested_mode == 'manual'
    when 'both'
      true
    else
      requested_mode == 'auto'
    end
  end

  # Cooldown: quando o contato já respondeu a uma pesquisa NPS recentemente, não envia outra.
  # Prioridade: cooldown_hours (horas) se configurado; senão cooldown_days (dias), para compatibilidade.
  # Usar horas permite que vários agentes conversem no mesmo dia sem disparar NPS em toda resolução.
  def cooldown_respected?
    cooldown_hours = nps_config['cooldown_hours']
    if cooldown_hours.present? && cooldown_hours.to_s != ''
      return true if cooldown_hours.to_i.zero?

      last_response = contact.nps_responses
                             .where(status: :responded)
                             .order(answered_at: :desc)
                             .first
      return true unless last_response&.answered_at

      hours_since_last = (Time.current - last_response.answered_at) / 1.hour
      result = hours_since_last >= cooldown_hours.to_i
      Rails.logger.info "NpsSurveyService: cooldown_respected? = #{result} (cooldown_hours: #{cooldown_hours}, contact_id: #{contact.id}, hours_since_last: #{hours_since_last})"
      return result
    end

    # Fallback: cooldown em dias (comportamento antigo)
    cooldown_days = nps_config['cooldown_days'] || 30
    return true if cooldown_days.to_i.zero?

    last_response = contact.nps_responses
                          .where(status: :responded)
                          .order(answered_at: :desc)
                          .first
    return true unless last_response&.answered_at

    days_since_last = (Time.current - last_response.answered_at) / 1.day
    result = days_since_last >= cooldown_days.to_i
    Rails.logger.info "NpsSurveyService: cooldown_respected? = #{result} (cooldown_days: #{cooldown_days}, contact_id: #{contact.id}, days_since_last: #{days_since_last})"
    result
  end

  def blocked_by_labels?
    return false unless blocklist_configured?

    labels_to_check = labels_to_check_for_blocklist
    blocklist_labels = nps_config['blocklist_labels'] || []

    return false if blocklist_labels.empty?

    blocklist_labels.any? { |label| labels_to_check.include?(label) }
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

  def optional_rules_met?
    return false unless min_messages_met?
    return false unless min_duration_met?
    return false unless required_tags_met?

    true
  end

  def min_messages_met?
    min_messages = nps_config['min_messages']
    return true if min_messages.blank? || min_messages.zero?

    conversation.messages.count >= min_messages
  end

  def min_duration_met?
    min_duration_minutes = nps_config['min_duration_minutes']
    return true if min_duration_minutes.blank? || min_duration_minutes.zero?

    return false unless conversation.created_at

    duration_minutes = (Time.current - conversation.created_at) / 60
    duration_minutes >= min_duration_minutes
  end

  def required_tags_met?
    required_tags = nps_config['required_tags'] || []
    return true if required_tags.empty?

    conversation_labels = conversation.label_list
    required_tags.all? { |tag| conversation_labels.include?(tag) }
  end

  def within_messaging_window?
    conversation.can_reply?
  end

  def create_nps_not_sent_activity_message
    content = I18n.t('conversations.activity.nps.not_sent_due_to_messaging_window', default: 'NPS survey could not be sent due to messaging window restrictions.')
    create_activity_message(content)
  end

  # When NPS is not sent due to cooldown, already_sent, or optional_rules, create an activity message with the reason.
  def create_nps_not_sent_activity_message_if_applicable
    reason = nps_block_reason_for_activity
    return if reason.blank?

    key = "conversations.activity.nps.not_sent_#{reason}"
    content = I18n.t(key, default: "NPS survey not sent: #{reason}")
    create_activity_message(content)
  end

  # Returns a symbol (:cooldown, :already_sent, :optional_rules) if the survey was blocked by a reason we want to show in the UI; nil otherwise.
  def nps_block_reason_for_activity
    return :already_sent if nps_already_sent?
    return :cooldown unless cooldown_respected?
    return :optional_rules unless optional_rules_met?

    nil
  end

  def create_activity_message(content)
    return if content.blank?

    activity_message_params = {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
    ::Conversations::ActivityMessageJob.perform_later(conversation, activity_message_params)
  end

  def nps_config
    # Use the reloaded inbox from perform method
    inbox.nps_config || {}
  end

  def handle_blocked_nps
    return if conversation.nps_response.present?

    blocking_label = find_blocking_label
    return unless blocking_label

    nps_response = NpsResponse.create!(
      account_id: conversation.account_id,
      conversation_id: conversation.id,
      contact_id: conversation.contact_id,
      inbox_id: conversation.inbox_id,
      assigned_agent_id: conversation.assignee_id,
      status: :dismissed,
      dismiss_reason: 'label_blocked',
      blocked_by_label: blocking_label,
      blocked_scope: nps_config['blocklist_scope'] || 'both'
    )

    # Create activity message
    create_blocked_activity_message(blocking_label)
  end

  def find_blocking_label
    labels_to_check = labels_to_check_for_blocklist
    blocklist_labels = nps_config['blocklist_labels'] || []
    
    blocklist_labels.find { |label| labels_to_check.include?(label) }
  end

  def create_blocked_activity_message(blocking_label)
    content = I18n.t('conversations.activity.nps.blocked',
                     label: blocking_label,
                     default: "NPS survey blocked by label: #{blocking_label}")
    create_activity_message(content)
  end
end
