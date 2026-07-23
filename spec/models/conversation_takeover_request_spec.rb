# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationTakeoverRequest do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:requester) { create(:user, account: account, role: :agent) }

  def build_request(reason:)
    described_class.new(account: account, conversation: conversation, requester: requester, reason: reason)
  end

  describe 'reason length' do
    it 'accepts a blank reason' do
      expect(build_request(reason: nil)).to be_valid
    end

    it 'accepts a reason up to the cap' do
      expect(build_request(reason: 'a' * described_class::REASON_MAX_LENGTH)).to be_valid
    end

    it 'rejects a reason over the cap (API cannot trust the client :maxlength)' do
      request = build_request(reason: 'a' * (described_class::REASON_MAX_LENGTH + 1))
      expect(request).not_to be_valid
      expect(request.errors[:reason]).to be_present
    end
  end
end
