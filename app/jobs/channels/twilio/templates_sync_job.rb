class Channels::Twilio::TemplatesSyncJob < ApplicationJob
  queue_as :low

  def perform(channel_id)
    return unless (twilio_channel = Channel::TwilioSms.find_by(id: channel_id))

    Twilio::TemplateSyncService.new(channel: twilio_channel).call
  end
end
