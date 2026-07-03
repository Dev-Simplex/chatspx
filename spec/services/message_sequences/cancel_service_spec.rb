# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageSequences::CancelService do
  let(:account) { create(:account) }
  let(:sequence) { create(:message_sequence, :with_steps, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  describe '.cancel_for' do
    it 'cancels the active enrollment of the conversation' do
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence, conversation: conversation)

      described_class.cancel_for(conversation, reason: :customer_reply)

      enrollment.reload
      expect(enrollment).to be_cancelled
      expect(enrollment.next_run_at).to be_nil
    end

    it 'leaves enrollments of other conversations untouched' do
      other = create(:conversation, account: account)
      other_enrollment = create(:message_sequence_enrollment, message_sequence: sequence, conversation: other)

      described_class.cancel_for(conversation)

      expect(other_enrollment.reload).to be_active
    end

    it 'does not touch already completed enrollments' do
      done = create(:message_sequence_enrollment, message_sequence: sequence, conversation: conversation,
                                                  status: :completed)

      described_class.cancel_for(conversation)

      expect(done.reload).to be_completed
    end
  end
end
