class AgentNotifications::ConversationNotificationsMailer < ApplicationMailer
  def conversation_creation(conversation, agent, _user)
    return noop_mail_if_disabled if ENV['DISABLE_AGENT_EMAIL_NOTIFICATIONS'] == 'true'
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    inbox_name = @conversation.inbox&.sanitized_name
    subject = "#{@agent.available_name}, A new conversation [ID - #{@conversation.display_id}] has been created in #{inbox_name}."
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  def conversation_assignment(conversation, agent, _user)
    return noop_mail_if_disabled if ENV['DISABLE_AGENT_EMAIL_NOTIFICATIONS'] == 'true'
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    subject = "#{@agent.available_name}, A new conversation [ID - #{@conversation.display_id}] has been assigned to you."
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  def conversation_unassignment(conversation, agent, user)
    return noop_mail_if_disabled if ENV['DISABLE_AGENT_EMAIL_NOTIFICATIONS'] == 'true'
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    @taker = @conversation.assignee || user
    subject = I18n.t('notifications.notification_title.conversation_unassignment',
                     display_id: @conversation.display_id, taker: @taker&.available_name)
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  def conversation_mention(conversation, agent, message)
    return noop_mail_if_disabled if ENV['DISABLE_AGENT_EMAIL_NOTIFICATIONS'] == 'true'
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    @message = message
    subject = "#{@agent.available_name}, You have been mentioned in conversation [ID - #{@conversation.display_id}]"
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  def assigned_conversation_new_message(conversation, agent, message)
    return noop_mail_if_disabled if ENV['DISABLE_AGENT_EMAIL_NOTIFICATIONS'] == 'true'
    return unless smtp_config_set_or_development?
    # Don't spam with email notifications if agent is online
    return if ::OnlineStatusTracker.get_presence(message.account_id, 'User', agent.id)

    @agent = agent
    @conversation = conversation
    subject = "#{@agent.available_name}, New message in your assigned conversation [ID - #{@conversation.display_id}]."
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  def participating_conversation_new_message(conversation, agent, message)
    return noop_mail_if_disabled if ENV['DISABLE_AGENT_EMAIL_NOTIFICATIONS'] == 'true'
    return unless smtp_config_set_or_development?
    # Don't spam with email notifications if agent is online
    return if ::OnlineStatusTracker.get_presence(message.account_id, 'User', agent.id)

    @agent = agent
    @conversation = conversation
    subject = "#{@agent.available_name}, New message in a conversation you are participating in [ID - #{@conversation.display_id}]."
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  private

  def noop_mail_if_disabled
    mail(to: 'noreply@localhost', subject: '') do |format| # rubocop:disable Rails/I18nLocaleTexts
      format.text { render plain: '' }
    end.tap { |m| m.perform_deliveries = false } # rubocop:disable Style/MultilineBlockChain
  end

  def liquid_droppables
    super.merge({
                  user: @agent,
                  conversation: @conversation,
                  inbox: @conversation.inbox,
                  message: @message,
                  taker: @taker
                })
  end
end

AgentNotifications::ConversationNotificationsMailer.prepend_mod_with('AgentNotifications::ConversationNotificationsMailer')
