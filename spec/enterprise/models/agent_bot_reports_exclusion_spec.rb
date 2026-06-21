require 'rails_helper'

# E3/E-L8 (gap residual do C8) — espelho captain FORA dos relatórios por agente:
# a conversa cuja dona é a IA (assignee_agent_bot_id) tem assignee_id nil (invariante
# de exclusividade da Fase A), então NÃO pode contar nas métricas de nenhum humano
# (V2 reports agent metric usa User#conversations = assigned_conversations).
# Arquivo nomeado pelo design (fase-d-design.md §10.4) — descreve o builder de propósito.
RSpec.describe V2::ReportBuilder do # rubocop:disable RSpec/SpecFilePathFormat
  describe 'agent conversation metrics with captain mirror conversations' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
    let!(:agent) { create(:user, account: account, role: :agent) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:mirror) { assistant.mirror_agent_bot }

    let!(:mirror_conversation) do
      create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror, status: :open)
    end

    before do
      # conversa humana de controle: única que pode contar na métrica do agente
      create(:conversation, account: account, inbox: inbox, assignee: agent, status: :open)
    end

    def agent_metrics_for(user)
      described_class.new(account, { type: :agent, business_hours: false })
                     .conversation_metrics
                     .find { |metric| metric[:id] == user.id }
    end

    it 'does not count mirror-owned conversations in any agent metric' do
      metric = agent_metrics_for(agent)

      expect(metric[:metric][:open]).to eq(1) # só a conversa humana; a do espelho fica fora
    end

    it 'does not leak the mirror conversation to other agents either' do
      other_agent = create(:user, account: account, role: :agent)

      expect(agent_metrics_for(other_agent)[:metric][:open]).to eq(0)
    end

    it 'counts the conversation for the human after a takeover from the mirror' do
      mirror_conversation.update!(assignee: agent) # reset core limpa o espelho no MESMO save

      expect(mirror_conversation.reload.assignee_agent_bot_id).to be_nil
      expect(agent_metrics_for(agent)[:metric][:open]).to eq(2)
    end
  end
end
