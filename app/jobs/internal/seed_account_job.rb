class Internal::SeedAccountJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account

    Seeders::AccountSeeder.new(account: account).perform!
  end
end
