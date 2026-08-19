# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversations::ListPreloader do
  let!(:account) { create(:account) }
  let!(:agent_a) { create(:user, account: account, role: :agent) }
  let!(:agent_b) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }

  # presença de uma msg pública no meio garante que o filtro não a descarta nem quebra a ordenação
  let!(:public_msg) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'public hi')
  end
  let!(:from_a) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent_a,
                     content: 'from A')
  end
  let!(:from_b) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent_b,
                     content: 'from B')
  end

  after { Current.user = nil }

  describe 'last message preview with agent_message_isolation' do
    context 'when isolation is enabled' do
      before { inbox.update!(agent_message_isolation: true) }

      it 'previews the last message visible to the viewing agent (hides other agents)' do
        result = described_class.call([conversation], user: agent_a)
        preview = result.last_non_activity_messages[conversation.id]
        # from_b is the real latest, but it belongs to agent_b -> hidden for agent_a
        expect(preview.id).to eq(from_a.id)
      end

      it 'previews the real last message for an administrator' do
        result = described_class.call([conversation], user: admin)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)
      end

      it 'previews the real last message when there is no viewer (default Current.user nil)' do
        result = described_class.call([conversation], user: nil)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)
      end
    end

    context 'when isolation is disabled' do
      it 'previews the real last message even for a non-admin agent' do
        result = described_class.call([conversation], user: agent_a)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)
      end
    end

    # EXCEÇÕES: a prévia da LISTA é um dos quatro pontos de leitura; sem isto o agente
    # isento abriria a conversa e veria tudo, mas a lista continuaria recortada.
    context 'when the agent is an exemption of that inbox' do
      before do
        inbox.update!(agent_message_isolation: true)
        create(:inbox_isolation_exemption, inbox: inbox, user: agent_a, isolation_type: 'agent_message')
      end

      it 'previews the real last message for the exempt agent' do
        result = described_class.call([conversation], user: agent_a)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)
      end

      it 'keeps recutting the preview for an agent who is not an exemption' do
        result = described_class.call([conversation], user: agent_b)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)

        outro = create(:user, account: account, role: :agent)
        result = described_class.call([conversation], user: outro)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(public_msg.id)
      end
    end
  end

  # A prévia carrega a MESMA cláusula de time que vive na association conversation.messages,
  # então a exceção do isolamento por time precisa valer aqui também.
  describe 'last message preview with team_message_isolation' do
    let!(:team_a) { create(:team, account: account) }
    let!(:team_b) { create(:team, account: account) }
    let!(:team_conversation) { create(:conversation, account: account, inbox: inbox, team: team_a) }
    let!(:team_a_msg) do
      create(:message, conversation: team_conversation, account: account, inbox: inbox, message_type: :outgoing,
                       sender: agent_a, content: 'do time A')
    end
    let!(:team_b_msg) do
      create(:message, conversation: team_conversation, account: account, inbox: inbox, message_type: :outgoing,
                       sender: agent_b, content: 'do time B').tap do |message|
        message.update_column(:team_id, team_b.id) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    before { inbox.update!(team_message_isolation: true) }

    it 'previews only the current team message when there is no exemption' do
      result = described_class.call([team_conversation], user: agent_a)
      expect(result.last_non_activity_messages[team_conversation.id].id).to eq(team_a_msg.id)
    end

    it 'previews the real last message for the exempt agent' do
      create(:inbox_isolation_exemption, inbox: inbox, user: agent_a, isolation_type: 'team_message')

      result = described_class.call([team_conversation], user: agent_a)
      expect(result.last_non_activity_messages[team_conversation.id].id).to eq(team_b_msg.id)
    end

    it 'keeps the filter when there is no viewer (job/public API)' do
      create(:inbox_isolation_exemption, inbox: inbox, user: agent_a, isolation_type: 'team_message')

      result = described_class.call([team_conversation], user: nil)
      expect(result.last_non_activity_messages[team_conversation.id].id).to eq(team_a_msg.id)
    end
  end
end
