# Endpoint SSE do copiloto (contrato C1).
#
#   POST /api/v1/accounts/:account_id/captain/copilot_threads/:copilot_thread_id/stream
#
# Por que `ActionController::Live` e nao ActionCable/Sidekiq+Redis:
# a ordem dos tokens e o unico requisito inegociavel de um chat (chunk fora de
# ordem = palavra embaralhada na frente do agente), e SSE numa unica conexao HTTP
# da ordem de graca. O custo e conhecido e esta documentado no relato: cada
# conexao segura UMA thread do Puma ate o fim da geracao — por isso existe teto
# de duracao (Copilot::StreamingChatService::MAX_DURATION_SECONDS), heartbeat que
# detecta cliente morto e lock por thread.
#
# `ActionController::Live` vale para TODAS as actions do controller (cada request
# roda numa thread propria), por isso este controller tem uma action so.
class Api::V1::Accounts::Captain::CopilotStreamsController < Api::V1::Accounts::BaseController
  include ActionController::Live
  include Captain::ApiKeyValidation

  LOCK_KEY_FORMAT = 'COPILOT_STREAM_LOCK::%<thread_id>d'.freeze
  LOCK_TTL_SECONDS = Copilot::StreamingChatService::MAX_DURATION_SECONDS + 30

  before_action :ensure_captain_api_key!, only: :create
  before_action :set_copilot_thread
  before_action :ensure_generation_possible, only: :create
  before_action :ensure_response_quota, only: :create
  before_action :ensure_thread_not_busy, only: :create

  def create
    setup_sse_headers
    cancellation.clear!
    @sse = Copilot::SseStream.new(response.stream)
    Copilot::ThreadStreamService.new(
      copilot_thread: @copilot_thread,
      user: Current.user,
      sse: @sse,
      input: {
        message: permitted_params[:message],
        conversation_id: permitted_params[:conversation_id],
        regenerate: regenerating?
      }
    ).call
  ensure
    @sse&.close
    cancellation.clear!
    release_lock
  end

  # Botao "parar" do agente. Fechar a conexao tambem cancela, mas a deteccao
  # depende do buffer do socket encher (medido: ate ~4s ainda gerando contra a
  # OpenAI real). Este caminho e deterministico: a proxima checagem da geracao,
  # no maximo 200ms depois, aborta a chamada ao provedor.
  def destroy
    cancellation.request!
    head :no_content
  end

  private

  def cancellation
    @cancellation ||= Copilot::StreamCancellation.new(params[:copilot_thread_id].to_i)
  end

  def setup_sse_headers
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache, no-store'
    # Desliga o buffer do nginx nesta resposta, independente da config do server.
    response.headers['X-Accel-Buffering'] = 'no'
    # Presenca de Last-Modified impede o Rack::ETag de bufferizar o corpo inteiro
    # para calcular o digest — o que anularia o streaming.
    response.headers['Last-Modified'] = Time.zone.now.httpdate
  end

  def set_copilot_thread
    @copilot_thread = Current.account.copilot_threads.find_by!(
      id: params[:copilot_thread_id],
      user: Current.user
    )
  end

  # Ou o agente mandou uma pergunta nova, ou existe uma pergunta pendente para
  # (re)gerar. Sem isso o endpoint viraria uma forma cara de nao fazer nada.
  def ensure_generation_possible
    return if permitted_params[:message].present?
    return if regenerating? && last_message&.message_type == 'assistant'
    return if last_message&.message_type == 'user'

    render_stream_error('nothing_to_generate', 'No pending agent question in this thread.', :unprocessable_entity)
  end

  def ensure_response_quota
    return if Current.account.usage_limits[:captain][:responses][:current_available].positive?

    render_stream_error(
      'quota_exceeded',
      'The Captain response quota for this account is exhausted.',
      :too_many_requests
    )
  end

  # Duas perguntas seguidas na MESMA thread nao podem gerar em paralelo: o
  # historico e compartilhado e as duas respostas sairiam intercaladas. A segunda
  # e recusada com 409 antes de abrir o stream — cabe ao front esperar ou parar a
  # primeira. O TTL do lock cobre o teto de duracao da geracao, entao um processo
  # que morrer no meio nao deixa a thread travada.
  def ensure_thread_not_busy
    return if lock_manager.lock(lock_key, LOCK_TTL_SECONDS)

    # Retry-After ajuda o caso mais comum de 409: o cliente caiu e reconectou
    # antes de o servidor perceber a desconexao (leva ~1s) e soltar o lock.
    response.headers['Retry-After'] = '2'
    render_stream_error('busy', 'This copilot thread is already generating an answer.', :conflict)
  end

  def release_lock
    lock_manager.unlock(lock_key)
  end

  def lock_manager
    @lock_manager ||= Redis::LockManager.new
  end

  def lock_key
    format(LOCK_KEY_FORMAT, thread_id: params[:copilot_thread_id].to_i)
  end

  def last_message
    @last_message ||= @copilot_thread.copilot_messages.order(created_at: :desc, id: :desc).first
  end

  def regenerating?
    ActiveModel::Type::Boolean.new.cast(permitted_params[:regenerate]).present?
  end

  # Erros de pre-condicao saem como HTTP + JSON (o stream nem chega a abrir).
  # Falha DEPOIS da geracao comecar sai como evento SSE `error`. Os dois usam o
  # mesmo vocabulario de `code`.
  def render_stream_error(code, message, status)
    render json: { code: code, message: message }, status: status
  end

  def permitted_params
    params.permit(:message, :conversation_id, :regenerate)
  end
end
