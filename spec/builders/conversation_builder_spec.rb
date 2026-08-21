require 'rails_helper'

describe ConversationBuilder do
  let(:account) { create(:account) }
  let!(:sms_channel) { create(:channel_sms, account: account) }
  let!(:api_channel) { create(:channel_api, account: account) }
  let!(:sms_inbox) { create(:inbox, channel: sms_channel, account: account) }
  let!(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_sms_inbox) { create(:contact_inbox, contact: contact, inbox: sms_inbox) }
  let(:contact_api_inbox) { create(:contact_inbox, contact: contact, inbox: api_inbox) }

  describe '#perform' do
    it 'creates sms conversation' do
      conversation = described_class.new(
        contact_inbox: contact_sms_inbox,
        params: {}
      ).perform

      expect(conversation.contact_inbox_id).to eq(contact_sms_inbox.id)
    end

    it 'creates api conversation' do
      conversation = described_class.new(
        contact_inbox: contact_api_inbox,
        params: {}
      ).perform

      expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
    end

    context 'when lock_to_single_conversation is true for sms inbox' do
      before do
        sms_inbox.update!(lock_to_single_conversation: true)
      end

      it 'creates sms conversation when existing conversation is not present' do
        conversation = described_class.new(
          contact_inbox: contact_sms_inbox,
          params: {}
        ).perform

        expect(conversation.contact_inbox_id).to eq(contact_sms_inbox.id)
      end

      it 'returns last from existing sms conversations when existing conversation is not present' do
        # A fabrica de conversa NAO deriva inbox/contact do `contact_inbox` passado: o
        # `after(:build)` faz `inbox ||= create(:inbox, ...)` e cria uma caixa NOVA (widget). As
        # conversas do arranjo acabavam em outra caixa, e `find_contact_conversation_in_inbox` —
        # que filtra por contato + CAIXA de proposito, para cobrir varios contact_inboxes do
        # mesmo contato — nao as encontrava. O builder criava uma terceira, corretamente.
        create(:conversation, account: account, inbox: sms_inbox, contact: contact, contact_inbox: contact_sms_inbox)
        existing_conversation = create(:conversation, account: account, inbox: sms_inbox, contact: contact,
                                                      contact_inbox: contact_sms_inbox)
        conversation = described_class.new(
          contact_inbox: contact_sms_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end

    context 'when lock_to_single_conversation is true for api inbox' do
      before do
        api_inbox.update!(lock_to_single_conversation: true)
      end

      it 'creates conversation when existing api conversation is not present' do
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
      end

      it 'returns last from existing api conversations when existing conversation is not present' do
        create(:conversation, account: account, inbox: api_inbox, contact: contact, contact_inbox: contact_api_inbox)
        existing_conversation = create(:conversation, account: account, inbox: api_inbox, contact: contact,
                                                      contact_inbox: contact_api_inbox)
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end
  end
end
