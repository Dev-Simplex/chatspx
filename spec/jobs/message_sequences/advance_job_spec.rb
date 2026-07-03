# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageSequences::AdvanceJob do
  let(:account) { create(:account) }
  let(:sequence) { create(:message_sequence, :with_steps, account: account) }

  before { create(:user, account: account, role: :administrator) }

  it 'advances due enrollments and skips future ones' do
    due_conv = create(:conversation, account: account)
    future_conv = create(:conversation, account: account)
    due = create(:message_sequence_enrollment, message_sequence: sequence, conversation: due_conv,
                                               current_step_position: 1, next_run_at: 1.minute.ago)
    future = create(:message_sequence_enrollment, message_sequence: sequence, conversation: future_conv,
                                                  current_step_position: 1, next_run_at: 1.hour.from_now)

    described_class.perform_now

    expect(due.reload.current_step_position).to eq(2)
    expect(future.reload.current_step_position).to eq(1)
  end
end
