class Captain::Copilot::ChatService < Llm::BaseAiService
  include Captain::ChatHelper

  attr_reader :assistant, :account, :user, :copilot_thread, :previous_history, :messages

  def initialize(assistant, config)
    super(account: assistant.account)

    @assistant = assistant
    @account = assistant.account
    @user = nil
    @copilot_thread = nil
    @previous_history = []
    @conversation = @account.conversations.find_by(display_id: config[:conversation_id])
    @conversation_id = @conversation&.display_id

    setup_user(config)
    setup_message_history(config)
    @tools = build_tools
    @messages = build_messages(config)
  end

  def generate_response(input)
    @messages << { role: 'user', content: input } if input.present?
    response = request_chat_completion

    Rails.logger.debug { "#{self.class.name} Assistant: #{@assistant.id}, Received response #{response}" }
    Rails.logger.info(
      "#{self.class.name} Assistant: #{@assistant.id}, Incrementing response usage for account #{@account.id}"
    )
    @account.increment_response_usage

    response
  end

  private

  def setup_user(config)
    @user = @account.users.find_by(id: config[:user_id]) if config[:user_id].present?
  end

  def build_messages(config)
    messages= [system_message]
    messages << account_id_context
    messages += @previous_history if @previous_history.present?
    messages += current_viewing_history(config[:conversation_id]) if config[:conversation_id].present?
    messages
  end

  def setup_message_history(config)
    Rails.logger.info(
      "#{self.class.name} Assistant: #{@assistant.id}, Previous History: #{config[:previous_history]&.length || 0}, Language: #{config[:language]}"
    )

    @copilot_thread = @account.copilot_threads.find_by(id: config[:copilot_thread_id]) if config[:copilot_thread_id].present?
    @previous_history = if @copilot_thread.present?
                          @copilot_thread.previous_history
                        else
                          config[:previous_history].presence || []
                        end
  end

  TOOL_CLASSES = [
    Captain::Tools::SearchDocumentationService,
    Captain::Tools::Copilot::GetConversationService,
    Captain::Tools::Copilot::SearchConversationsService,
    Captain::Tools::Copilot::GetContactService,
    Captain::Tools::Copilot::GetArticleService,
    Captain::Tools::Copilot::SearchArticlesService,
    Captain::Tools::Copilot::SearchContactsService,
    Captain::Tools::Copilot::SearchLinearIssuesService,
    Captain::Tools::Copilot::GetAccountStatsService,
    Captain::Tools::Copilot::GetAgentWorkloadService,
    Captain::Tools::Copilot::GetTeamInfoService,
    Captain::Tools::Copilot::AssignConversationService,
    Captain::Tools::Copilot::AddLabelService,
    Captain::Tools::Copilot::ChangeStatusService,
    Captain::Tools::Copilot::ChangePriorityService,
    Captain::Tools::Copilot::GetCsatDataService,
    Captain::Tools::Copilot::SearchMessagesService,
    Captain::Tools::Copilot::GetInboxInfoService,
    Captain::Tools::Copilot::GetConversationFullService,
    Captain::Tools::Copilot::SendMessageService,
    Captain::Tools::Copilot::SendTemplateService,
    Captain::Tools::Copilot::UpdateContactService,
    Captain::Tools::Copilot::SetCustomAttributesService,
    Captain::Tools::Copilot::RemoveLabelService,
    Captain::Tools::Copilot::SnoozeConversationService,
    Captain::Tools::Copilot::TransferToInboxService,
    Captain::Tools::Copilot::GetContactConversationsService,
    Captain::Tools::Copilot::AddNoteToContactService,
    Captain::Tools::Copilot::ResolveConversationService,
    Captain::Tools::Copilot::GetLabelsService,
    Captain::Tools::Copilot::GetAgentsService,
    Captain::Tools::Copilot::GetConversationAnalysisService
  ].freeze

  def build_tools
    native = TOOL_CLASSES.map { |klass| klass.new(@assistant, user: @user) }.select(&:active?)
    # Custom Tools do account (ex: Vista da Tozi) também ficam disponíveis pro Copilot.
    # HttpTool herda de Agents::Tool (RubyLLM-compatível), então pluga direto via with_tool.
    custom = @account.captain_custom_tools.enabled.filter_map do |custom_tool|
      custom_tool.tool(@assistant)
    rescue StandardError => e
      Rails.logger.warn("[Copilot] skip custom tool #{custom_tool.slug}: #{e.message}")
      nil
    end
    native + custom
  end

  def system_message
    {
      role: 'system',
      content: Captain::Llm::SystemPromptsService.copilot_response_generator(
        @assistant.config['product_name'],
        tools_summary,
        @assistant.config
      )
    }
  end

  def tools_summary
    @tools.map { |tool| "- #{tool.class.name}: #{tool.class.description}" }.join("\n")
  end

  def account_id_context
    {
      role: 'system',
      content: "The current account id is #{@account.id}. The account is using #{@account.locale_english_name} as the language."
    }
  end

  def current_viewing_history(conversation_id)
    conversation = @account.conversations.find_by(display_id: conversation_id)
    return [] unless conversation

    Rails.logger.info("#{self.class.name} Assistant: #{@assistant.id}, Setting viewing history for conversation_id=#{conversation_id}")
    contact_id = conversation.contact_id
    [{
      role: 'system',
      content: <<~HISTORY.strip
        You are currently viewing the conversation with the following details:
        Conversation ID: #{conversation_id}
        Contact ID: #{contact_id}
      HISTORY
    }]
  end

  def persist_message(message, message_type = 'assistant')
    return if @copilot_thread.blank?

    @copilot_thread.copilot_messages.create!(
      message: message,
      message_type: message_type
    )
  end

  def feature_name
    'copilot'
  end
end
