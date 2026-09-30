# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NpsResponsePolicy, type: :policy do
  subject(:nps_response_policy) { described_class }

  let(:account_user) { build(:account_user, role: role) }
  let(:user_context) { { account_user: account_user } }

  permissions :show_by_conversation? do
    context 'when administrator' do
      let(:role) { :administrator }

      it { expect(nps_response_policy).to permit(user_context, NpsResponse) }
    end

    context 'when agent' do
      let(:role) { :agent }

      it { expect(nps_response_policy).to permit(user_context, NpsResponse) }
    end
  end
end
