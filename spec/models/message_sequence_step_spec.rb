# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageSequenceStep, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:message_sequence) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_presence_of(:position) }
  end

  describe '#render_content' do
    let(:contact) { create(:contact, name: 'Maria Silva') }
    let(:conversation) { create(:conversation, contact: contact) }

    it 'interpolates {{contact.name}} and {{contact.first_name}}' do
      step = build(:message_sequence_step, content: 'Oi {{contact.first_name}} ({{contact.name}})!')
      expect(step.render_content(conversation)).to eq('Oi Maria (Maria Silva)!')
    end

    it 'is safe when the contact has no name' do
      conversation.contact.update!(name: '')
      step = build(:message_sequence_step, content: 'Oi {{contact.first_name}}!')
      expect(step.render_content(conversation)).to eq('Oi !')
    end
  end
end
