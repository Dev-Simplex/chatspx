# Acha o Integrations::Hook correspondente ao page_id do payload Meta.
module Meta
  module LeadAds
    class HookFinder
      def self.for_page_id(page_id)
        return if page_id.blank?

        Integrations::Hook.where(app_id: 'meta_lead_ads', status: 'enabled').find do |hook|
          hook.settings['page_id'].to_s == page_id.to_s
        end
      end
    end
  end
end
