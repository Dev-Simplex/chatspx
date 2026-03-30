class SendOnSlackJob < MutexApplicationJob
  queue_as :medium
  retry_on LockAcquisitionError, wait: 1.second, attempts: 8

  def perform(message_id, hook_id)
    return unless (message = Message.find_by(id: message_id))
    return unless (hook = Integrations::Hook.find_by(id: hook_id))

    key = format(::Redis::Alfred::SLACK_MESSAGE_MUTEX, conversation_id: message.conversation_id, reference_id: hook.reference_id)
    with_lock(key) do
      Integrations::Slack::SendOnSlackService.new(message: message, hook: hook).perform
    end
  end
end
