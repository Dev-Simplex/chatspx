# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageSequenceEnrollment, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:message_sequence) }
    it { is_expected.to belong_to(:conversation) }
    it { is_expected.to belong_to(:enrolled_by).class_name('User').optional }
  end

  describe 'enum status' do
    it 'defines the lifecycle states' do
      expect(described_class.statuses).to eq('active' => 0, 'completed' => 1, 'cancelled' => 2)
    end
  end

  describe '.due' do
    let(:sequence) { create(:message_sequence, :with_steps) }

    it 'returns active enrollments whose next_run_at has passed' do
      due = create(:message_sequence_enrollment, message_sequence: sequence, next_run_at: 1.minute.ago)
      create(:message_sequence_enrollment, message_sequence: sequence, next_run_at: 1.hour.from_now)
      create(:message_sequence_enrollment, message_sequence: sequence, status: :completed, next_run_at: 1.minute.ago)

      expect(described_class.due).to contain_exactly(due)
    end
  end

  describe '#current_step' do
    it 'returns the step at current_step_position' do
      sequence = create(:message_sequence, :with_steps)
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence, current_step_position: 2)
      expect(enrollment.current_step.position).to eq(2)
    end

    it 'returns nil once past the last step' do
      sequence = create(:message_sequence, :with_steps)
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence, current_step_position: nil)
      expect(enrollment.current_step).to be_nil
    end
  end
end
