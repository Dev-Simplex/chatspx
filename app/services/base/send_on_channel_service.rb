#######################################
# To create an external channel reply service
# - Inherit this as the base class.
# - Implement `channel_class` method in your child class.
# - Implement `perform_reply` method in your child class.
# - Implement additional custom logic for your `perform_reply` method.
# - When required override the validation_methods.
# - Use Childclass.new.perform.
######################################
class Base::SendOnChannelService
  pattr_initialize [:message!]

  def perform
    Rails.logger.info "Base::SendOnChannelService: perform called for message #{message.id}, message_type: #{message.message_type}, content_type: #{message.content_type}, outgoing?: #{message.outgoing?}, template?: #{message.template?}, private?: #{message.private?}"
    validate_target_channel
    Rails.logger.info "Base::SendOnChannelService: Channel validated, outgoing_message?: #{outgoing_message?}, invalid_message?: #{invalid_message?}"
    return unless outgoing_message?
    return if invalid_message?

    Rails.logger.info "Base::SendOnChannelService: Calling perform_reply"
    perform_reply
  end

  private

  delegate :conversation, to: :message
  delegate :contact, :contact_inbox, :inbox, to: :conversation
  delegate :channel, to: :inbox

  def channel_class
    raise 'Overwrite this method in child class'
  end

  def perform_reply
    raise 'Overwrite this method in child class'
  end

  def outgoing_message_originated_from_channel?
    # TODO: we need to refactor this logic as more integrations comes by
    # chatwoot messages won't have source id at the moment
    # TODO: migrate source_ids to external_source_ids and check the source id relevant to specific channel
    message.source_id.present?
  end

  def outgoing_message?
    message.outgoing? || message.template?
  end

  def invalid_message?
    # private notes aren't send to the channels
    # we should also avoid the case of message loops, when outgoing messages are created from channel
    message.private? || outgoing_message_originated_from_channel?
  end

  def validate_target_channel
    raise 'Invalid channel service was called' if inbox.channel.class != channel_class
  end
end
