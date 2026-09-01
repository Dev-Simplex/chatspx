# Orquestra uma geracao do copiloto sobre uma thread persistida.
#
# Ordem que importa (contrato C1): a mensagem final e gravada em
# `copilot_messages` ANTES do evento `done`. Se o agente recarregar a pagina no
# instante seguinte, a resposta ja esta no historico.
#
# Saidas possiveis (`finish_reason`):
#   stop      — o provedor terminou;
#   cancelled — o agente fechou a conexao/parou; o parcial e preservado;
#   error     — falha do provedor, traduzida em codigo estavel.
class Copilot::ThreadStreamService
  FINISH_STOP = 'stop'.freeze
  FINISH_CANCELLED = 'cancelled'.freeze
  FINISH_ERROR = 'error'.freeze

  # `input` carrega o que veio do agente: :message (pergunta nova),
  # :conversation_id (a conversa que ele esta olhando) e :regenerate.
  def initialize(copilot_thread:, user:, sse:, input: {})
    @copilot_thread = copilot_thread
    @user = user
    @sse = sse
    @cancellation = Copilot::StreamCancellation.new(copilot_thread.id)
    @message = input[:message].to_s.strip.presence
    @conversation_id = input[:conversation_id]
    @regenerate = input[:regenerate].present?
    @buffer = +''
  end

  def call
    @started_at = monotonic_time
    discard_last_answer if @regenerate
    persist_user_message
    sse.emit('start', thread_id: copilot_thread.id, user_message_id: @user_message&.id)
    sse.start_heartbeat!

    finish_with_success(generate)
  rescue Copilot::StreamingChatService::Cancelled, Copilot::SseStream::Disconnected
    finish_with_cancellation
  rescue Copilot::StreamingError => e
    finish_with_error(e)
  rescue StandardError => e
    finish_with_error(Copilot::StreamingError.from(e))
  ensure
    sse.stop_heartbeat!
  end

  private

  attr_reader :copilot_thread, :user, :sse, :buffer

  # Duas formas de parar: o agente sumiu (conexao morta) ou o agente pediu
  # explicitamente (botao "parar" -> DELETE .../stream). A segunda e a rapida.
  def generate
    Copilot::StreamingChatService
      .new(copilot_thread: copilot_thread, conversation_id: @conversation_id)
      .call(cancelled: -> { !sse.connected? || @cancellation.requested? }) { |delta| handle_delta(delta) }
  end

  # O buffer e alimentado ANTES de tentar escrever: se o cliente sumiu neste
  # exato chunk, o texto ja gerado ainda entra no parcial persistido.
  def handle_delta(delta)
    buffer << delta
    sse.emit('token', delta: delta)
  rescue Copilot::SseStream::Disconnected
    raise Copilot::StreamingChatService::Cancelled
  end

  def finish_with_success(text)
    content = text.presence || buffer.presence
    persisted = persist_assistant_message(content, FINISH_STOP)
    log_outcome(FINISH_STOP)
    emit_done(persisted, FINISH_STOP)
  end

  # Cancelado: nao ha para quem emitir (a conexao caiu), mas o parcial e do
  # agente — fica gravado com o motivo, para o front oferecer continuar/refazer.
  def finish_with_cancellation
    persisted = persist_assistant_message(buffer.presence, FINISH_CANCELLED)
    log_outcome(FINISH_CANCELLED)
    # No "parar" explicito o agente continua na escuta: ele recebe o `done` com
    # o id do parcial, e pode continuar/refazer a partir dali. Quando a conexao
    # morreu, nao ha para quem emitir.
    emit_done(persisted, FINISH_CANCELLED) if sse.connected?
  end

  def finish_with_error(error)
    persisted = persist_assistant_message(buffer.presence, FINISH_ERROR)
    log_outcome(FINISH_ERROR, error)
    return unless sse.connected?

    safe_emit { sse.emit('error', error.to_event) }
    emit_done(persisted, FINISH_ERROR)
  end

  def emit_done(persisted_message, finish_reason)
    safe_emit { sse.emit('done', message_id: persisted_message&.id, finish_reason: finish_reason) }
  end

  def safe_emit
    yield
  rescue Copilot::SseStream::Disconnected
    nil
  end

  # "Refazer" do ChatGPT: a resposta anterior sai do historico antes de gerar de
  # novo. Sem isso o modelo veria a propria resposta e tenderia a repeti-la.
  def discard_last_answer
    last = copilot_thread.copilot_messages.order(created_at: :desc, id: :desc).first
    last.destroy! if last&.assistant?
  end

  def persist_user_message
    return if @message.blank?

    @user_message = copilot_thread.copilot_messages.create!(
      message_type: :user,
      message: { content: @message }
    )
  end

  def persist_assistant_message(content, finish_reason)
    return if content.blank?

    account.increment_response_usage
    copilot_thread.copilot_messages.create!(
      message_type: :assistant,
      message: { content: content, finish_reason: finish_reason }
    )
  end

  def log_outcome(outcome, error = nil)
    duration_ms = ((monotonic_time - @started_at) * 1000).round
    log = "[Copilot::Stream] outcome=#{outcome} account_id=#{account.id} " \
          "copilot_thread_id=#{copilot_thread.id} user_id=#{user&.id} " \
          "chars=#{buffer.length} events=#{sse.sequence} duration_ms=#{duration_ms}"
    log += " #{error.log_context}" if error

    error ? Rails.logger.error(log) : Rails.logger.info(log)
  end

  def account
    copilot_thread.account
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
