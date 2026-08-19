require 'rails_helper'

describe ConversationFinder do
  subject(:conversation_finder) { described_class.new(user_1, params) }

  let!(:account) { create(:account) }
  let!(:user_1) { create(:user, account: account) }
  let!(:user_2) { create(:user, account: account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let!(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: 'testing_source_id') }
  let!(:restricted_inbox) { create(:inbox, account: account) }

  before do
    create(:inbox_member, user: user_1, inbox: inbox)
    create(:inbox_member, user: user_2, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, assignee: user_1)
    create(:conversation, account: account, inbox: inbox, assignee: user_1)
    create(:conversation, account: account, inbox: inbox, assignee: user_1, status: 'resolved')
    create(:conversation, account: account, inbox: inbox, assignee: user_2, contact_inbox: contact_inbox)
    # unassigned conversation
    create(:conversation, account: account, inbox: inbox)
    Current.account = account
  end

  describe '#perform' do
    context 'with status' do
      let(:params) { { status: 'open', assignee_type: 'me' } }

      it 'filter conversations by status' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 2
      end
    end

    context 'with inbox' do
      let!(:restricted_conversation) { create(:conversation, account: account, inbox_id: restricted_inbox.id) }

      it 'returns conversation from any inbox if its admin' do
        params = { inbox_id: restricted_inbox.id }
        result = described_class.new(admin, params).perform

        expect(result[:conversations].map(&:id)).to include(restricted_conversation.id)
      end

      it 'returns conversation from inbox if agent is its member' do
        params = { inbox_id: restricted_inbox.id }
        create(:inbox_member, user: user_1, inbox: restricted_inbox)
        result = described_class.new(user_1, params).perform

        expect(result[:conversations].map(&:id)).to include(restricted_conversation.id)
      end

      it 'does not return conversations from inboxes where agent is not a member' do
        params = { inbox_id: restricted_inbox.id }
        result = described_class.new(user_1, params).perform

        expect(result[:conversations].map(&:id)).not_to include(restricted_conversation.id)
      end

      it 'returns only the conversations from the inbox if inbox_id filter is passed' do
        conversation = create(:conversation, account: account, inbox_id: inbox.id)
        params = { inbox_id: restricted_inbox.id }
        result = described_class.new(admin, params).perform

        conversation_ids = result[:conversations].map(&:id)
        expect(conversation_ids).not_to include(conversation.id)
        expect(conversation_ids).to include(restricted_conversation.id)
      end
    end

    context 'with assignee_type all' do
      let(:params) { { assignee_type: 'all' } }

      it 'filter conversations by assignee type all' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 4
      end
    end

    context 'with assignee_type unassigned' do
      let(:params) { { assignee_type: 'unassigned' } }

      it 'filter conversations by assignee type unassigned' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'with status all' do
      let(:params) { { status: 'all' } }

      it 'returns all conversations' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 5
      end
    end

    context 'with assignee_type assigned' do
      let(:params) { { assignee_type: 'assigned' } }

      it 'filter conversations by assignee type assigned' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 3
      end

      it 'returns the correct meta' do
        result = conversation_finder.perform
        expect(result[:count]).to include(
          mine_count: 2,
          assigned_count: 3,
          unassigned_count: 1,
          all_count: 4
        )
      end
    end

    context 'with team' do
      let(:team) { create(:team, account: account) }
      let(:params) { { team_id: team.id } }

      it 'filter conversations by team' do
        create(:conversation, account: account, inbox: inbox, team: team)
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'with invalid team id' do
      let(:params) { { team_id: 'all' } }

      it 'ignores team filter and returns conversations' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 4
      end
    end

    context 'with labels' do
      let(:params) { { labels: ['resolved'] } }

      it 'filter conversations by labels' do
        conversation = inbox.conversations.first
        conversation.update_labels('resolved')

        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'with source_id' do
      let(:params) { { source_id: 'testing_source_id' } }

      it 'filter conversations by source id' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'without source' do
      let(:params) { {} }

      it 'returns conversations with any source' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 4
      end
    end

    context 'with updated_within' do
      let(:params) { { updated_within: 20, assignee_type: 'unassigned', sort_by: 'created_at_asc' } }

      it 'filters based on params, sort order but returns all conversations without pagination with in time range' do
        # value of updated_within is in seconds
        # write spec based on that
        conversations = create_list(:conversation, 50, account: account,
                                                       inbox: inbox, assignee: nil,
                                                       updated_at: Time.now.utc - 30.seconds,
                                                       created_at: Time.now.utc - 30.seconds)
        # update updated_at of 27 conversations to be with in 20 seconds
        conversations[0..27].each do |conversation|
          conversation.update(updated_at: Time.now.utc - 10.seconds)
        end
        result = conversation_finder.perform
        # pagination is not applied
        # filters are applied
        # modified conversations + 1 conversation created during set up
        expect(result[:conversations].length).to be 29
        # ensure that the conversations are sorted by created_at
        expect(result[:conversations].first.created_at).to be < result[:conversations].last.created_at
      end
    end

    context 'with pagination' do
      let(:params) { { status: 'open', assignee_type: 'me', page: 1 } }

      it 'returns paginated conversations' do
        create_list(:conversation, 50, account: account, inbox: inbox, assignee: user_1)
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 25
      end
    end

    context 'with perform_meta_only' do
      let(:params) { { assignee_type: 'assigned' } }

      it 'returns only count without conversations' do
        result = conversation_finder.perform_meta_only
        expect(result).to have_key(:count)
        expect(result).not_to have_key(:conversations)
      end

      it 'returns the correct counts' do
        result = conversation_finder.perform_meta_only
        expect(result[:count]).to eq({
                                       mine_count: 2,
                                       assigned_count: 3,
                                       unassigned_count: 1,
                                       all_count: 4
                                     })
      end

      it 'returns same counts as perform' do
        meta_result = conversation_finder.perform_meta_only
        full_result = conversation_finder.perform
        expect(meta_result[:count]).to eq(full_result[:count])
      end
    end

    context 'with captain (AI) assignee' do
      let(:assistant) { create(:captain_assistant, account: account) }
      let(:mirror) { assistant.mirror_agent_bot }
      let(:webhook_bot) { create(:agent_bot, account: account) }
      # baseline do before externo (open): 2 do user_1, 1 do user_2, 1 sem dono = 4
      let!(:ai_conversation) { create(:conversation, account: account, inbox: inbox, assignee_agent_bot: mirror) }
      let!(:webhook_bot_conversation) { create(:conversation, account: account, inbox: inbox, assignee_agent_bot: webhook_bot) }

      context 'with assignee_type ai and reply_assignment_gate enabled' do
        before { account.update!(reply_assignment_gate: true) }

        let(:params) { { assignee_type: 'ai' } }

        it 'returns only conversations assigned to a captain mirror (webhook bot does not count)' do
          result = conversation_finder.perform
          expect(result[:conversations].map(&:id)).to contain_exactly(ai_conversation.id)
        end

        it 'computes ai_count and excludes AI from unassigned_count' do
          result = conversation_finder.perform
          expect(result[:count]).to include(
            ai_count: 1,
            unassigned_count: 2, # sem dono do setup + bot webhook (não é IA)
            all_count: 6
          )
        end

        it 'derives assigned_count including the AI conversation (DC-4, frozen semantics)' do
          result = conversation_finder.perform
          expect(result[:count][:assigned_count]).to eq(4)
        end
      end

      context 'with assignee_type unassigned and reply_assignment_gate enabled' do
        before { account.update!(reply_assignment_gate: true) }

        let(:params) { { assignee_type: 'unassigned' } }

        it 'excludes AI conversations but keeps webhook-bot conversations' do
          result = conversation_finder.perform
          conversation_ids = result[:conversations].map(&:id)
          expect(conversation_ids).not_to include(ai_conversation.id)
          expect(conversation_ids).to include(webhook_bot_conversation.id)
          expect(result[:conversations].length).to be 2
        end
      end

      context 'with assignee_type unassigned and reply_assignment_gate disabled' do
        let(:params) { { assignee_type: 'unassigned' } }

        it 'keeps current behavior: AI conversation still counts as unassigned' do
          result = conversation_finder.perform
          expect(result[:conversations].map(&:id)).to include(ai_conversation.id, webhook_bot_conversation.id)
          expect(result[:conversations].length).to be 3
          expect(result[:count]).to include(unassigned_count: 3, assigned_count: 3)
        end

        it 'still computes and exposes ai_count' do
          result = conversation_finder.perform
          expect(result[:count]).to include(ai_count: 1)
        end
      end

      context 'with assignee_type ai and reply_assignment_gate disabled' do
        let(:params) { { assignee_type: 'ai' } }

        it 'still filters by captain mirror (filter is not gated, only the tab is)' do
          result = conversation_finder.perform
          expect(result[:conversations].map(&:id)).to contain_exactly(ai_conversation.id)
        end
      end

      context 'with perform_counts_only and reply_assignment_gate disabled' do
        let(:params) { {} }

        it 'includes ai_count in the counts hash' do
          result = conversation_finder.perform_counts_only
          expect(result[:count]).to include(ai_count: 1, unassigned_count: 3, all_count: 6)
        end
      end
    end

    context 'with unattended' do
      let(:params) { { status: 'open', assignee_type: 'me', conversation_type: 'unattended' } }

      it 'returns unattended conversations' do
        create(:conversation, account: account, first_reply_created_at: Time.now.utc, assignee: user_1) # attended_conversation
        create(:conversation, account: account, first_reply_created_at: nil, assignee: user_1) # unattended_conversation_no_first_reply
        create(:conversation, account: account, first_reply_created_at: Time.now.utc,
                              assignee: user_1, waiting_since: Time.now.utc) # unattended_conversation_waiting_since

        result = conversation_finder.perform
        expect(result[:conversations].length).to be 2
      end
    end

    # F2 — Escopo por time na aba "Aguardando atendimento" (fila) no modo reply_assignment_gate.
    # Agente não-admin só vê a fila dos seus times; admin vê tudo; modo clássico inalterado;
    # outras abas (all/me/ai) não são afetadas pelo escopo forçado.
    context 'with team-scoped queue (F2 fila por time)' do
      let!(:team_a) { create(:team, account: account) }
      let!(:team_b) { create(:team, account: account) }
      # 3 conversas sem dono (unassigned) em times distintos.
      let!(:queue_team_a) { create(:conversation, account: account, inbox: inbox, team: team_a) }
      let!(:queue_team_b) { create(:conversation, account: account, inbox: inbox, team: team_b) }
      let!(:queue_no_team) { create(:conversation, account: account, inbox: inbox, team: nil) }

      # user_1 é membro só do team_a; user_2 não pertence a nenhum time.
      before { create(:team_member, user: user_1, team: team_a) }

      # @is_admin lê Current.account_user; setá-lo para o admin nos cenários de admin.
      def as_admin
        Current.account_user = admin.account_users.find_by(account: account)
        yield
      ensure
        Current.account_user = nil
      end

      context 'when gate ON and a non-admin agent is on the unassigned tab' do
        let(:params) { { assignee_type: 'unassigned' } }

        before { account.update!(reply_assignment_gate: true) }

        it 'lists only unassigned conversations from the user teams' do
          result = conversation_finder.perform
          ids = result[:conversations].map(&:id)
          expect(ids).to include(queue_team_a.id)
          expect(ids).not_to include(queue_team_b.id)
          expect(ids).not_to include(queue_no_team.id)
        end

        it 'scopes the unassigned_count to the user teams' do
          result = conversation_finder.perform
          expect(result[:count][:unassigned_count]).to eq(1)
        end

        it 'ignores a team_id param pointing to a team the user does not belong to' do
          result = described_class.new(user_1, { assignee_type: 'unassigned', team_id: team_b.id }).perform
          expect(result[:conversations].map(&:id)).to contain_exactly(queue_team_a.id)
          expect(result[:count][:unassigned_count]).to eq(1)
        end

        it 'keeps the account-wide queue when the agent has no team' do
          # Decisão F2: agente sem nenhum time não fica trancado fora da fila; mantém o
          # comportamento atual (@team_ids vazio → short-circuit de filter_by_team).
          result = described_class.new(user_2, { assignee_type: 'unassigned' }).perform
          ids = result[:conversations].map(&:id)
          expect(ids).to include(queue_team_a.id, queue_team_b.id, queue_no_team.id)
        end
      end

      context 'when gate ON and an admin is on the unassigned tab' do
        before { account.update!(reply_assignment_gate: true) }

        it 'lists every unassigned conversation account-wide' do
          as_admin do
            result = described_class.new(admin, { assignee_type: 'unassigned' }).perform
            ids = result[:conversations].map(&:id)
            expect(ids).to include(queue_team_a.id, queue_team_b.id, queue_no_team.id)
          end
        end

        it 'counts unassigned account-wide' do
          as_admin do
            result = described_class.new(admin, { assignee_type: 'unassigned' }).perform
            # setup externo cria 1 unassigned sem time + as 3 desta fixture = 4
            expect(result[:count][:unassigned_count]).to eq(4)
          end
        end
      end

      # Badge do sidebar "Aguardando atendimento": o contador vem do endpoint
      # /conversations/meta (perform_counts_only), chamado SEM assignee_type.
      # Para o badge bater com a fila que o agente acessa, o unassigned_count do
      # /meta precisa ficar escopado aos times do agente não-admin (via auto-escopo
      # nativo do fork em set_team) e conta inteira para admin.
      context 'with perform_counts_only (sidebar badge / endpoint meta)' do
        before { account.update!(reply_assignment_gate: true) }

        it 'scopes unassigned_count to the user teams for a non-admin agent' do
          result = described_class.new(user_1, {}).perform_counts_only
          # user_1 pertence só ao team_a → conta apenas a fila do team_a.
          expect(result[:count][:unassigned_count]).to eq(1)
        end

        it 'matches the count the agent gets when opening the queue (list vs badge)' do
          badge = described_class.new(user_1, {}).perform_counts_only[:count][:unassigned_count]
          queue = described_class.new(user_1, { assignee_type: 'unassigned' }).perform[:count][:unassigned_count]
          expect(badge).to eq(queue)
        end

        it 'counts unassigned account-wide for an admin' do
          as_admin do
            result = described_class.new(admin, {}).perform_counts_only
            # setup externo cria 1 unassigned sem time + as 3 desta fixture = 4
            expect(result[:count][:unassigned_count]).to eq(4)
          end
        end

        it 'keeps the account-wide badge when the agent has no team' do
          result = described_class.new(user_2, {}).perform_counts_only
          # user_2 não pertence a nenhum time → sem escopo (espelha a fila que ele vê).
          badge = result[:count][:unassigned_count]
          queue = described_class.new(user_2, { assignee_type: 'unassigned' }).perform[:count][:unassigned_count]
          expect(badge).to eq(queue)
        end
      end

      context 'when gate ON and a non-admin agent is on another tab' do
        before { account.update!(reply_assignment_gate: true) }

        it 'does not force the queue scope on the "all" tab (keeps existing team auto-scope)' do
          # user_1 é membro do team_a → auto-escopo já existente do fork limita ao team_a.
          # O escopo forçado da fila não deve alterar essa semântica.
          result = described_class.new(user_1, { assignee_type: 'all', status: 'all' }).perform
          ids = result[:conversations].map(&:id)
          expect(ids).to include(queue_team_a.id)
          expect(ids).not_to include(queue_team_b.id)
        end
      end

      context 'when gate OFF (classic mode) and a non-admin agent is on the unassigned tab' do
        let(:params) { { assignee_type: 'unassigned' } }

        it 'keeps the existing fork team auto-scope (no forced queue scope)' do
          # Sem a flag, force_team_queue_scope? é false. user_1 (membro do team_a) cai no
          # auto-escopo existente do fork (@team_ids = teams do user), que já limita ao team_a.
          result = conversation_finder.perform
          ids = result[:conversations].map(&:id)
          expect(ids).to include(queue_team_a.id)
          expect(ids).not_to include(queue_team_b.id)
        end
      end

      context 'when gate OFF (classic mode) and an admin passes a team_id' do
        it 'honors the explicit team_id param (no forced override without the flag)' do
          as_admin do
            result = described_class.new(admin, { assignee_type: 'unassigned', team_id: team_b.id }).perform
            # Sem a flag, o param team_id é respeitado → filtra pelo team_b.
            expect(result[:conversations].map(&:id)).to contain_exactly(queue_team_b.id)
          end
        end
      end
    end
  end

  # Descoberta de conversa PELO CONTEÚDO da mensagem (o `q` da lista). É o quarto ponto
  # de leitura do isolamento por agente, e o que mais escapa.
  describe '#perform with q and agent_message_isolation' do
    let!(:iso_inbox) { create(:inbox, account: account, enable_auto_assignment: false, agent_message_isolation: true) }
    let!(:iso_conversation) { create(:conversation, account: account, inbox: iso_inbox) }
    let!(:params) { { q: 'palavra secreta' } }

    before do
      [user_1, user_2].each { |u| create(:inbox_member, user: u, inbox: iso_inbox) }
      create(:message, account: account, inbox: iso_inbox, conversation: iso_conversation,
                       message_type: :outgoing, sender: user_2, content: 'a palavra secreta do outro agente')
    end

    def found_ids_for(viewer)
      described_class.new(viewer, params).perform[:conversations].map(&:id)
    end

    # lista de exceções vazia = comportamento de hoje
    it 'does not surface the conversation to an agent who did not write it' do
      expect(found_ids_for(user_1)).not_to include(iso_conversation.id)
    end

    it 'surfaces it to the agent who wrote it' do
      expect(found_ids_for(user_2)).to include(iso_conversation.id)
    end

    it 'surfaces it to the exempt agent' do
      create(:inbox_isolation_exemption, inbox: iso_inbox, user: user_1, isolation_type: 'agent_message')

      expect(found_ids_for(user_1)).to include(iso_conversation.id)
    end

    it 'keeps hiding it from an agent who is not an exemption' do
      create(:inbox_isolation_exemption, inbox: iso_inbox, user: user_1, isolation_type: 'agent_message')
      outro = create(:user, account: account, role: :agent)
      create(:inbox_member, user: outro, inbox: iso_inbox)

      expect(found_ids_for(outro)).not_to include(iso_conversation.id)
    end

    it 'lets an administrator find it, as it always did' do
      expect(found_ids_for(admin)).to include(iso_conversation.id)
    end
  end
end
