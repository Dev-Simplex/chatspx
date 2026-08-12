# Resolves integration credentials/config for a Captain tool's account.
#
# Single source of truth for Vista (real-estate CRM), Google, the office location
# and the public site domain. Every helper reads in the SAME priority order:
#
#   1. AccountIntegration.settings_for(account, provider)  -> new per-account model
#   2. account.custom_attributes                           -> legacy per-account
#   3. ENV / hardcoded constant                            -> global fallback (Tozi legacy)
#
# Mixed into BasePublicTool, so every public tool inherits the helpers. Relies on
# the including instance exposing @assistant (set in BasePublicTool#initialize).
#
# NOTE: this file lives under .../tools/concerns/ but defines the constant WITHOUT
# a ::Concerns:: segment. config/application.rb collapses this directory in Zeitwerk
# (same convention Rails applies to app/**/concerns).
# rubocop:disable Style/ClassAndModuleChildren -- nested obrigatório: o Zeitwerk
# resolve este arquivo via collapse de .../tools/concerns/ no config/application.rb.
module Captain
  module Tools
    module IntegrationCredentials
      # Vista (real-estate CRM) -------------------------------------------------
      DEFAULT_VISTA_BASE_URL = 'https://toz19328-rest.vistahost.com.br'.freeze

      # Office location (escritório) — legacy Tozi constants as last resort -----
      DEFAULT_OFFICE_LAT  = -11.8519937
      DEFAULT_OFFICE_LNG  = -55.5093314
      DEFAULT_OFFICE_NAME = 'Tozi Imóveis - Av. das Figueiras, 1646, Sala 01, Centro, Sinop/MT'.freeze

      # Public site domain (link builder) --------------------------------------
      DEFAULT_SITE_DOMAIN = 'toziimoveis.com.br'.freeze

      # Cidade de atendimento (viés das buscas no Google) — legacy Tozi ---------
      DEFAULT_GEO_CITY = 'Sinop MT'.freeze

      def vista_api_key
        integration_setting('vista', 'vista_api_key') ||
          custom_attribute('vista_api_key') ||
          ENV['TOZI_VISTA_API_KEY'].to_s
      end

      def vista_base_url
        integration_setting('vista', 'vista_base_url') ||
          custom_attribute('vista_base_url') ||
          ENV.fetch('TOZI_VISTA_BASE_URL', DEFAULT_VISTA_BASE_URL)
      end

      # Returns a present key or nil (callers may layer their own last-resort fallback).
      def google_maps_key
        integration_setting('google', 'google_maps_key') ||
          custom_attribute('google_maps_key') ||
          ENV['GOOGLE_MAPS_API_KEY'].presence
      end

      # { lat: Float, lng: Float, name: String } — office pin coordinates.
      def office_coords
        vista = account_integration_settings('vista')
        {
          lat: (vista['office_lat'].presence || DEFAULT_OFFICE_LAT).to_f,
          lng: (vista['office_lng'].presence || DEFAULT_OFFICE_LNG).to_f,
          name: vista['office_name'].presence || DEFAULT_OFFICE_NAME
        }
      end

      def site_domain
        integration_setting('vista', 'site_domain') ||
          custom_attribute('site_domain') ||
          DEFAULT_SITE_DOMAIN
      end

      # API do site do cliente que resolve código do imóvel -> URL da página.
      # Por padrão mora no próprio domínio público, então configurar `site_domain`
      # já basta; `site_api_url` existe pra apontar pra outro host quando preciso.
      def site_api_url
        integration_setting('vista', 'site_api_url') ||
          custom_attribute('site_api_url') ||
          ENV['SITE_API_URL'].presence ||
          "https://www.#{site_domain}/functions/v1/api"
      end

      # Cidade que enviesa a busca de lugares e o geocoding ("<termo> <cidade>"). Sem
      # config na conta cai no DEFAULT_GEO_CITY, que é exatamente o texto que estava
      # fixo no código — nenhuma conta muda de comportamento sem ser configurada.
      # Mesma ordem de prioridade dos demais (integração -> custom_attributes ->
      # constante); sem camada de ENV de propósito: uma variável global mudaria a
      # cidade de TODAS as contas do box de uma vez.
      def geo_city
        integration_setting('google', 'geo_city') ||
          custom_attribute('geo_city') ||
          DEFAULT_GEO_CITY
      end

      # Sem chave, o link cai no formato montado localmente (ver VistaImovelUrl).
      def site_api_key
        integration_setting('vista', 'site_api_key') ||
          custom_attribute('site_api_key') ||
          ENV['SITE_API_KEY'].presence
      end

      private

      # The account that owns the running tool (assistant's account).
      def tool_account
        @assistant&.account
      end

      def account_integration_settings(provider)
        acc = tool_account
        return {} unless acc

        AccountIntegration.settings_for(acc, provider) || {}
      end

      def integration_setting(provider, key)
        account_integration_settings(provider)[key].presence
      end

      def custom_attribute(key)
        (tool_account&.custom_attributes || {})[key].presence
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
