# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversations::ListPreloader do
  let!(:account) { create(:account) }
  let!(:agent_a) { create(:user, account: account, role: :agent) }
  let!(:agent_b) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:team) { create(:team, account: account) }
  let!(:other_team) { create(:team, account: account) }
  # A conversa tem TIME de proposito: o isolamento e escopado pelo time da conversa, e
  # conversa sem time nunca e isolada (Inbox#isolation_applies_to_team?).
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, team: team) }

  # presença de uma msg pública no meio garante que o filtro não a descarta nem quebra a ordenação
  let!(:public_msg) do # rubocop:disable RSpec/LetSetup
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

    # ESCOPO POR TIME: a flag liga a regra na caixa, a lista diz em QUAIS times ela vale.
    context 'when isolation is scoped to teams' do
      before { inbox.update!(agent_message_isolation: true) }

      it 'hides the colleague message when the team list is empty (retrocompat)' do
        inbox.update!(agent_message_isolation_team_ids: [])
        result = described_class.call([conversation], user: agent_a)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_a.id)
      end

      it 'hides the colleague message when the conversation team is in the list' do
        inbox.update!(agent_message_isolation_team_ids: [team.id])
        result = described_class.call([conversation], user: agent_a)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_a.id)
      end

      it 'previews the real last message when the conversation team is NOT in the list' do
        inbox.update!(agent_message_isolation_team_ids: [other_team.id])
        result = described_class.call([conversation], user: agent_a)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)
      end

      it 'previews the real last message for a conversation without a team' do
        inbox.update!(agent_message_isolation_team_ids: [team.id])
        conversation.update!(team: nil)
        result = described_class.call([conversation], user: agent_a)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)
      end

      it 'previews the real last message for an administrator whatever the list' do
        inbox.update!(agent_message_isolation_team_ids: [team.id])
        result = described_class.call([conversation], user: admin)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)
      end
    end
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

  # FILTRO POR TIME DA MENSAGEM (team_message_isolation) NA PREVIA.
  #
  # O SQL da previa filtrava por time INCONDICIONALMENTE — `c.team_id IS NULL OR
  # m.team_id IS NULL OR m.team_id = c.team_id` — sem olhar flag nenhuma. Uma mensagem com
  # team_id defasado (a conversa trocou de time e o UpdateMessagesTeamIdJob ainda nao
  # rodou) sumia da previa ate na caixa com o isolamento DESLIGADO, e a lista mostrava uma
  # mensagem antiga como se fosse a ultima. E o mesmo bug de `messages` vs `all_messages`
  # que derrubou em silencio o no de mensagem do flow, o CSAT e o NPS (ver o comentario em
  # conversations/message_window_service.rb) — aqui na previa da lista.
  describe 'last message preview with team_message_isolation' do
    # A ULTIMA mensagem da conversa, carimbada com o time ANTIGO. E ela que sumia.
    let!(:stale) do
      msg = create(:message, conversation: conversation, account: account, inbox: inbox,
                             message_type: :incoming, content: 'stale team')
      msg.update_column(:team_id, other_team.id) # rubocop:disable Rails/SkipsModelValidations
      msg
    end

    def preview_for(user)
      described_class.call([conversation.reload], user: user).last_non_activity_messages[conversation.id]
    end

    # A PROVA DO BUG: flag DESLIGADA, previa tem que ser a mensagem real.
    it 'previews the stale-team message when the flag is OFF' do
      inbox.update!(team_message_isolation: false, team_message_isolation_team_ids: [team.id])
      expect(preview_for(agent_a).id).to eq(stale.id)
    end

    it 'previews the stale-team message when the flag is OFF even for an administrator' do
      inbox.update!(team_message_isolation: false)
      expect(preview_for(admin).id).to eq(stale.id)
    end

    it 'previews the stale-team message when the conversation team is NOT in the list' do
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [other_team.id])
      expect(preview_for(agent_a).id).to eq(stale.id)
    end

    it 'previews the stale-team message on a conversation without a team' do
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [])
      conversation.update!(team: nil)
      expect(preview_for(agent_a).id).to eq(stale.id)
    end

    # O outro lado: com a regra ALCANCANDO a conversa, a previa continua escondendo a
    # mensagem do time antigo — o comportamento que a flag existe para dar.
    it 'hides the stale-team message when the list is empty (retrocompat)' do
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [])
      expect(preview_for(agent_a).id).to eq(from_b.id)
    end

    it 'hides the stale-team message when the conversation team is in the list' do
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [team.id])
      expect(preview_for(agent_a).id).to eq(from_b.id)
    end

    # Mesma cláusula, mesmo bug, no contador de nao-lidas: as 2 incoming da conversa sao
    # `public_msg` (time atual) e `stale` (time antigo). `agent_last_seen_at` vai a nil de
    # proposito — a factory carimba Time.current e o teste nao pode depender de ordem de
    # microssegundo entre a conversa e as mensagens.
    it 'counts the stale-team incoming message as unread when the flag is OFF' do
      inbox.update!(team_message_isolation: false)
      conversation.update!(agent_last_seen_at: nil)
      result = described_class.call([conversation.reload], user: agent_a)
      expect(result.unread_counts[conversation.id]).to eq(2)
    end

    it 'skips the stale-team incoming message in the unread count when the rule applies' do
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [team.id])
      conversation.update!(agent_last_seen_at: nil)
      result = described_class.call([conversation.reload], user: agent_a)
      expect(result.unread_counts[conversation.id]).to eq(1)
    end
  end

  # A prévia carrega a MESMA cláusula de time que vive na association conversation.messages,
  # então a exceção do isolamento por time precisa valer aqui também.
  describe 'last message preview with team_message_isolation, exemption axis' do
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
