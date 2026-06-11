# Valida assinatura HMAC-SHA256 dos webhooks Meta (header X-Hub-Signature-256).
# Itera hooks ativos do app_id 'meta_lead_ads' e tenta com cada app_secret
# até encontrar match (suporta multiplos apps Meta no mesmo SPX).
module Meta
  module LeadAds
    class SignatureVerifier
      PREFIX = 'sha256='.freeze

      def self.valid?(raw_payload:, signature_header:)
        return false if signature_header.blank? || raw_payload.blank?
        return false unless signature_header.start_with?(PREFIX)

        Integrations::Hook.where(app_id: 'meta_lead_ads', status: 'enabled').find_each do |hook|
          secret = hook.settings['app_secret'].to_s
          next if secret.blank?

          expected = PREFIX + OpenSSL::HMAC.hexdigest('SHA256', secret, raw_payload)
          return true if ActiveSupport::SecurityUtils.secure_compare(signature_header, expected)
        end

        false
      end
    end
  end
end
