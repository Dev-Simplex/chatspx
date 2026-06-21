require 'rails_helper'

# E2 (Fase E) — atribuição do disparo SEMPRE pelo trilho canônico (Conversations::
# AssignmentService): reatribuir uma conversa cujo dono é o espelho captain limpa o
# espelho no MESMO save, preservando a invariante humano×IA da Fase A.
RSpec.describe Spx::Tozi::DisparoLeadJob do
  describe '#find_or_create_conversation (E2 — trilho canônico de atribuição)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:job) { described_class.new }

    def find_or_create(assignee_id: agent.id, campaign_id: nil)
      job.send(:find_or_create_conversation, inbox, contact_inbox, assignee_id, campaign_id, 'tozi_lancamento_interagir')
    end

    context 'when the existing conversation is owned by a captain mirror' do
      let(:assistant) { create(:captain_assistant, account: account) }
      let!(:conversation) do
        create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                              assignee: nil, assignee_agent_bot: assistant.mirror_agent_bot, status: :open)
      end

      it 'reassigns via AssignmentService clearing the mirror in the same save (invariante Fase A)' do
        result = find_or_create

        expect(result.id).to eq(conversation.id)
        conversation.reload
        expect(conversation.assignee_id).to eq(agent.id)
        expect(conversation.assignee_agent_bot_id).to be_nil
      end
    end

    it 'does not reassign when the conversation already belongs to the corretor' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact,
                                           contact_inbox: contact_inbox, assignee: agent, status: :open)
      expect(Conversations::AssignmentService).not_to receive(:new)

      expect(find_or_create.id).to eq(conversation.id)
    end

    it 'reopens a resolved conversation and assigns the corretor' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact,
                                           contact_inbox: contact_inbox, assignee: nil, status: :resolved)

      result = find_or_create

      expect(result.id).to eq(conversation.id)
      expect(result.reload).to be_open
      expect(result.assignee_id).to eq(agent.id)
    end

    it 'creates a new conversation already assigned when the contact never had one' do
      result = find_or_create

      expect(result).to be_persisted
      expect(result.assignee_id).to eq(agent.id)
      expect(result.assignee_agent_bot_id).to be_nil
      expect(result.additional_attributes['source']).to eq('disparo_lancamento')
    end
  end
end
