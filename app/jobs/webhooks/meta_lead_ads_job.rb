# Processa payload de webhook Meta Lead Ads em background.
# Payload exemplo:
#   { "object": "page",
#     "entry": [
#       { "id": "<page_id>",
#         "time": 1764000000,
#         "changes": [
#           { "field": "leadgen",
#             "value": { "leadgen_id": "...", "page_id": "...", "form_id": "...", ... } } ] } ] }
class Webhooks::MetaLeadAdsJob < ApplicationJob
  queue_as :default

  def perform(payload)
    Array(payload['entry']).each do |entry|
      page_id = entry['id']
      hook = Meta::LeadAds::HookFinder.for_page_id(page_id)
      unless hook
        Rails.logger.warn("Meta Lead Ads webhook: no hook found for page_id=#{page_id}")
        next
      end

      Array(entry['changes']).each do |change|
        next unless change['field'] == 'leadgen'

        process_leadgen(change['value'], hook)
      end
    end
  end

  private

  def process_leadgen(value, hook)
    leadgen_id = value['leadgen_id']
    if leadgen_id.blank?
      Rails.logger.warn("Meta Lead Ads webhook: missing leadgen_id in change value")
      return
    end

    lead = Meta::LeadAds::FetchLeadService.new(
      leadgen_id: leadgen_id,
      access_token: hook.settings['page_access_token']
    ).perform

    Meta::LeadAds::CreateConversationService.new(hook: hook, lead: lead).perform
  rescue StandardError => e
    Rails.logger.error("Meta Lead Ads webhook: error processing leadgen=#{leadgen_id} hook=#{hook&.id} - #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))
    raise
  end
end
