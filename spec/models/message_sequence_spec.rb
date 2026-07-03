# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageSequence, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
    it { is_expected.to have_many(:steps).class_name('MessageSequenceStep').dependent(:destroy) }
    it { is_expected.to have_many(:enrollments).class_name('MessageSequenceEnrollment').dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe 'exit condition helpers' do
    let(:account) { create(:account) }

    it 'defaults cancel_on_customer_reply? to true' do
      sequence = create(:message_sequence, account: account, exit_conditions: {})
      expect(sequence.cancel_on_customer_reply?).to be(true)
    end

    it 'respects an explicit on_customer_reply=false' do
      sequence = create(:message_sequence, account: account, exit_conditions: { 'on_customer_reply' => false })
      expect(sequence.cancel_on_customer_reply?).to be(false)
    end

    it 'exposes the configured exit status' do
      sequence = create(:message_sequence, account: account, exit_conditions: { 'on_status' => 'resolved' })
      expect(sequence.exit_status).to eq('resolved')
    end
  end

  describe 'steps ordering' do
    it 'returns steps ordered by position' do
      sequence = create(:message_sequence)
      create(:message_sequence_step, message_sequence: sequence, position: 2)
      create(:message_sequence_step, message_sequence: sequence, position: 1)
      expect(sequence.steps.pluck(:position)).to eq([1, 2])
    end
  end
end
