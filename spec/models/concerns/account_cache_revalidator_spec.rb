require 'rails_helper'

RSpec.describe AccountCacheRevalidator do
  it 'allows dependent records to be cleaned up after their account is deleted' do
    account = create(:account)
    team = create(:team, account: account)
    account.destroy!

    expect { team.reload.destroy! }.not_to raise_error
  end

  it 'updates the account cache when the account still exists' do
    team = create(:team)

    expect(team.account).to receive(:update_cache_key).with('team')
    team.update_account_cache
  end
end
