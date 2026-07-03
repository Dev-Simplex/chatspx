# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageSequences::AdvanceService do
  let(:account) { create(:account) }
  let(:sequence) { create(:message_sequence, :with_steps, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  # The send pipeline (ScheduledMessages::CreateService) requires a sender; in
  # production the account always has an administrator. AdvanceService#sender falls
  # back to it when there is no enrolled_by / assignee.
  before { create(:user, account: account, role: :administrator) }

  def enroll
    MessageSequences::EnrollService.new(sequence: sequence, conversation: conversation).perform
  end

  describe '#perform' do
    it 'sends the current step and schedules the next one' do
      enrollment = enroll

      expect do
        described_class.new(enrollment: enrollment).perform
      end.to change { ScheduledMessage.where(conversation: conversation).count }.by(1)

      enrollment.reload
      expect(enrollment).to be_active
      expect(enrollment.current_step_position).to eq(2)
      # step 2 has delay_minutes 60 → scheduled into the future
      expect(enrollment.next_run_at).to be > Time.current
    end

    it 'renders {{contact.first_name}} into the scheduled message' do
      conversation.contact.update!(name: 'João Souza')
      enrollment = enroll

      described_class.new(enrollment: enrollment).perform

      expect(ScheduledMessage.where(conversation: conversation).last.message).to include('João')
    end

    it 'completes the enrollment after the last step is sent' do
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence,
                                                        conversation: conversation,
                                                        current_step_position: 2, next_run_at: 1.minute.ago)

      described_class.new(enrollment: enrollment).perform

      enrollment.reload
      expect(enrollment).to be_completed
      expect(enrollment.current_step_position).to be_nil
      expect(enrollment.next_run_at).to be_nil
    end

    it 'is reentrant — running again before next_run_at does not resend' do
      enrollment = enroll
      described_class.new(enrollment: enrollment).perform

      expect do
        described_class.new(enrollment: enrollment.reload).perform
      end.not_to(change { ScheduledMessage.where(conversation: conversation).count })
    end

    it 'does not send when next_run_at is still in the future' do
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence,
                                                        conversation: conversation,
                                                        current_step_position: 1, next_run_at: 1.hour.from_now)

      expect do
        described_class.new(enrollment: enrollment).perform
      end.not_to change(ScheduledMessage, :count)
    end
  end
end
