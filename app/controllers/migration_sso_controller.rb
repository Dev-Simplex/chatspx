require 'jwt'

# SSO custom de migração Tozi (Account 6) prod on-premise → AWS dedicada.
# Mesmo arquivo deploya nos 2 servers; .env diferencia comportamento.
# Pos-migracao: REMOVER este controller, view, routes e .env vars.
class MigrationSsoController < ActionController::Base
  layout false
  protect_from_forgery with: :null_session

  ELIGIBLE_ACCOUNT_ID = 6

  # Senhas conhecidas dos users Tozi — NUNCA viajam no JWT.
  # Ficam apenas no consume controller (servidor destino).
  TRY_PASSWORDS = ['Master@123*', 'Master@123', 'Master@1239*'].freeze

  JTI_TTL_SECONDS = 300 # 5min — mesmo que exp do JWT.

  # POST /migration_sso/issue (PROD)
  def issue
    return render_json_error('sso_not_configured', :service_unavailable) if missing_env?
    return render_json_error('forbidden_origin', :forbidden) unless valid_origin?

    user = current_user_from_cookie
    return render_json_error('not_authenticated', :unauthorized) unless user

    eligible = user.account_users.where(account_id: ELIGIBLE_ACCOUNT_ID).exists?
    return render_json_error('not_eligible', :forbidden) unless eligible

    payload = {
      sub: user.email,
      acc: ELIGIBLE_ACCOUNT_ID,
      exp: JTI_TTL_SECONDS.seconds.from_now.to_i,
      iat: Time.now.to_i,
      jti: SecureRandom.uuid
    }

    token = JWT.encode(payload, ENV['MIGRATION_SHARED_SECRET'], 'HS256')
    redirect_url = "#{ENV['MIGRATION_DESTINATION_URL'].chomp('/')}/migration_sso/consume?token=#{CGI.escape(token)}"

    Rails.logger.info("[MigrationSSO] issue email=#{user.email} jti=#{payload[:jti]}")
    render json: { redirect_url: redirect_url }
  end

  # GET /migration_sso/consume (DESTINO)
  def consume
    return render plain: 'SSO not configured', status: :service_unavailable if ENV['MIGRATION_SHARED_SECRET'].blank?

    raw_token = params[:token].to_s
    return render plain: 'Token missing', status: :bad_request if raw_token.blank?

    begin
      payload = JWT.decode(raw_token, ENV['MIGRATION_SHARED_SECRET'], true, algorithm: 'HS256').first
    rescue JWT::DecodeError => e
      Rails.logger.warn("[MigrationSSO] invalid token: #{e.message}")
      return redirect_to '/app/login?sso_error=invalid_or_expired'
    end

    jti = payload['jti'].to_s
    if jti.blank? || !consume_jti(jti)
      Rails.logger.warn("[MigrationSSO] jti reused or empty: #{jti}")
      return redirect_to '/app/login?sso_error=replay'
    end

    email = payload['sub'].to_s
    user = User.find_by(email: email)
    unless user
      return redirect_to "/app/login?email=#{CGI.escape(email)}&sso_error=user_not_found"
    end

    matched = TRY_PASSWORDS.find { |p| user.valid_password?(p) }
    unless matched
      Rails.logger.warn("[MigrationSSO] no password match for #{email}")
      return redirect_to "/app/login?email=#{CGI.escape(email)}&sso_error=needs_login"
    end

    auth_data = create_auth_token(user)
    if auth_data.nil?
      Rails.logger.error("[MigrationSSO] token factory failed for #{email}")
      return redirect_to "/app/login?email=#{CGI.escape(email)}&sso_error=internal"
    end

    @headers = auth_data
    @redirect_path = "/app/accounts/#{ELIGIBLE_ACCOUNT_ID}/dashboard"

    Rails.logger.info("[MigrationSSO] consume OK email=#{email} jti=#{jti}")
    render 'consume_success', layout: false
  end

  private

  def missing_env?
    ENV['MIGRATION_SHARED_SECRET'].blank? || ENV['MIGRATION_DESTINATION_URL'].blank?
  end

  def render_json_error(code, status)
    render json: { error: code }, status: status
  end

  def valid_origin?
    source_url = ENV['MIGRATION_SOURCE_URL'].presence || request.base_url
    expected_host = URI.parse(source_url).host
    # Aceita same-origin (sem Origin/Referer) e cross-origin com Origin/Referer batendo
    origin = request.headers['Origin'] || request.headers['Referer']
    return true if origin.blank? # same-origin XHR às vezes vem sem header

    URI.parse(origin).host == expected_host
  rescue URI::InvalidURIError
    false
  end

  def current_user_from_cookie
    # cookies[] no Rails lê signed/encrypted. Cookies raw setados pelo JS via js-cookie
    # ficam em request.cookies. Tentar ambos.
    raw = request.cookies['cw_d_session_info'] || cookies['cw_d_session_info']
    if raw.blank?
      Rails.logger.warn("[MigrationSSO] no cw_d_session_info cookie present (request.cookies keys: #{request.cookies.keys.inspect})")
      return nil
    end

    # js-cookie url-encoda valor; Rails NÃO decoda cookies "normais" (não signed/encrypted).
    # Tentar parse direto, fallback CGI.unescape se houver `%`.
    candidates = [raw]
    candidates << CGI.unescape(raw) if raw.include?('%')

    parsed = nil
    candidates.each do |candidate|
      parsed = JSON.parse(candidate) rescue nil
      break if parsed.is_a?(Hash)
    end

    unless parsed.is_a?(Hash)
      Rails.logger.warn("[MigrationSSO] cookie present but unparseable. First 100 chars: #{raw[0, 100].inspect}")
      return nil
    end

    uid = parsed['uid'] || parsed[:uid]
    user = User.find_by(email: uid) if uid.present?
    Rails.logger.info("[MigrationSSO] cookie parsed OK, uid=#{uid.inspect}, found_user=#{user&.id}")
    user
  rescue StandardError => e
    Rails.logger.warn("[MigrationSSO] cookie parse exception: #{e.class}: #{e.message}")
    nil
  end

  # Redis SETNX para impedir replay de JWT dentro da janela de exp.
  def consume_jti(jti)
    # API: Redis::Alfred.set(key, value, nx: true, ex: ttl). Retorna true se SETNX criou
    # (jti inédito) ou false/nil se já existia (replay).
    Redis::Alfred.set("migration_sso:jti:#{jti}", 1, nx: true, ex: JTI_TTL_SECONDS)
  rescue StandardError => e
    Rails.logger.error("[MigrationSSO] redis SETNX failed: #{e.message}")
    # Fail-open só se Redis indisponivel (operacional > seguranca aqui)
    true
  end

  # Gera devise-token-auth credentials direto via TokenFactory.
  # Substitui o HTTP-loop pra 127.0.0.1:3000 (que era frágil c/ socket/port mudando).
  def create_auth_token(user)
    factory = DeviseTokenAuth::TokenFactory.create
    user.tokens[factory.client] = {
      token: factory.token_hash,
      expiry: factory.expiry
    }
    user.save(validate: false)

    {
      'access-token' => factory.token,
      'client' => factory.client,
      'expiry' => factory.expiry.to_s,
      'token-type' => 'Bearer',
      'uid' => user.email
    }
  rescue StandardError => e
    Rails.logger.error("[MigrationSSO] create_auth_token error: #{e.class}: #{e.message}")
    nil
  end
end
