# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScheduledMessages::ResolveConversationService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+14155550100') }

  describe '#perform' do
    it 'returns existing conversation when conversation_id is provided' do
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      conversation = create(
        :conversation,
        account: account,
        contact: contact,
        inbox: inbox,
        contact_inbox: contact_inbox
      )

      resolved = described_class.new(
        account: account,
        conversation_id: conversation.id
      ).perform

      expect(resolved.id).to eq(conversation.id)
    end

    it 'returns active conversation for contact/inbox when available' do
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      active_conversation = create(
        :conversation,
        account: account,
        contact: contact,
        inbox: inbox,
        contact_inbox: contact_inbox,
        status: :open
      )

      resolved = described_class.new(
        account: account,
        contact_id: contact.id,
        inbox_id: inbox.id
      ).perform

      expect(resolved.id).to eq(active_conversation.id)
    end

    it 'creates a new conversation when none exists for contact/inbox' do
      resolved = nil

      expect do
        resolved = described_class.new(
          account: account,
          contact_id: contact.id,
          inbox_id: inbox.id
        ).perform
      end.to change(Conversation, :count).by(1)

      expect(resolved).to be_present
      expect(resolved.contact_id).to eq(contact.id)
      expect(resolved.inbox_id).to eq(inbox.id)
    end

    it 'raises on invalid contact/inbox input' do
      expect do
        described_class.new(
          account: account,
          contact_id: nil,
          inbox_id: inbox.id
        ).perform
      end.to raise_error(ArgumentError)
    end
  end
end
