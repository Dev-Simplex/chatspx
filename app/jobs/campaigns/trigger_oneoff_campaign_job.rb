class Campaigns::TriggerOneoffCampaignJob < ApplicationJob
  queue_as :low

  def perform(campaign_id)
    return unless (campaign = Campaign.find_by(id: campaign_id))

    campaign.trigger!
  end
end
