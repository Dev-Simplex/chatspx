# Motor de geracao em streaming do copiloto.
#
# Diferente do caminho antigo (`Captain::Copilot::ChatService`), aqui nao existe
# resposta em JSON nem loop de tools: o objetivo e texto em markdown chegando
# token a token para o agente ler enquanto e escrito.
#
# O vinculo com o agente de IA (`Captain::Assistant`) e SO LEITURA — usamos
# persona e idioma; nada e gravado no assistente.
class Copilot::StreamingChatService < Llm::BaseAiService
  # Interrompido de proposito (cliente desconectou ou pediu para parar).
  # Nao e falha: nao vira evento `error`.
  class Cancelled < StandardError; end

  # Teto de duracao de UMA geracao. Uma conexao SSE segura uma thread do Puma,
  # entao gerar sem teto e o mesmo que vazar thread.
  MAX_DURATION_SECONDS = ENV.fetch('COPILOT_STREAM_TIMEOUT_SECONDS', 120).to_i
  # Timeout de rede por requisicao ao provedor (cobre o TTFT).
  REQUEST_TIMEOUT_SECONDS = ENV.fetch('COPILOT_STREAM_REQUEST_TIMEOUT_SECONDS', 60).to_i
  # Retry automatico do RubyLLM: 1 e o teto aqui. Cada retry segura a thread do
  # Puma mais um round-trip inteiro, e 401 (o caso mais provavel hoje) nao
  # melhora com repeticao.
  MAX_RETRIES = 1

  MAX_HISTORY_MESSAGES = 20
  MAX_CONVERSATION_MESSAGES = 20
  MAX_MESSAGE_LENGTH = 400

  attr_reader :copilot_thread, :assistant, :conversation

  def initialize(copilot_thread:, conversation_id: nil)
    @copilot_thread = copilot_thread
    @assistant = copilot_thread.assistant
    super(account: copilot_thread.account)

    @conversation = find_conversation(conversation_id)
  end

  # Executa a geracao. Cada pedaco de texto chega pelo bloco.
  #
  # `cancelled` e consultado a cada chunk: retornando true, levantamos Cancelled
  # de dentro do callback do provedor, o que aborta a conexao HTTP com a OpenAI —
  # ou seja, paramos de pagar tokens que ninguem vai ler.
  #
  # Erros do provedor sobem como Copilot::StreamingError (codigo estavel).
  def call(cancelled: nil, &block)
    deadline = monotonic_time + MAX_DURATION_SECONDS
    history = build_history
    return '' if history.blank?

    chat = build_chat(history)
    response = chat.ask(history.last[:content]) do |chunk|
      guard!(cancelled, deadline)
      delta = chunk.content.to_s
      # `present?` é `blank?` invertido, e em Ruby QUALQUER string só de espaço em
      # branco é blank — inclusive `"\n"` e `"\n\n"`. Filtrar por `present?` aqui
      # engolia todo token de quebra de linha do modelo, e a resposta chegava na
      # tela como um paredão colado ("...atenção.2. Use linguagem..."), destruindo
      # parágrafos, listas e tabelas. O único delta que não vale enviar é o vazio.
      block&.call(delta) unless delta.empty?
    end
    response.content.to_s
  rescue Cancelled, Copilot::StreamingError
    raise
  rescue StandardError => e
    raise Copilot::StreamingError.from(e)
  end

  private

  def guard!(cancelled, deadline)
    raise Cancelled if cancelled.respond_to?(:call) && cancelled.call
    raise Copilot::StreamingError, Copilot::StreamingError::TIMEOUT if monotonic_time > deadline
  end

  # Timeout e retry sao aplicados no contexto do RubyLLM: `context_for_account`
  # devolve um contexto novo a cada chamada (config duplicada), entao mexer aqui
  # nao contamina a config global nem os agentes de IA.
  def context_for_account
    context = super
    context.config.request_timeout = REQUEST_TIMEOUT_SECONDS
    context.config.max_retries = MAX_RETRIES
    context
  end

  def build_chat(history)
    llm_chat = chat(model: @model, temperature: temperature).with_instructions(system_prompt)
    history[0...-1].each { |message| llm_chat.add_message(role: message[:role].to_sym, content: message[:content]) }
    llm_chat
  end

  # Historico da thread, ja em ordem estavel, cortado nas ultimas mensagens.
  # A ultima tem de ser do agente — e a pergunta que vamos responder.
  def build_history
    history = copilot_thread.previous_history
                            .map { |entry| { role: entry[:role].to_s, content: entry[:content].to_s } }
                            .reject { |entry| entry[:content].blank? }
                            .last(MAX_HISTORY_MESSAGES)
    return [] if history.blank? || history.last[:role] != 'user'

    history
  end

  def temperature
    assistant&.config&.[]('temperature').presence&.to_f || 0.4
  end

  def find_conversation(conversation_id)
    return if conversation_id.blank?

    account.conversations.find_by(display_id: conversation_id)
  end

  def system_prompt
    [identity_prompt, conversation_prompt].compact_blank.join("\n\n")
  end

  def identity_prompt
    <<~PROMPT.strip
      [Identity]
      You are the copilot of a human support agent working on #{product_name}.
      You talk to the AGENT, never to the customer. The agent reads your answer and decides what to do with it.

      [Response Guidelines]
      - Answer in #{account.locale_english_name}, the language used by this account, unless the agent writes in another language.
      - Be brief and useful: one or two short paragraphs, unless the agent asks for detail.
      - Write in Markdown, without headings.
      - Never invent data. If the answer is not in the context you were given, say so plainly.
      - Do not tell the agent to contact support: the agent IS the support.
      - Do not end with pleasantries ("let me know if you need anything else").
    PROMPT
  end

  def conversation_prompt
    return if conversation.blank?

    <<~PROMPT.strip
      [Conversation the agent is looking at]
      Conversation ID: #{conversation.display_id}
      Contact: #{conversation.contact&.name}
      Status: #{conversation.status} · Priority: #{conversation.priority || 'none'}

      Transcript (most recent messages):
      #{transcript}
    PROMPT
  end

  def transcript
    conversation.messages
                .where(message_type: [:incoming, :outgoing])
                .order(created_at: :desc, id: :desc)
                .limit(MAX_CONVERSATION_MESSAGES)
                .reverse
                .filter_map { |message| transcript_line(message) }
                .join("\n")
  end

  def transcript_line(message)
    content = message.content.to_s.strip
    return if content.blank?

    "#{transcript_author(message)}: #{content[0, MAX_MESSAGE_LENGTH]}"
  end

  def transcript_author(message)
    return 'Customer' if message.incoming?
    return 'Private note' if message.private?

    'Agent'
  end

  def product_name
    assistant&.config&.[]('product_name').presence || account.name
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def feature_name
    'copilot'
  end
end
