# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageSequences::ExitListener do
  let(:account) { create(:account) }
  let(:sequence) do
    create(:message_sequence, :with_steps, account: account,
                                           exit_conditions: { 'on_customer_reply' => true })
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:listener) { described_class.instance }

  def event_for(data)
    Struct.new(:data).new(data)
  end

  describe '#message_created' do
    it 'cancels active enrollments on an incoming message when on_customer_reply is set' do
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence, conversation: conversation)
      message = create(:message, account: account, conversation: conversation, message_type: :incoming)

      listener.message_created(event_for(message: message))

      expect(enrollment.reload).to be_cancelled
    end

    it 'does not cancel when the sequence opts out of reply-exit' do
      sequence.update!(exit_conditions: { 'on_customer_reply' => false })
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence, conversation: conversation)
      message = create(:message, account: account, conversation: conversation, message_type: :incoming)

      listener.message_created(event_for(message: message))

      expect(enrollment.reload).to be_active
    end

    it 'ignores outgoing messages' do
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence, conversation: conversation)
      message = create(:message, account: account, conversation: conversation, message_type: :outgoing)

      listener.message_created(event_for(message: message))

      expect(enrollment.reload).to be_active
    end
  end

  describe '#conversation_status_changed' do
    it 'cancels enrollments whose exit_status matches the new status' do
      sequence.update!(exit_conditions: { 'on_status' => 'resolved' })
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence, conversation: conversation)
      conversation.update!(status: :resolved)

      listener.conversation_status_changed(event_for(conversation: conversation))

      expect(enrollment.reload).to be_cancelled
    end

    it 'leaves enrollments untouched when the status does not match' do
      sequence.update!(exit_conditions: { 'on_status' => 'resolved' })
      enrollment = create(:message_sequence_enrollment, message_sequence: sequence, conversation: conversation)
      conversation.update!(status: :open)

      listener.conversation_status_changed(event_for(conversation: conversation))

      expect(enrollment.reload).to be_active
    end
  end
end
