class Api::V1::Accounts::IntegrationsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(AccountIntegration) }
  before_action :set_integration, only: [:show, :test_connection]

  def index
    @integrations = account_integrations.order(:provider)
  end

  def show; end

  def update
    @integration = account_integrations.find_or_initialize_by(provider: integration_params[:provider].to_s)
    @integration.enabled = ActiveModel::Type::Boolean.new.cast(integration_params[:enabled]) unless integration_params[:enabled].nil?
    @integration.settings = merged_settings(@integration, integration_params[:settings])
    @integration.save!
    render :show
  end

  # Smoke-test the stored credentials for a provider (save settings first, then test).
  # vista: hits the listar endpoint with a minimal search. google: checks key presence.
  def test_connection
    settings = @integration.settings || {}
    result = case @integration.provider
             when 'vista' then test_vista_connection(settings)
             when 'google' then test_google_connection(settings)
             else { ok: false, error: 'unsupported_provider' }
             end
    render json: result
  end

  private

  def account_integrations
    Current.account.account_integrations
  end

  def set_integration
    @integration = account_integrations.find_or_initialize_by(provider: params[:id].to_s)
  end

  def integration_params
    params.require(:integration).permit(
      :provider,
      :enabled,
      settings: [:vista_api_key, :vista_base_url, :google_maps_key,
                 :office_lat, :office_lng, :office_name, :site_domain,
                 :site_api_url, :site_api_key]
    )
  end

  # Merge submitted settings over the stored ones so partial updates don't wipe
  # other keys. Secret fields submitted blank or still masked ('*') are skipped so
  # the UI re-posting masked values never clobbers a real stored secret.
  def merged_settings(integration, submitted)
    current = (integration.settings || {}).dup
    return current if submitted.blank?

    submitted.to_h.each do |key, value|
      next if AccountIntegration::SECRET_KEYS.include?(key.to_s) && masked_or_blank?(value)

      current[key.to_s] = value
    end
    current
  end

  def masked_or_blank?(value)
    value.blank? || value.to_s.include?('*')
  end

  def test_vista_connection(settings)
    api_key = settings['vista_api_key']
    base_url = settings['vista_base_url']
    return { ok: false, error: 'missing_credentials' } if api_key.blank? || base_url.blank?

    pesquisa = { fields: ['Codigo'], paginacao: { pagina: 1, quantidade: 1 } }.to_json
    url = "#{base_url.to_s.chomp('/')}/imoveis/listar"
    # Vista exige Accept: application/json (sem isso responde 406), igual ao buscar_imovel_tool.
    response = connection_tester_http.get(url, { key: api_key, pesquisa: pesquisa, showtotal: 1 },
                                          { 'Accept' => 'application/json' })
    { ok: response.success?, status: response.status }
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def test_google_connection(settings)
    return { ok: true } if settings['google_maps_key'].present?

    { ok: false, error: 'missing_google_maps_key' }
  end

  def connection_tester_http
    Faraday.new do |faraday|
      faraday.options.open_timeout = 5
      faraday.options.timeout = 10
      faraday.adapter Faraday.default_adapter
    end
  end
end
