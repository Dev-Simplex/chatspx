# Base dos endpoints que o Captador chama (docs/contratos/captador.md). Máquina a máquina, sem
# sessão: cada pedido vem assinado com o segredo do hook "captador" da conta, e a assinatura cobre
# método e path além do corpo, senão uma assinatura capturada valeria para outra rota por 5 min.
#
# Qualquer falha de autenticação responde 401 sem corpo, para não ensinar quem está tentando.
class Spx::Captador::BaseController < ActionController::API
  APP_ID = 'captador'.freeze
  MAX_CLOCK_SKEW = 5.minutes.to_i
  REPLAY_TTL = 10.minutes.to_i

  # Current é thread-local e o Puma reusa threads: quem popula limpa (RequestExceptionHandler).
  around_action :reset_current
  before_action :authenticate_captador!

  private

  def reset_current
    yield
  ensure
    Current.reset
  end

  def authenticate_captador!
    @account = Account.find_by(id: request.headers['X-Captador-Account'])
    @hook = @account.hooks.find_by(app_id: APP_ID, status: 'enabled') if @account&.captador_integration_enabled?
    return head :unauthorized unless @hook && fresh_timestamp? && valid_signature? && unused_signature?

    Current.account = @account
  end

  def fresh_timestamp?
    timestamp = request.headers['X-Captador-Timestamp'].to_s
    timestamp.match?(/\A\d+\z/) && (Time.now.to_i - timestamp.to_i).abs <= MAX_CLOCK_SKEW
  end

  # v1: "<ts>.<MÉTODO>.<path?query>.<corpo bruto>". v2 inclui conta, Idempotency-Key e hash do corpo.
  def valid_signature?
    secret = @hook.captador_shared_secret.to_s
    return false if secret.blank?

    provided = request.headers['X-Captador-Signature'].to_s
    expected = provided.start_with?('v2=') ? v2_signature(secret) : v1_signature(secret)
    ActiveSupport::SecurityUtils.secure_compare(expected, provided)
  end

  def v1_signature(secret)
    signed = [request.headers['X-Captador-Timestamp'], request.method, request.fullpath, request.raw_post].join('.')
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, signed)}"
  end

  def v2_signature(secret)
    Spx::Captador::Signature.v2(
      secret: secret,
      timestamp: request.headers['X-Captador-Timestamp'],
      method: request.method,
      path: request.fullpath,
      identifier: request.headers['X-Captador-Account'],
      header_name: 'idempotency-key',
      header_value: request.headers['Idempotency-Key'],
      body: request.raw_post
    )
  end

  # GETs podem ser repetidos; mutações usam a assinatura uma vez só dentro da janela aceita.
  def unused_signature?
    return true if request.get? || request.head?

    signature = request.headers['X-Captador-Signature'].to_s
    key = "captador:signature:#{@account.id}:#{Digest::SHA256.hexdigest(signature)}"
    Redis::Alfred.set(key, 1, nx: true, ex: REPLAY_TTL).present?
  end

  def render_error(status, error_code, meta = nil)
    render json: { error_code: error_code, meta: meta }.compact, status: status
  end
end
