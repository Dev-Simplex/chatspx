# Valida verify_token do challenge (GET /webhooks/meta_lead_ads).
# Token bate se qualquer hook ativo tiver settings['verify_token'] igual.
module Meta
  module LeadAds
    class TokenVerifier
      def self.valid?(token)
        return false if token.blank?

        Integrations::Hook.where(app_id: 'meta_lead_ads', status: 'enabled').find_each do |hook|
          expected = hook.settings['verify_token'].to_s
          next if expected.blank?

          return true if ActiveSupport::SecurityUtils.secure_compare(expected, token.to_s)
        end

        false
      end
    end
  end
end
