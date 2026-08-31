# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamMessageIsolation do
  let!(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:team) { create(:team, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, team: team) }

  describe '.apply?' do
    context 'when the inbox does not have team isolation enabled' do
      it 'does not apply for anyone' do
        expect(described_class.apply?(conversation, agent)).to be(false)
        expect(described_class.apply?(conversation, nil)).to be(false)
      end
    end

    context 'when the inbox has team isolation enabled' do
      before { inbox.update!(team_message_isolation: true) }

      # lista de exceções vazia = comportamento de hoje
      it 'applies to an agent when there is no exemption' do
        expect(described_class.apply?(conversation.reload, agent)).to be(true)
      end

      # a guarda que impede um job de relatório enxergar mensagem de outro time
      it 'applies when there is no viewer (job, public API, widget)' do
        expect(described_class.apply?(conversation.reload, nil)).to be(true)
      end

      # comportamento de hoje preservado: o filtro por time sempre valeu para o admin também
      it 'applies to an administrator, as it always did' do
        expect(described_class.apply?(conversation.reload, admin)).to be(true)
      end

      it 'stops applying to the exempt agent' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')

        expect(described_class.apply?(conversation.reload, agent)).to be(false)
      end

      it 'keeps applying to an agent who is not an exemption' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')
        outro = create(:user, account: account, role: :agent)

        expect(described_class.apply?(conversation.reload, outro)).to be(true)
      end

      # os dois isolamentos são independentes: isentar do de agente não isenta do de time
      it 'ignores an exemption of the agent isolation' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'agent_message')

        expect(described_class.apply?(conversation.reload, agent)).to be(true)
      end

      it 'does not apply when the conversation has no team' do
        no_team = create(:conversation, account: account, inbox: inbox, team: nil)

        expect(described_class.apply?(no_team, agent)).to be(false)
      end

      it 'does not apply without a conversation' do
        expect(described_class.apply?(nil, agent)).to be(false)
      end
    end
  end

  describe '.exempt?' do
    it 'is false without a user and without an inbox' do
      expect(described_class.exempt?(nil, inbox)).to be(false)
      expect(described_class.exempt?(agent, nil)).to be(false)
    end

    it 'is true only for the inbox where the exemption was recorded' do
      other_inbox = create(:inbox, account: account)
      create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')

      expect(described_class.exempt?(agent, inbox)).to be(true)
      expect(described_class.exempt?(agent, other_inbox)).to be(false)
    end

    # Um agente isentado e depois PROMOVIDO sai da lista de participantes da tela (só
    # agentes entram lá), então a linha vira invisível. Sem a guarda de papel ele seria o
    # único administrador da conta a escapar do isolamento por time — que vale para o
    # admin também. A linha é criada DEPOIS da promoção de propósito: é o retrato de uma
    # linha que já estava no banco antes da correção, e é justamente ela que a limpeza
    # por evento não alcança.
    it 'is false for a promoted administrator even with an old exemption row' do
      account.account_users.find_by(user_id: agent.id).update!(role: :administrator)
      create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')

      expect(described_class.exempt?(User.find(agent.id), inbox)).to be(false)
    end
  end
end
