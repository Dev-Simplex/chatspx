require 'rails_helper'

# Regression coverage for the duplicate-conversation bug: forwarding several messages to the
# same contact (the dashboard fires one parallel request per message) used to create one new
# conversation per request, and forwarding to a contact whose previous conversation was resolved
# spawned yet another conversation. The fix delegates to ConversationBuilder, which reuses the
# contact's conversation on the inbox (honouring lock_to_single_conversation) under a per-(inbox,
# contact) Redis lock.
describe Messages::ForwardService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: true) }

  let(:source_contact) { create(:contact, account: account) }
  let(:source_contact_inbox) { create(:contact_inbox, contact: source_contact, inbox: inbox) }
  let(:source_conversation) do
    create(:conversation, account: account, inbox: inbox, contact: source_contact, contact_inbox: source_contact_inbox)
  end
  # `let!` de proposito: `message` encadeia `source_conversation`, que CRIA uma conversa. Sendo
  # preguicoso, ele so era avaliado dentro do bloco `expect { ... }.to change(Conversation, :count)`
  # — ou seja, a conversa de ORIGEM entrava na contagem junto com a de destino e todo exemplo
  # media um a mais. Materializando antes, a medicao passa a contar so o que o forward cria.
  let!(:message) do
    create(:message, conversation: source_conversation, account: account, content: 'forward me', message_type: :incoming)
  end

  let(:target_contact) { create(:contact, account: account) }
  let!(:target_contact_inbox) { create(:contact_inbox, contact: target_contact, inbox: inbox) }

  def forward_to_contact(contact_id = target_contact.id)
    described_class.new(
      message: message, target_conversation_ids: [], target_contact_ids: [contact_id], user: agent
    ).perform
  end

  describe '#perform forwarding to a contact' do
    context 'when the contact already has an open conversation on the inbox' do
      let!(:existing) do
        create(:conversation, account: account, inbox: inbox, contact: target_contact,
                              contact_inbox: target_contact_inbox, status: :open)
      end

      it 'reuses it instead of creating a new conversation' do
        expect { forward_to_contact }.not_to change(Conversation, :count)
      end

      it 'appends the forwarded message to the existing conversation' do
        result = forward_to_contact
        expect(result[:success]).to be true

        forwarded = existing.reload.messages.last
        expect(forwarded.content).to eq('forward me')
        expect(forwarded.message_type).to eq('outgoing')
        expect(forwarded.forwarded).to be true
        expect(forwarded.forwarded_from_message_id).to eq(message.id)
      end
    end

    context 'when the contact only has a resolved conversation' do
      let!(:resolved) do
        create(:conversation, account: account, inbox: inbox, contact: target_contact,
                              contact_inbox: target_contact_inbox, status: :resolved)
      end

      it 'reuses and reopens it rather than creating a duplicate' do
        expect { forward_to_contact }.not_to change(Conversation, :count)
        expect(resolved.reload.status).to eq('open')
      end
    end

    context 'when the contact has no conversation yet' do
      it 'creates exactly one conversation' do
        expect { forward_to_contact }.to change(Conversation, :count).by(1)
      end
    end

    context 'when the same message is forwarded to the same contact repeatedly' do
      it 'does not keep creating duplicate conversations' do
        forward_to_contact
        expect { forward_to_contact }.not_to change(Conversation, :count)
      end
    end

    context 'when the inbox does not lock to a single conversation' do
      let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: false) }
      let!(:existing) do
        create(:conversation, account: account, inbox: inbox, contact: target_contact,
                              contact_inbox: target_contact_inbox, status: :open)
      end

      it 'still reuses the existing conversation instead of creating a duplicate' do
        expect { forward_to_contact }.not_to change(Conversation, :count)
        expect(existing.reload.messages.last.content).to eq('forward me')
      end
    end
  end

  describe '#perform forwarding to an explicit conversation' do
    let(:other_contact) { create(:contact, account: account) }
    let(:other_contact_inbox) { create(:contact_inbox, contact: other_contact, inbox: inbox) }
    let!(:target_conversation) do
      create(:conversation, account: account, inbox: inbox, contact: other_contact, contact_inbox: other_contact_inbox)
    end

    it 'appends to the chosen conversation without creating a new one' do
      result = described_class.new(
        message: message, target_conversation_ids: [target_conversation.display_id],
        target_contact_ids: [], user: agent
      ).perform

      expect(result[:success]).to be true
      expect(target_conversation.reload.messages.last.content).to eq('forward me')
    end
  end
end
