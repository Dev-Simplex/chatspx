# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentMessageIsolation do
  let!(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }

  describe '.viewer_restriction_id' do
    it 'returns the user id for a non-admin agent' do
      expect(described_class.viewer_restriction_id(agent, account)).to eq(agent.id)
    end

    it 'returns nil for an administrator' do
      expect(described_class.viewer_restriction_id(admin, account)).to be_nil
    end

    it 'returns nil when there is no user (widget/public/job context)' do
      expect(described_class.viewer_restriction_id(nil, account)).to be_nil
    end

    it 'accepts an account id instead of an account object' do
      expect(described_class.viewer_restriction_id(agent, account.id)).to eq(agent.id)
    end

    it 'returns nil when the account is blank' do
      expect(described_class.viewer_restriction_id(agent, nil)).to be_nil
    end
  end

  describe '.restriction_id_for_inbox' do
    let!(:team) { create(:team, account: account) }
    let!(:other_team) { create(:team, account: account) }

    it 'returns nil when the inbox does not have isolation enabled' do
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, team.id)).to be_nil
    end

    it 'returns the agent id when isolation is enabled' do
      inbox.update!(agent_message_isolation: true)
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, team.id)).to eq(agent.id)
    end

    it 'returns nil for an admin even with isolation enabled' do
      inbox.update!(agent_message_isolation: true)
      expect(described_class.restriction_id_for_inbox(inbox, admin, account, team.id)).to be_nil
    end

    # ESCOPO POR TIME
    it 'restricts any team when the team list is empty (retrocompat)' do
      inbox.update!(agent_message_isolation: true, agent_message_isolation_team_ids: [])
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, other_team.id)).to eq(agent.id)
    end

    it 'restricts a team inside the chosen list' do
      inbox.update!(agent_message_isolation: true, agent_message_isolation_team_ids: [team.id])
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, team.id)).to eq(agent.id)
    end

    it 'does not restrict a team outside the chosen list' do
      inbox.update!(agent_message_isolation: true, agent_message_isolation_team_ids: [team.id])
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, other_team.id)).to be_nil
    end

    it 'does not restrict a conversation without a team' do
      inbox.update!(agent_message_isolation: true, agent_message_isolation_team_ids: [team.id])
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, nil)).to be_nil
    end

    it 'does not restrict a conversation without a team even with an empty list' do
      inbox.update!(agent_message_isolation: true, agent_message_isolation_team_ids: [])
      expect(described_class.restriction_id_for_inbox(inbox, agent, account, nil)).to be_nil
    end
  end

  describe '.filter_messages' do
    let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:public_msg) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
    end
    let!(:mine) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent)
    end
    let!(:other) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                       sender: create(:user, account: account, role: :agent))
    end

    it 'returns the same scope untouched when restriction id is nil' do
      scope = conversation.messages
      expect(described_class.filter_messages(scope, nil)).to be(scope)
    end

    it 'keeps public (agent_id NULL) and own messages, drops other agents messages' do
      ids = described_class.filter_messages(conversation.messages, agent.id).map(&:id)
      expect(ids).to include(public_msg.id, mine.id)
      expect(ids).not_to include(other.id)
    end
  end

  # EXCEÇÕES POR AGENTE: quem está na tabela volta a ver as mensagens dos outros NAQUELA
  # caixa. Convive com os isentos que já existiam (admin, supervisor) sem substituí-los.
  describe 'exemptions' do
    let!(:other_inbox) { create(:inbox, account: account) }

    before { inbox.update!(agent_message_isolation: true) }

    describe '.exempt?' do
      it 'is false when there is no exemption row (comportamento de hoje)' do
        expect(described_class.exempt?(agent, inbox)).to be(false)
      end

      it 'is true for the agent listed as an exemption of that inbox' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'agent_message')

        expect(described_class.exempt?(agent, inbox)).to be(true)
      end

      it 'does not leak to another inbox' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'agent_message')

        expect(described_class.exempt?(agent, other_inbox)).to be(false)
      end

      it 'does not read the team isolation exemption' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')

        expect(described_class.exempt?(agent, inbox)).to be(false)
      end

      it 'is false without a user (job/widget/public API)' do
        expect(described_class.exempt?(nil, inbox)).to be(false)
      end

      it 'is false without an inbox' do
        expect(described_class.exempt?(agent, nil)).to be(false)
      end

      # Mesma guarda de papel do isolamento por time (ver TeamMessageIsolation): a linha é
      # criada DEPOIS da promoção porque o que precisa ficar inofensivo é a linha ANTIGA,
      # a que a limpeza por evento não teve como alcançar. Aqui o administrador já era
      # isento por outro caminho (viewer_restriction_id), então isto é cinto e suspensório
      # — mas mantém as duas regras respondendo a mesma coisa sobre a mesma linha.
      it 'is false for a promoted administrator even with an old exemption row' do
        account.account_users.find_by(user_id: agent.id).update!(role: :administrator)
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'agent_message')

        promoted = User.find(agent.id)
        expect(described_class.exempt?(promoted, inbox)).to be(false)
        expect(described_class.exempt_inbox_ids(promoted, account)).to be_empty
      end
    end

    describe '.exempt_inbox_ids' do
      it 'is empty when nobody is an exemption' do
        expect(described_class.exempt_inbox_ids(agent, account)).to be_empty
      end

      it 'lists the inboxes where the agent is an exemption' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'agent_message')

        expect(described_class.exempt_inbox_ids(agent, account)).to contain_exactly(inbox.id)
      end

      it 'accepts an account id and is empty for a blank account or no user' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'agent_message')

        expect(described_class.exempt_inbox_ids(agent, account.id)).to contain_exactly(inbox.id)
        expect(described_class.exempt_inbox_ids(agent, nil)).to be_empty
        expect(described_class.exempt_inbox_ids(nil, account)).to be_empty
      end
    end

    describe '.restriction_id_for_inbox' do
      # A assinatura pede o team_id porque o OUTRO eixo da regra e o escopo por time.
      # Lista de escopo vazia (o padrao) = a regra vale para todos os times, entao o que
      # estes exemplos medem continua sendo so a ISENCAO.
      let!(:team) { create(:team, account: account) }

      it 'stops restricting the exempt agent' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'agent_message')

        expect(described_class.restriction_id_for_inbox(inbox, agent, account, team.id)).to be_nil
      end

      it 'keeps restricting an agent who is not an exemption' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'agent_message')
        outro = create(:user, account: account, role: :agent)

        expect(described_class.restriction_id_for_inbox(inbox, outro, account, team.id)).to eq(outro.id)
      end

      it 'keeps restricting the exempt agent in the inboxes where he is not an exemption' do
        create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'agent_message')
        other_inbox.update!(agent_message_isolation: true)

        expect(described_class.restriction_id_for_inbox(other_inbox, agent, account, team.id)).to eq(agent.id)
      end
    end
  end
end
