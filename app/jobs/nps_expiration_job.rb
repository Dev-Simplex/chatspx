class NpsExpirationJob < ApplicationJob
  queue_as :default

  def perform
    expire_nps_surveys
  end

  private

  def expire_nps_surveys
    # Find all sent NPS responses that haven't been responded yet
    sent_nps_responses = NpsResponse.where(status: :sent)
                                    .where.not(sent_at: nil)
                                    .includes(:inbox, :conversation)

    sent_nps_responses.find_each do |nps_response|
      next unless expired?(nps_response)

      nps_response.update!(status: :expired)
      create_expired_activity_message(nps_response)
    end
  end

  def create_expired_activity_message(nps_response)
    content = I18n.t('conversations.activity.nps.expired', default: 'NPS survey expired')
    activity_message_params = {
      account_id: nps_response.account_id,
      inbox_id: nps_response.inbox_id,
      message_type: :activity,
      content: content
    }
    conversation = nps_response.conversation
    ::Conversations::ActivityMessageJob.perform_later(conversation.id, activity_message_params) if content
  end

  def expired?(nps_response)
    return false unless nps_response.sent_at

    inbox = nps_response.inbox
    nps_config = inbox.nps_config || {}
    expiration_hours = nps_config['expiration_hours'] || 72

    nps_response.sent_at < expiration_hours.hours.ago
  end
end
