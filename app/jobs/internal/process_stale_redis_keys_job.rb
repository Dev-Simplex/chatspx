# housekeeping
# remove contact inboxes that does not have any conversations
# and are older than 3 months

class Internal::ProcessStaleRedisKeysJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account

    removed_count = Internal::RemoveStaleRedisKeysService.new(account_id: account.id).perform
    Rails.logger.info "Successfully cleaned up Redis keys for account #{account.id} (removed #{removed_count} keys)"
  end
end
