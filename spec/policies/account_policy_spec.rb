# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountPolicy, type: :policy do
  subject(:account_policy) { described_class }

  let(:account_user) { build(:account_user, role: role) }
  let(:user_context) { { account_user: account_user } }

  permissions :chat_wallpaper? do
    context 'when administrator' do
      let(:role) { :administrator }

      it { expect(account_policy).to permit(user_context, Account) }
    end

    context 'when agent' do
      let(:role) { :agent }

      it { expect(account_policy).not_to permit(user_context, Account) }
    end
  end
end
