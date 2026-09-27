# Assina como o Captador (Spx::Captador::BaseController): "sha256=" + HMAC-SHA256, em hex, de
# "<ts>.<MÉTODO>.<path?query>.<corpo bruto>" com o segredo do hook. Incluir no spec que usa.
module CaptadorSigningHelpers
  def captador_hook_for(account, **settings)
    account.update!(captador_integration: true)
    create(:integrations_hook, account: account, app_id: 'captador', settings: {
      'captador_url' => 'https://captador.test', 'instance_key' => 'inst-1', 'shared_secret' => 's' * 40
    }.merge(settings.stringify_keys))
  end

  def captador_post(path, body, hook:, headers: {}, timestamp: Time.now.to_i, secret: hook.settings['shared_secret'])
    raw = body.to_json
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.POST.#{path}.#{raw}")
    post path, params: raw, headers: {
      'CONTENT_TYPE' => 'application/json',
      'X-Captador-Account' => hook.account_id.to_s,
      'X-Captador-Timestamp' => timestamp.to_s,
      'X-Captador-Signature' => "sha256=#{signature}"
    }.merge(headers)
  end
end
