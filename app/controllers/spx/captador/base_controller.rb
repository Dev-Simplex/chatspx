# Base dos endpoints que o Captador chama (docs/contratos/captador.md). Máquina a máquina, sem
# sessão: cada pedido vem assinado com o segredo do hook "captador" da conta, e a assinatura cobre
# método e path além do corpo, senão uma assinatura capturada valeria para outra rota por 5 min.
#
# Qualquer falha de autenticação responde 401 sem corpo, para não ensinar quem está tentando.
class Spx::Captador::BaseController < ActionController::API
  APP_ID = 'captador'.freeze
  MAX_CLOCK_SKEW = 5.minutes.to_i

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
    return head :unauthorized unless @hook && fresh_timestamp? && valid_signature?

    Current.account = @account
  end

  def fresh_timestamp?
    timestamp = request.headers['X-Captador-Timestamp'].to_s
    timestamp.match?(/\A\d+\z/) && (Time.now.to_i - timestamp.to_i).abs <= MAX_CLOCK_SKEW
  end

  # "<ts>.<MÉTODO>.<path?query>.<corpo bruto>", HMAC-SHA256 em hex, prefixo "sha256=".
  def valid_signature?
    secret = @hook.settings['shared_secret'].to_s
    return false if secret.blank?

    signed = [request.headers['X-Captador-Timestamp'], request.method, request.fullpath, request.raw_post].join('.')
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, signed)}"
    ActiveSupport::SecurityUtils.secure_compare(expected, request.headers['X-Captador-Signature'].to_s)
  end

  def render_error(status, error_code, meta = nil)
    render json: { error_code: error_code, meta: meta }.compact, status: status
  end
end
