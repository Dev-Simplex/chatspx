class Captain::Conversation::ResponseBuilderJob < ApplicationJob
  MAX_MESSAGE_LENGTH = 10_000
  retry_on ActiveStorage::FileNotFoundError, attempts: 3, wait: 2.seconds
  retry_on Faraday::BadRequestError, attempts: 3, wait: 2.seconds

  def perform(conversation, assistant, directive: nil)
    @conversation = conversation
    @inbox = conversation.inbox
    @assistant = assistant
    @directive = directive

    return unless captain_can_respond?

    reset_followup_state if @directive.nil?

    Current.executed_by = @assistant

    if captain_v2_enabled?
      generate_response_with_v2
    else
      generate_and_process_response
    end
  rescue ActiveStorage::FileNotFoundError, Faraday::BadRequestError => e
    handle_error(e)
    raise e
  rescue StandardError => e
    handle_error(e)
  ensure
    Current.executed_by = nil
  end

  private

  delegate :account, :inbox, to: :@conversation

  def generate_and_process_response
    @response = Captain::Llm::AssistantChatService.new(assistant: @assistant, conversation: @conversation).generate_response(
      message_history: collect_previous_messages
    )
    process_response
  end

  def generate_response_with_v2
    @response = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, conversation: @conversation).generate_response(
      message_history: collect_previous_messages
    )
    process_response
  end

  def process_response
    return unless captain_can_respond?

    if handoff_requested?
      process_action('handoff')
    else
      ActiveRecord::Base.transaction do
        create_messages
        Rails.logger.info("[CAPTAIN][ResponseBuilderJob] Incrementing response usage for #{account.id}")
        account.increment_response_usage
      end
    end
  end

  def collect_previous_messages
    @conversation
      .messages
      .where(message_type: [:incoming, :outgoing])
      .where(private: false)
      .map do |message|
      message_hash = {
        content: with_reply_context(message, prepare_multimodal_message_content(message)),
        role: determine_role(message)
      }

      # Include agent_name if present in additional_attributes
      message_hash[:agent_name] = message.additional_attributes['agent_name'] if message.additional_attributes&.dig('agent_name').present?

      message_hash
    end.tap do |history|
      # Diretiva interna de follow-up (cutucada): entra como último turno pro agente decidir.
      history << { content: @directive, role: 'user' } if @directive.present?
    end
  end

  # Quando o cliente volta a responder (resposta normal, sem diretiva), a cadência
  # de cutucada zera: lead reengajado começa do zero.
  def reset_followup_state
    attrs = @conversation.custom_attributes || {}
    return if attrs['followup_token'].blank? && attrs['followup_count'].to_i.zero?

    @conversation.update!(custom_attributes: attrs.merge('followup_token' => nil, 'followup_count' => 0, 'followup_status' => nil))
  rescue StandardError => e
    Rails.logger.warn("[ResponseBuilderJob] reset_followup: #{e.message}")
  end

  def determine_role(message)
    message.message_type == 'incoming' ? 'user' : 'assistant'
  end

  # Quando o cliente responde (reply) a uma mensagem específica do WhatsApp,
  # injeta o texto citado no contexto pra o agente saber a qual imóvel/mensagem
  # ele se refere. Sem isso, "é essa" / "quero essa" ficavam sem referência.
  def with_reply_context(message, content)
    attrs = message.content_attributes || {}
    reply_id = attrs['in_reply_to']
    reply_ext = attrs['in_reply_to_external_id']
    quoted = nil
    quoted = @conversation.messages.find_by(id: reply_id) if reply_id.present?
    quoted ||= @conversation.messages.find_by(source_id: reply_ext) if reply_ext.present?
    return content if quoted&.content.blank?

    prefix = "[Respondendo a esta mensagem anterior: \"#{quoted.content.to_s.gsub(/\s+/, ' ').strip[0, 180]}\"] "
    case content
    when String then prefix + content
    when Array then [{ type: 'text', text: prefix }] + content
    else content
    end
  end

  def prepare_multimodal_message_content(message)
    Captain::OpenAiMessageBuilderService.new(message: message).generate_content
  end

  def handoff_requested?
    @response['response'] == 'conversation_handoff'
  end

  def process_action(action)
    case action
    when 'handoff'
      I18n.with_locale(@assistant.account.locale) do
        create_handoff_message
        @conversation.bot_handoff!
        send_out_of_office_message_if_applicable
      end
    end
  end

  def send_out_of_office_message_if_applicable
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if @conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(@conversation)
  end

  def create_handoff_message
    create_outgoing_message(
      @assistant.config['handoff_message'].presence || I18n.t('conversations.captain.handoff')
    )
  end

  def create_messages
    content = @response['response']
    return if no_reply?(content)
    return if skip_duplicate?(content)

    send_response(content)
  end

  # O agente decide quando NÃO responder (ex: cliente só mandou "ok"/"blz" e não há
  # nada pendente). Sinaliza com [IGNORAR] ou resposta vazia -> não envia nada.
  def no_reply?(content)
    return true if content.blank?

    content.to_s.strip.match?(/\A\[?\s*(ignorar|sem[\s_-]?resposta|no[\s_-]?reply)\s*\]?\z/i)
  end

  def skip_duplicate?(content)
    return false unless dedup_enabled?

    dedup = Captain::Behavior::DedupService.new(assistant: @assistant, conversation: @conversation)
    return false unless dedup.duplicate?(content)

    log_behavior_event('dedup_skip', { content_hash: Digest::MD5.hexdigest(content) })
    true
  end

  def send_response(content)
    content = sanitize_for_whatsapp(content)
    if humanizer_enabled?
      send_humanized_response(content)
    else
      create_outgoing_message(content, agent_name: @response['agent_name'])
    end
  end

  # WhatsApp não renderiza markdown; alguns LLMs (ex: gpt-5-mini) insistem em
  # **negrito** mesmo instruídos a não usar. Remove a formatação markdown comum
  # antes de enviar, pra não aparecer literal pro cliente.
  def sanitize_for_whatsapp(content)
    return content if content.blank?

    content.gsub(/\*\*(.*?)\*\*/m, '\1')   # **negrito** -> negrito
           .gsub(/__(.*?)__/m, '\1')        # __negrito__ -> negrito
           .gsub(/^\s{0,3}#+\s+/, '')        # ## títulos -> texto
           .gsub(/^\s{0,3}[-*]\s+/, '')      # - bullets -> texto
  end

  def send_humanized_response(content)
    chunks = Captain::Behavior::HumanizerService.new(config: @assistant.behavior['humanizer']).split(content)
    delay_seconds = @assistant.behavior.dig('humanizer', 'delay_ms').to_f / 1000

    chunks.each_with_index do |chunk, i|
      create_outgoing_message(chunk, agent_name: @response['agent_name'])
      sleep(delay_seconds) if i < chunks.size - 1
    end
    log_behavior_event('humanizer_split', { chunks: chunks.size }) if chunks.size > 1
  end

  def validate_message_content!(content)
    raise ArgumentError, 'Message content cannot be blank' if content.blank?
  end

  def create_outgoing_message(message_content, agent_name: nil)
    additional_attrs = {}
    additional_attrs[:agent_name] = agent_name if agent_name.present?

    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      sender: @assistant,
      content: message_content,
      additional_attributes: additional_attrs
    )
  end

  def handle_error(error)
    log_error(error)
    process_action('handoff') if conversation_pending?
    true
  end

  def log_error(error)
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  def captain_v2_enabled?
    account.feature_enabled?('captain_integration_v2')
  end

  def dedup_enabled?
    @assistant.behavior.dig('dedup', 'enabled') == true
  end

  def humanizer_enabled?
    @assistant.behavior.dig('humanizer', 'enabled') == true
  end

  def log_behavior_event(event_type, payload = {})
    Captain::AssistantLog.create!(
      captain_assistant: @assistant,
      conversation: @conversation,
      event_type: event_type,
      payload: payload
    )
  end

  def conversation_pending?
    status = Conversation.uncached { Conversation.where(id: @conversation.id).pick(:status) }
    status == 'pending' || status == Conversation.statuses[:pending]
  end

  # Captain responde em pending E em open (continua atendendo após handoff/atribuição
  # até um humano responder; skip_after_human_response corta quando o atendente fala).
  def captain_can_respond?
    status = Conversation.uncached { Conversation.where(id: @conversation.id).pick(:status) }
    [Conversation.statuses[:pending], Conversation.statuses[:open], 'pending', 'open'].include?(status)
  end
end
