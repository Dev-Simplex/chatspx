class SendReplyJob < ApplicationJob
  queue_as :high

  CHANNEL_SERVICES = {
    'Channel::TwitterProfile' => ::Twitter::SendOnTwitterService,
    'Channel::TwilioSms' => ::Twilio::SendOnTwilioService,
    'Channel::Line' => ::Line::SendOnLineService,
    'Channel::Telegram' => ::Telegram::SendOnTelegramService,
    'Channel::Whatsapp' => ::Whatsapp::SendOnWhatsappService,
    'Channel::Sms' => ::Sms::SendOnSmsService,
    'Channel::Instagram' => ::Instagram::SendOnInstagramService,
    'Channel::Tiktok' => ::Tiktok::SendOnTiktokService,
    'Channel::Email' => ::Email::SendOnEmailService,
    'Channel::WebWidget' => ::Messages::SendEmailNotificationService,
    'Channel::Api' => ::Messages::SendEmailNotificationService
  }.freeze

  def perform(message_id)
    message = Message.find(message_id)
    channel_name = message.conversation.inbox.channel.class.to_s

    return send_on_facebook_page(message) if channel_name == 'Channel::FacebookPage'

    service_class = CHANNEL_SERVICES[channel_name]
    return unless service_class

    service_class.new(message: message).perform
  def perform(message_id)
    message = Message.find(message_id)
    conversation = message.conversation
    channel_name = conversation.inbox.channel.class.to_s
    
    Rails.logger.info "SendReplyJob: Processing message #{message_id}, channel: #{channel_name}, message_type: #{message.message_type}, content_type: #{message.content_type}, input_nps?: #{message.input_nps?}, input_csat?: #{message.input_csat?}"

    services = {
      'Channel::TwitterProfile' => ::Twitter::SendOnTwitterService,
      'Channel::TwilioSms' => ::Twilio::SendOnTwilioService,
      'Channel::Line' => ::Line::SendOnLineService,
      'Channel::Telegram' => ::Telegram::SendOnTelegramService,
      'Channel::Whatsapp' => ::Whatsapp::SendOnWhatsappService,
      'Channel::Sms' => ::Sms::SendOnSmsService,
      'Channel::Instagram' => ::Instagram::SendOnInstagramService,
      'Channel::Api' => ::Api::SendOnApiService
    }

    case channel_name
    when 'Channel::FacebookPage'
      Rails.logger.info "SendReplyJob: Sending via FacebookPage"
      send_on_facebook_page(message)
    else
      service_class = services[channel_name]
      if service_class.present?
        Rails.logger.info "SendReplyJob: Calling service #{service_class} for channel #{channel_name}"
        service_class.new(message: message).perform
      else
        Rails.logger.warn "SendReplyJob: No service found for channel #{channel_name}"
      end
    end
  end

  private

  def send_on_facebook_page(message)
    if message.conversation.additional_attributes['type'] == 'instagram_direct_message'
      ::Instagram::Messenger::SendOnInstagramService.new(message: message).perform
    else
      ::Facebook::SendOnFacebookService.new(message: message).perform
    end
  end
end
