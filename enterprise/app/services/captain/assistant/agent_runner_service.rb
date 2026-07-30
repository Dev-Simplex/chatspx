require 'agents'
require 'agents/instrumentation'

class Captain::Assistant::AgentRunnerService
  include Integrations::LlmInstrumentationConstants
  include Captain::Assistant::RunnerCallbacksHelper
  include Captain::Assistant::TracePayloadHelper

  CONVERSATION_STATE_ATTRIBUTES = %i[
    id display_id inbox_id contact_id status priority
    label_list custom_attributes additional_attributes
  ].freeze

  CONTACT_STATE_ATTRIBUTES = %i[
    id name email phone_number identifier contact_type
    custom_attributes additional_attributes
  ].freeze

  CONTACT_INBOX_STATE_ATTRIBUTES = %i[id hmac_verified].freeze

  CAMPAIGN_STATE_ATTRIBUTES = %i[id title message campaign_type description].freeze
  def initialize(assistant:, conversation: nil, callbacks: {}, source: nil)
    @assistant = assistant
    @conversation = conversation
    @callbacks = callbacks
    @source = source
  end

  def generate_response(message_history: [])
    message_to_process, context = run_payload(message_history)
    result = runner.run(message_to_process, context: context, max_turns: 100)

    process_agent_result(result)
  rescue StandardError => e
    handle_run_error(e)
  end

  # Additive: roda o engine real e devolve o RunResult cru (output + messages + usage),
  # pra callers de eval/test-gate (Spx::AiConfig) inspecionarem tool_calls/handoffs por
  # mensagem. NAO altera #generate_response (caminho de producao). Mesma chamada do runner.
  def run_raw(message_history: [])
    message_to_process, context = run_payload(message_history)
    runner.run(message_to_process, context: context, max_turns: 100)
  end

  private

  def handle_run_error(e)
    # In rake/local runs, conversation may not be present, so account is optional here.
    ChatwootExceptionTracker.new(e, account: @conversation&.account).capture_exception
    Rails.logger.error "[Captain V2] AgentRunnerService error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    error_response(e.message)
  end

  def build_context(message_history)
    conversation_history = message_history.map do |msg|
      content = msg[:content]
      # Preserve multimodal arrays (with image_url entries) as-is for the runner to restore with attachments.
      # Only extract text from non-array formats (hashes from agent structured output, plain strings).
      content = extract_text_from_content(content) unless content.is_a?(Array)

      {
        role: msg[:role].to_sym,
        content: content,
        agent_name: msg[:agent_name]
      }
    end

    {
      session_id: "#{@assistant.account_id}_#{@conversation&.display_id}",
      conversation_history: conversation_history,
      state: build_state
    }
  end

  def extract_last_user_message(message_history)
    last_user_msg = message_history.reverse.find { |msg| msg[:role] == 'user' }
    return '' if last_user_msg.blank?

    content = last_user_msg[:content]
    return extract_text_from_content(content) unless content.is_a?(Array)

    text, attachments = Captain::OpenAiMessageBuilderService.extract_text_and_attachments(content)
    return text if attachments.blank?

    RubyLLM::Content.new(text, attachments)
  end

  def message_history_without_last_user_message(message_history)
    last_user_index = message_history.rindex { |msg| msg[:role] == 'user' }
    return message_history if last_user_index.nil?

    message_history.reject.with_index { |_msg, index| index == last_user_index }
  end

  def extract_text_from_content(content)
    # Handle structured output from agents
    return content[:response] || content['response'] || content.to_s if content.is_a?(Hash)

    return content unless content.is_a?(Array)

    text_parts = content.select { |part| part[:type] == 'text' }.pluck(:text)
    text_parts.join(' ')
  end

  def process_agent_result(result)
    Rails.logger.info "[Captain V2] Agent result: #{result.inspect}"
    output = result.output
    response = output.is_a?(Hash) ? output.with_indifferent_access : { 'response' => output.to_s, 'reasoning' => 'Processed by agent' }

    # Quando o ultimo turno e um handoff (ou o agente nao produz output final),
    # result.output volta vazio — mas o texto pro cliente ("vou te passar pra
    # Bruna...") ficou na ultima mensagem do assistente, antes da tool_call de
    # handoff. Sem este fallback, o ResponseBuilderJob trata como [IGNORAR] e a
    # fala de handoff nunca chega no WhatsApp.
    response['response'] = last_assistant_message_text(result) if response['response'].blank?
    # Anti-papagaio: o fallback acima pode pegar a ULTIMA fala do assistente vinda do
    # HISTORICO quando o turno atual nao produziu texto novo, re-emitindo identica.
    # So vale pra texto NOVO deste turno (ex: ponte de handoff); se bater com uma
    # mensagem de saida recente da conversa, descarta (vira [IGNORAR], sem replay).
    response['response'] = '' if response['response'].present? && fallback_replays_history?(response['response'])

    response['agent_name'] = result.context&.dig(:current_agent)
    response
  end

  # Recupera o texto da ultima mensagem do assistente do resultado do runner.
  # Cobre conteudo em texto puro e em JSON estruturado (response_schema).
  # True se o texto bate com uma das ultimas saidas da conversa (= replay do historico,
  # nao texto novo deste turno). A resposta nova deste turno ainda nao foi persistida,
  # entao nunca casa aqui — so casa quando o fallback pegou uma fala antiga.
  def fallback_replays_history?(text)
    return false if @conversation.blank?

    recent = @conversation.messages.where(message_type: :outgoing, private: false)
                          .order(created_at: :desc).limit(12).pluck(:content).compact
                          .map { |c| c.to_s.strip }
    return false if recent.empty?

    norm = text.to_s.strip
    return true if recent.include?(norm)

    # O humanizer quebra a resposta em bolhas, salvas como mensagens separadas — então o
    # texto INTEIRO do fallback nunca casa com uma bolha isolada. Quebra do mesmo jeito e
    # só marca replay se TODAS as bolhas já foram enviadas (texto NOVO deste turno passa).
    chunks = humanizer_chunks(text)
    chunks.present? && chunks.all? { |chunk| recent.include?(chunk) }
  end

  def humanizer_chunks(text)
    Captain::Behavior::HumanizerService.new(config: @assistant.behavior['humanizer'])
                                       .split(text).map { |c| c.to_s.strip }.reject(&:blank?)
  rescue StandardError
    []
  end

  def last_assistant_message_text(result)
    messages = result.try(:messages)
    return '' if messages.blank?

    last = messages.reverse.find do |msg|
      role = msg[:role] || msg['role']
      content = msg[:content] || msg['content']
      role.to_s == 'assistant' && content.present?
    end
    content = last && (last[:content] || last['content'])
    return '' if content.blank?

    unwrap_agent_output(content)
  end

  # Estrutura de saída serializada no formato cru do inspect, com hash-rocket.
  SERIALIZED_OUTPUT = /\A\{.*["']response["']\s*=>/m
  SERIALIZED_RESPONSE_FIELD = /["']response["']\s*=>\s*"((?:[^"\\]|\\.)*)"/m

  # O modelo às vezes serializa a PRÓPRIA estrutura de saída ({"response"=>"...",
  # "reasoning"=>"..."}) em vez de devolver só o texto. Em JSON válido o parse abaixo
  # resolve; em hash-rocket, não — e a estrutura inteira viraria a fala do agente.
  # Acontece sobretudo quando o turno termina em transferência: o response sai vazio,
  # cai neste fallback e o hash cru seguiria como mensagem pro cliente. Desembrulhado,
  # o turno de transferência devolve vazio, que é o certo — quem fala em seguida é a
  # agente que assumiu.
  def unwrap_agent_output(content)
    parsed = begin
      JSON.parse(content)
    rescue StandardError
      nil
    end
    return parsed['response'].to_s if parsed.is_a?(Hash) && parsed['response'].present?
    return content.to_s unless content.to_s.strip.match?(SERIALIZED_OUTPUT)

    content.to_s.match(SERIALIZED_RESPONSE_FIELD)&.captures&.first.to_s
  end

  def error_response(error_message)
    {
      'response' => 'conversation_handoff',
      'reasoning' => "Error occurred: #{error_message}"
    }
  end

  def build_state
    state = {
      account_id: @assistant.account_id,
      assistant_id: @assistant.id,
      assistant_config: @assistant.config
    }
    state[:source] = @source if @source.present?

    build_conversation_state(state) if @conversation
    state
  end

  def build_conversation_state(state)
    state[:conversation] = slice_attrs(@conversation, CONVERSATION_STATE_ATTRIBUTES)
    # O marcador de espera por humano NÃO entra no contexto do agente: a presença dele empurra
    # o LLM pro silêncio ([IGNORAR]) mesmo quando o cliente traz pergunta nova. Ele segue no
    # banco pros outros usos (guard do follow-up + filtro "Aguardando atendimento").
    state[:conversation][:custom_attributes] = (state[:conversation][:custom_attributes] || {}).except('aguardando_humano_desde')
    state[:channel_type] = @conversation.inbox&.channel_type
    state[:contact] = slice_attrs(@conversation.contact, CONTACT_STATE_ATTRIBUTES) if @conversation.contact
    state[:campaign] = slice_attrs(@conversation.campaign, CAMPAIGN_STATE_ATTRIBUTES) if @conversation.campaign
    state[:contact_inbox] = slice_attrs(@conversation.contact_inbox, CONTACT_INBOX_STATE_ATTRIBUTES) if @conversation.contact_inbox
  end

  def slice_attrs(record, keys)
    record.attributes.symbolize_keys.slice(*keys)
  end

  def build_and_wire_agents
    assistant_agent = @assistant.agent
    scenario_agents = @assistant.scenarios.enabled.map(&:agent)

    assistant_agent.register_handoffs(*scenario_agents) if scenario_agents.any?
    scenario_agents.each { |scenario_agent| scenario_agent.register_handoffs(assistant_agent) }

    [assistant_agent] + scenario_agents
  end

  def install_instrumentation(runner)
    return unless ChatwootApp.otel_enabled?

    Agents::Instrumentation.install(
      runner,
      tracer: OpentelemetryConfig.tracer,
      trace_name: 'llm.captain_v2',
      span_attributes: {
        ATTR_LANGFUSE_TAGS => ['captain_v2'].to_json
      },
      attribute_provider: ->(context_wrapper) { dynamic_trace_attributes(context_wrapper) }
    )
    register_trace_input_callback(runner)
  end

  def dynamic_trace_attributes(context_wrapper)
    state = context_wrapper&.context&.dig(:state) || {}
    conversation = state[:conversation] || {}
    trace_input = context_wrapper&.context&.dig(:captain_v2_trace_input)

    {
      ATTR_LANGFUSE_USER_ID => state[:account_id],
      format(ATTR_LANGFUSE_METADATA, 'assistant_id') => state[:assistant_id],
      format(ATTR_LANGFUSE_METADATA, 'conversation_id') => conversation[:id],
      format(ATTR_LANGFUSE_METADATA, 'conversation_display_id') => conversation[:display_id],
      format(ATTR_LANGFUSE_METADATA, 'channel_type') => state[:channel_type],
      format(ATTR_LANGFUSE_METADATA, 'source') => state[:source],
      ATTR_LANGFUSE_TRACE_INPUT => trace_input,
      ATTR_LANGFUSE_OBSERVATION_INPUT => trace_input
    }.compact.transform_values(&:to_s)
  end

  def add_usage_metadata_callback(runner)
    return runner unless ChatwootApp.otel_enabled?

    handoff_tool_name = Captain::Tools::HandoffTool.new(@assistant).name

    runner.on_tool_complete do |tool_name, _tool_result, context_wrapper|
      track_handoff_usage(tool_name, handoff_tool_name, context_wrapper)
    end

    runner.on_run_complete do |_agent_name, _result, context_wrapper|
      write_credits_used_metadata(context_wrapper)
    end
    runner
  end

  def track_handoff_usage(tool_name, handoff_tool_name, context_wrapper)
    return unless context_wrapper&.context
    return unless tool_name.to_s == handoff_tool_name

    context_wrapper.context[:captain_v2_handoff_tool_called] = true
  end

  def write_credits_used_metadata(context_wrapper)
    root_span = context_wrapper&.context&.dig(:__otel_tracing, :root_span)
    return unless root_span

    credit_used = !context_wrapper.context[:captain_v2_handoff_tool_called]
    root_span.set_attribute(format(ATTR_LANGFUSE_METADATA, 'credit_used'), credit_used.to_s)
  end

  def runner
    @runner ||= begin
      configured_runner = Agents::Runner.with_agents(*build_and_wire_agents)
      configured_runner = add_usage_metadata_callback(configured_runner)
      configured_runner = add_callbacks_to_runner(configured_runner) if @callbacks.any?
      install_instrumentation(configured_runner)
      configured_runner
    end
  end

  def run_payload(message_history)
    message_to_process = extract_last_user_message(message_history)
    context = build_context(message_history_without_last_user_message(message_history))
    enrich_context_with_trace_payload!(context, message_history, message_to_process)
    [message_to_process, context]
  end
end
