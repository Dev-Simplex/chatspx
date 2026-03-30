class Channels::Whatsapp::TemplatesSyncJob < ApplicationJob
  queue_as :low

  def perform(channel_id)
    return unless (whatsapp_channel = Channel::Whatsapp.find_by(id: channel_id))

    whatsapp_channel.sync_templates
  end
end
