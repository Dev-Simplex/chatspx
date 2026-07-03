# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageSequences::EnrollService do
  let(:account) { create(:account) }
  let(:sequence) { create(:message_sequence, :with_steps, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  describe '#perform' do
    it 'creates an active enrollment scheduled for the first step' do
      freeze_time do
        enrollment = described_class.new(sequence: sequence, conversation: conversation).perform

        expect(enrollment).to be_persisted
        expect(enrollment).to be_active
        expect(enrollment.current_step_position).to eq(1)
        # first step has delay_minutes 0 → runs now
        expect(enrollment.next_run_at).to eq(Time.current)
      end
    end

    it 'is idempotent — a second enrollment of the same conversation is a no-op' do
      described_class.new(sequence: sequence, conversation: conversation).perform
      expect do
        described_class.new(sequence: sequence, conversation: conversation).perform
      end.not_to change(MessageSequenceEnrollment, :count)
    end

    it 'allows re-enrollment after the previous one is cancelled' do
      first = described_class.new(sequence: sequence, conversation: conversation).perform
      first.cancelled!

      expect do
        described_class.new(sequence: sequence, conversation: conversation).perform
      end.to change(MessageSequenceEnrollment, :count).by(1)
    end

    it 'does nothing for an inactive sequence' do
      sequence.update!(active: false)
      expect do
        described_class.new(sequence: sequence, conversation: conversation).perform
      end.not_to change(MessageSequenceEnrollment, :count)
    end

    it 'does nothing for a sequence with no steps' do
      empty = create(:message_sequence, account: account)
      expect do
        described_class.new(sequence: empty, conversation: conversation).perform
      end.not_to change(MessageSequenceEnrollment, :count)
    end
  end
end
