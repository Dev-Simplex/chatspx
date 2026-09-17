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
        # inbox e contact explicitos: sem eles a factory cria outra conta/caixa/contato, e o builder
        # busca por caixa + contato.
        create(:conversation, account: account, inbox: sms_inbox, contact: contact, contact_inbox: contact_sms_inbox)
        existing_conversation = create(:conversation, account: account, inbox: sms_inbox, contact: contact, contact_inbox: contact_sms_inbox)
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
        existing_conversation = create(:conversation, account: account, inbox: api_inbox, contact: contact, contact_inbox: contact_api_inbox)
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end

    # Outro request do mesmo contato segura a trava de criacao (a corrida do GlitchTip producao 115).
    context 'when another request holds the creation lock' do
      let(:lock_key) { "conv_builder:#{api_inbox.id}:#{contact.id}" }

      before { Redis::Alfred.set(lock_key, '1', ex: 10) }
      after { Redis::Alfred.delete(lock_key) }

      it 'still creates the conversation on an inbox without the single-conversation rule' do
        conversation = described_class.new(contact_inbox: contact_api_inbox, params: {}).perform

        expect(conversation).to be_persisted
        expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
      end

      it 'returns the existing conversation on a single-conversation inbox instead of creating another' do
        api_inbox.update!(lock_to_single_conversation: true)
        existing_conversation = create(:conversation, account: account, inbox: api_inbox, contact: contact, contact_inbox: contact_api_inbox)

        conversation = nil
        expect { conversation = described_class.new(contact_inbox: contact_api_inbox, params: {}).perform }
          .not_to change(Conversation, :count)
        expect(conversation.id).to eq(existing_conversation.id)
      end
    end
  end
end
