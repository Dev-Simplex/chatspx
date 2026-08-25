require 'rails_helper'

# O id do time/agente é escolhido pelo MODELO, não pelo operador — ele pede "distribui isso"
# e o copilot resolve sozinho. Estes testes cobrem a fronteira que faltava: nada podia
# impedir a conversa de acabar apontada pra um time (ou agente) de OUTRA conta.
RSpec.describe Captain::Tools::Copilot::AssignConversationService do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }
  let(:conversation) { create(:conversation, account: account) }

  describe '#execute' do
    context 'when the conversation does not exist' do
      it 'returns not found message' do
        expect(service.execute(conversation_id: 0)).to eq('Conversation not found')
      end
    end

    context 'when the team belongs to another account' do
      let(:foreign_team) { create(:team, account: other_account) }

      it 'refuses and leaves the conversation untouched' do
        result = service.execute(conversation_id: conversation.display_id, team_id: foreign_team.id)

        expect(result).to eq("Team #{foreign_team.id} not found in this account")
        expect(conversation.reload.team_id).to be_nil
      end
    end

    context 'when the agent belongs to another account' do
      let(:foreign_agent) { create(:user, account: other_account) }

      it 'refuses and leaves the conversation untouched' do
        result = service.execute(conversation_id: conversation.display_id, agent_id: foreign_agent.id)

        expect(result).to eq("Agent #{foreign_agent.id} not found in this account")
        expect(conversation.reload.assignee_id).to be_nil
      end
    end

    # Recusa ATÔMICA: aplicar só a metade válida imprimiria "team: none" como sucesso e
    # deixaria a conversa na fila de ninguém.
    context 'when the agent is valid but the team belongs to another account' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:foreign_team) { create(:team, account: other_account) }

      it 'applies neither' do
        service.execute(conversation_id: conversation.display_id, agent_id: agent.id, team_id: foreign_team.id)

        conversation.reload
        expect(conversation.assignee_id).to be_nil
        expect(conversation.team_id).to be_nil
      end
    end

    # Allowlist de roteamento do PR #39: o copilot escolhe o destino sozinho, então o mesmo
    # limite vale aqui. Time da conta, mas fora da lista.
    context 'when the team is outside the routing allowlist' do
      let!(:allowed_team) { create(:team, account: account) }
      let!(:blocked_team) { create(:team, account: account) }

      before { account.update!(custom_attributes: { 'handoff_allowed_team_ids' => [allowed_team.id] }) }

      it 'refuses the blocked team' do
        result = service.execute(conversation_id: conversation.display_id, team_id: blocked_team.id)

        expect(result).to eq("Team #{blocked_team.id} is not available for routing in this account")
        expect(conversation.reload.team_id).to be_nil
      end

      it 'still assigns an allowlisted team' do
        service.execute(conversation_id: conversation.display_id, team_id: allowed_team.id)

        expect(conversation.reload.team_id).to eq(allowed_team.id)
      end
    end

    # Conta que nunca configurou a allowlist não muda de comportamento.
    context 'without an allowlist configured' do
      let(:team) { create(:team, account: account) }
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'assigns any team of the account' do
        result = service.execute(conversation_id: conversation.display_id, team_id: team.id)

        expect(conversation.reload.team_id).to eq(team.id)
        expect(result).to include(team.name)
      end

      it 'assigns an agent of the account' do
        result = service.execute(conversation_id: conversation.display_id, agent_id: agent.id)

        expect(conversation.reload.assignee_id).to eq(agent.id)
        expect(result).to include(agent.name)
      end
    end
  end

  describe '#active?' do
    it 'is true for an administrator' do
      expect(service.active?).to be true
    end

    it 'is false for a custom role without conversation_manage' do
      custom_role = create(:custom_role, account: account, permissions: [])
      AccountUser.find_by(user: user, account: account).update(role: :agent, custom_role: custom_role)

      expect(service.active?).to be false
    end
  end
end
