class NpsSurveyService # rubocop:disable Metrics/ClassLength
  def initialize(conversation:, mode: nil)
    @conversation = conversation
    @mode = mode || 'auto'
  end

  def perform # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    Rails.logger.debug { "NpsSurveyService: Starting for conversation #{conversation.id}, mode: #{mode}" }

    # Reload inbox association to ensure we have the latest NPS configuration
    conversation.association(:inbox).reload if conversation.association(:inbox).loaded?
    conversation.association(:contact).reload if conversation.association(:contact).loaded?

    Rails.logger.debug { "NpsSurveyService: Inbox #{inbox.id}, nps_survey_enabled: #{inbox.nps_survey_enabled}" }

    if blocked_by_labels?
      handle_blocked_nps
      return
    end

    unless should_send_nps_survey?
      create_nps_not_sent_activity_message_if_applicable
      return
    end

    if within_messaging_window?
      ::MessageTemplates::Template::NpsSurvey.new(conversation: conversation).perform
      Rails.logger.info "NpsSurveyService: NPS survey sent for conversation #{conversation.id}"
    else
      create_nps_not_sent_activity_message
    end
  rescue StandardError => e
    Rails.logger.error "NpsSurveyService failed for conversation #{conversation.id}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  private

  attr_reader :conversation, :mode

  delegate :inbox, :contact, to: :conversation

  def should_send_nps_survey?
    nps_enabled? &&
      conversation_allows_nps? &&
      !nps_already_sent? &&
      mode_allows_sending? &&
      cooldown_respected? &&
      !blocked_by_labels? &&
      optional_rules_met?
  end

  def nps_enabled?
    inbox.nps_survey_enabled?
  end

  def conversation_allows_nps?
    conversation.resolved? && !conversation.tweet?
  end

  def nps_already_sent?
    return @nps_already_sent if defined?(@nps_already_sent)

    @nps_already_sent = compute_nps_already_sent?
  end

  def compute_nps_already_sent?
    # Only block if an NPS was sent in this conversation in the last 5 minutes (avoid duplicate on same resolution).
    recent_time_threshold = 5.minutes.ago

    last_nps_response = conversation.nps_responses
                                    .where('created_at >= ?', recent_time_threshold)
                                    .where(status: :sent)
                                    .order(created_at: :desc)
                                    .first
    return false if last_nps_response.blank?

    return nps_message_exists?(last_nps_response) if last_nps_response.metadata&.dig('message_id')

    recent_nps_message_exists?(recent_time_threshold)
  end

  def nps_message_exists?(nps_response)
    message = Message.find_by(id: nps_response.metadata['message_id'])
    return false if message.nil?

    true
  end

  # content_attributes e JSON serializado como STRING: ver Message::CONTENT_ATTRIBUTES_JSON.
  # Com o `->` direto, a pesquisa enviada como TEXTO (WhatsApp) nunca era encontrada e so
  # o content_type input_nps (widget) contava.
  def recent_nps_message_exists?(since)
    conversation.messages
                .where('created_at >= ?', since)
                .where.not(content: [nil, ''])
                .exists?(
                  ["content_type = :input_nps OR (content_type = :text AND " \
                   "#{Message::CONTENT_ATTRIBUTES_JSON} ->> 'nps_survey' = 'true')",
                   { input_nps: Message.content_types[:input_nps], text: Message.content_types[:text] }]
                )
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
    else # rubocop:disable Lint/DuplicateBranch
      requested_mode == 'auto'
    end
  end

  # Cooldown: when the contact has already responded to an NPS survey recently, do not send another.
  # Priority: cooldown_hours if configured; otherwise cooldown_days, for backwards compatibility.
  # Using hours allows multiple agents to chat on the same day without triggering NPS on every resolution.
  def cooldown_respected?
    return @cooldown_respected if defined?(@cooldown_respected)

    @cooldown_respected = compute_cooldown_respected?
  end

  def compute_cooldown_respected?
    cooldown_hours = nps_config['cooldown_hours']
    if cooldown_hours.present? && cooldown_hours.to_s != ''
      return true if cooldown_hours.to_i.zero?

      return elapsed_since_last_response >= cooldown_hours.to_i.hours
    end

    cooldown_days = (nps_config['cooldown_days'] || 30).to_i
    return true if cooldown_days.zero?

    elapsed_since_last_response >= cooldown_days.days
  end

  def elapsed_since_last_response
    last_response = contact.nps_responses
                           .where(status: :responded)
                           .order(answered_at: :desc)
                           .first
    return Float::INFINITY unless last_response&.answered_at

    Time.current - last_response.answered_at
  end

  def blocked_by_labels?
    return @blocked_by_labels if defined?(@blocked_by_labels)

    @blocked_by_labels = compute_blocked_by_labels?
  end

  def compute_blocked_by_labels?
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
    return @optional_rules_met if defined?(@optional_rules_met)

    @optional_rules_met = min_messages_met? && min_duration_met? && required_tags_met?
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
    content = I18n.t('conversations.activity.nps.not_sent_due_to_messaging_window',
                     default: 'NPS survey could not be sent due to messaging window restrictions.')
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
    ::Conversations::ActivityMessageJob.perform_later(conversation.id, activity_message_params)
  end

  def nps_config
    # Use the reloaded inbox from perform method
    inbox.nps_config || {}
  end

  def handle_blocked_nps
    return if conversation.nps_response.present?

    blocking_label = find_blocking_label
    return unless blocking_label

    NpsResponse.create!(
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
