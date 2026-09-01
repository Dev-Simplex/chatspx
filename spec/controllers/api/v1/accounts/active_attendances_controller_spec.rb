require 'rails_helper'

RSpec.describe 'Active Attendances API', type: :request do
  let(:account) { create(:account) }
  # pending_status_enabled: a Conversation valida status pending contra a inbox
  # (conversation.rb:347) — sem isso o factory levanta RecordInvalid.
  let(:inbox) { create(:inbox, account: account, pending_status_enabled: true) }

  describe 'GET /api/v1/accounts/{account.id}/active_attendances' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/active_attendances"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    # A abertura desta aba é DENTRO da conta (D2) — a fronteira entre contas
    # continua fechada, e é a única que o gate de privacidade aqui precisa manter.
    context 'when the user belongs to another account' do
      it 'does not leak attendances across accounts' do
        other_account = create(:account)
        outsider = create(:user, account: other_account, role: :administrator)
        create(:conversation, account: account, inbox: inbox, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances", headers: outsider.create_new_auth_token, as: :json

        expect(response).not_to have_http_status(:success)
        expect(response.body).not_to include('payload')
      end
    end

    context 'when it is an authenticated agent' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:owner) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, user: agent, inbox: inbox)
        # "Solicitar" é uma superfície da Fase 3 — a capacidade can_request só é
        # oferecida com o modo de pedido ligado. O grosso dos testes assume o modo
        # ON; um teste dedicado cobre o degradê com o modo OFF.
        account.update!(takeover_request_gate: true)
      end

      it 'returns conversations in service and omits resolved ones' do
        open_conversation = create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)
        pending_conversation = create(:conversation, account: account, inbox: inbox, assignee: owner, status: :pending)
        snoozed_conversation = create(:conversation, account: account, inbox: inbox, assignee: owner, status: :snoozed)
        create(:conversation, account: account, inbox: inbox, assignee: owner, status: :resolved)

        get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['meta']['count']).to eq(3)
        expect(body['payload'].pluck('id')).to contain_exactly(
          open_conversation.display_id, pending_conversation.display_id, snoozed_conversation.display_id
        )
      end

      # D2 — "atendimento geral": o agente PRECISA enxergar que outro time já
      # atende o contato; é essa cegueira que causa o atendimento duplicado.
      # Esta spec trava contra alguém "consertar" o controller com o
      # Conversations::PermissionFilterService, que devolveria lista incompleta.
      it 'shows attendances owned by a team the requesting agent does not belong to' do
        other_team = create(:team, account: account)
        other_inbox = create(:inbox, account: account)
        conversation = create(:conversation, account: account, inbox: other_inbox, team: other_team, assignee: owner, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['payload'].pluck('id')).to include(conversation.display_id)
        expect(body['payload'].first['team']).to include('id' => other_team.id, 'name' => other_team.name)
      end

      # O requisito do dono: a aba não mostra NENHUM trecho de conversa. Blinda
      # contra reuso acidental do _conversation.json.jbuilder, que emite
      # json.messages [last_message.push_event_data].
      it 'never exposes message content' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)
        create(:message, account: account, inbox: inbox, conversation: conversation, content: 'segredo do cliente')

        get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

        payload = response.parsed_body['payload'].first
        expect(payload).not_to have_key('messages')
        expect(payload).not_to have_key('unread_count')
        expect(response.body).not_to include('segredo do cliente')
      end

      it 'exposes contact, inbox, status and timestamps as metadata only' do
        contact = create(:contact, account: account, name: 'Fulano', phone_number: '+5511999999999', email: 'fulano@example.com')
        create(:conversation, account: account, inbox: inbox, contact: contact, assignee: owner, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

        payload = response.parsed_body['payload'].first
        expect(payload['contact']).to include('id' => contact.id, 'name' => 'Fulano', 'phone_number' => '+5511999999999')
        expect(payload['inbox']).to include('id' => inbox.id, 'name' => inbox.name, 'channel_type' => inbox.channel_type)
        expect(payload['status']).to eq('open')
        expect(payload['created_at']).to be_present
      end

      context 'with assignee variants' do
        it 'serializes a human assignee' do
          create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

          expect(response.parsed_body['payload'].first['assignee']).to include(
            'id' => owner.id, 'name' => owner.name, 'type' => 'user'
          )
        end

        it 'serializes a captain mirror assignee as agent_bot' do
          assistant = create(:captain_assistant, account: account)
          mirror = assistant.mirror_agent_bot
          conversation = create(:conversation, account: account, inbox: inbox, status: :open)
          conversation.update!(assignee_agent_bot: mirror)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

          expect(response.parsed_body['payload'].first['assignee']).to include(
            'id' => mirror.id, 'name' => mirror.name, 'type' => 'agent_bot', 'is_captain' => true
          )
        end

        it 'omits the assignee when the conversation has no owner' do
          create(:conversation, account: account, inbox: inbox, assignee: nil, status: :open)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

          expect(response.parsed_body['payload'].first).not_to have_key('assignee')
        end

        it 'omits the team when the conversation has none' do
          create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json

          expect(response.parsed_body['payload'].first).not_to have_key('team')
        end
      end

      # can_request espelha a autorização do endpoint de pedido: o botão
      # "Solicitar" no front SÓ aparece quando true, senão prometeria uma ação
      # que o backend recusa com 403 (foi o bug que o usuário viu).
      describe 'can_request' do
        def can_request_for(conversation)
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json
          response.parsed_body['payload'].find { |p| p['id'] == conversation.display_id }['can_request']
        end

        it 'is true for a human-owned conversation with no team when I am an inbox member' do
          conv = create(:conversation, account: account, inbox: inbox, assignee: owner, team: nil, status: :open)
          expect(can_request_for(conv)).to be(true)
        end

        it 'is false for a conversation whose team I am not part of' do
          other_team = create(:team, account: account)
          # o dono precisa ser do time, senão o ensure_assignee_is_from_team
          # (assignment_handler.rb:49) zera o assignee e o teste mediria "sem dono".
          create(:team_member, user: owner, team: other_team)
          conv = create(:conversation, account: account, inbox: inbox, assignee: owner, team: other_team, status: :open)
          expect(conv.reload.assignee_id).to eq(owner.id)
          expect(can_request_for(conv)).to be(false)
        end

        it 'is true when I belong to the conversation team' do
          team = create(:team, account: account)
          create(:team_member, user: agent, team: team)
          create(:team_member, user: owner, team: team) # dono é do time (senão vira sem-dono)
          conv = create(:conversation, account: account, inbox: inbox, assignee: owner, team: team, status: :open)
          expect(conv.reload.assignee_id).to eq(owner.id)
          expect(can_request_for(conv)).to be(true)
        end

        it 'is false for my own conversation' do
          conv = create(:conversation, account: account, inbox: inbox, assignee: agent, team: nil, status: :open)
          expect(can_request_for(conv)).to be(false)
        end

        it 'is false for an unassigned conversation' do
          conv = create(:conversation, account: account, inbox: inbox, assignee: nil, team: nil, status: :open)
          expect(can_request_for(conv)).to be(false)
        end

        it 'is false for an AI-owned conversation' do
          assistant = create(:captain_assistant, account: account)
          conv = create(:conversation, account: account, inbox: inbox, assignee: nil, team: nil, status: :open)
          conv.update!(assignee_agent_bot: assistant.mirror_agent_bot)
          expect(can_request_for(conv)).to be(false)
        end

        it 'is false for an inbox I am not a member of (even with a human owner)' do
          other_inbox = create(:inbox, account: account)
          conv = create(:conversation, account: account, inbox: other_inbox, assignee: owner, team: nil, status: :open)
          expect(can_request_for(conv)).to be(false)
        end

        it 'is always false for an admin (admins assign directly)' do
          admin = create(:user, account: account, role: :administrator)
          conv = create(:conversation, account: account, inbox: inbox, assignee: owner, team: nil, status: :open)
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: admin.create_new_auth_token, as: :json
          row = response.parsed_body['payload'].find { |p| p['id'] == conv.display_id }
          expect(row['can_request']).to be(false)
        end

        # Fase 3 desligada: a aba não oferece "Solicitar" — a linha degrada para
        # "Abrir" (consistente com o compose e a página de contato, que checam a flag).
        it 'is false when the takeover request mode is off, degrading to open' do
          account.update!(takeover_request_gate: false)
          conv = create(:conversation, account: account, inbox: inbox, assignee: owner, team: nil, status: :open)
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json
          row = response.parsed_body['payload'].find { |p| p['id'] == conv.display_id }
          expect(row['can_request']).to be(false)
          expect(row['can_open']).to be(true)
        end
      end

      # A aba deixou de ser um mural: cada linha oferece UMA ação, e ela precisa
      # bater com o que o backend autoriza de verdade.
      describe 'can_open / can_assume' do
        def row_for(conversation, user: agent)
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: user.create_new_auth_token, as: :json
          response.parsed_body['payload'].find { |p| p['id'] == conversation.display_id }
        end

        it 'lets me open and assume an unassigned conversation in my inbox' do
          conv = create(:conversation, account: account, inbox: inbox, assignee: nil, team: nil, status: :open)
          row = row_for(conv)
          expect(row['can_open']).to be(true)
          expect(row['can_assume']).to be(true)
        end

        # Assumir de uma IA é legítimo: o AssignmentService troca o bot pelo humano.
        it 'lets me assume an AI-owned conversation' do
          assistant = create(:captain_assistant, account: account)
          conv = create(:conversation, account: account, inbox: inbox, assignee: nil, team: nil, status: :open)
          conv.update!(assignee_agent_bot: assistant.mirror_agent_bot)
          expect(row_for(conv)['can_assume']).to be(true)
        end

        it 'lets me open my own conversation but not assume it again' do
          conv = create(:conversation, account: account, inbox: inbox, assignee: agent, team: nil, status: :open)
          row = row_for(conv)
          expect(row['can_open']).to be(true)
          expect(row['can_assume']).to be(false)
        end

        # Conversa de colega: abro (mesmo time/caixa) mas NÃO assumo — tenho que pedir.
        it 'lets me open a colleague conversation but not assume it' do
          conv = create(:conversation, account: account, inbox: inbox, assignee: owner, team: nil, status: :open)
          row = row_for(conv)
          expect(row['can_open']).to be(true)
          expect(row['can_assume']).to be(false)
          expect(row['can_request']).to be(true)
        end

        # A linha "muda": time do qual não participo — nada de abrir/assumir/pedir.
        it 'blocks everything for a conversation of a team I am not part of' do
          other_team = create(:team, account: account)
          create(:team_member, user: owner, team: other_team)
          conv = create(:conversation, account: account, inbox: inbox, assignee: owner, team: other_team, status: :open)
          row = row_for(conv)
          expect(row['can_open']).to be(false)
          expect(row['can_assume']).to be(false)
          expect(row['can_request']).to be(false)
        end

        it 'lets an admin open and assume a colleague conversation (force)' do
          admin = create(:user, account: account, role: :administrator)
          conv = create(:conversation, account: account, inbox: inbox, assignee: owner, team: nil, status: :open)
          row = row_for(conv, user: admin)
          expect(row['can_open']).to be(true)
          expect(row['can_assume']).to be(true)
        end
      end

      # Inbox isolado: colega não ABRE, mas ainda PODE pedir (o decouple
      # reachable? vs can_open?). A aba continua listando tudo (awareness).
      describe 'agent_conversation_isolation' do
        # A conversa tem TIME: o isolamento e escopado pelo time da conversa
        # (Inbox#isolation_applies_to_team?), e `reachable?` tambem exige o time.
        # `allow_auto_assign: false` para o AssignmentHandler nao inventar um assignee
        # no caso "sem dono" — e para nao zerar o dono de quem nao e do time.
        let(:iso_team) { create(:team, account: account, allow_auto_assign: false) }
        let(:other_team) { create(:team, account: account, allow_auto_assign: false) }

        def iso_row_for(conversation, user: agent)
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: user.create_new_auth_token, as: :json
          response.parsed_body['payload'].find { |p| p['id'] == conversation.display_id }
        end

        def colleague_conversation(team: iso_team)
          create(:conversation, account: account, inbox: inbox, assignee: owner, team: team, status: :open)
        end

        before do
          inbox.update!(agent_conversation_isolation: true)
          [agent, owner].each do |user|
            create(:team_member, team: iso_team, user: user)
            create(:team_member, team: other_team, user: user)
          end
        end

        it 'vetoes opening a colleague conversation but still offers request (gate on)' do
          row = iso_row_for(colleague_conversation)
          expect(row['can_open']).to be(false)
          expect(row['can_assume']).to be(false)
          expect(row['can_request']).to be(true)
        end

        it 'degrades to blocked (no open, no request) for a colleague when the gate is off' do
          account.update!(takeover_request_gate: false)
          row = iso_row_for(colleague_conversation)
          expect(row['can_open']).to be(false)
          expect(row['can_request']).to be(false)
        end

        it 'still lets me open my own and assume the unowned queue' do
          mine = create(:conversation, account: account, inbox: inbox, assignee: agent, team: iso_team, status: :open)
          unowned = create(:conversation, account: account, inbox: inbox, assignee: nil, team: iso_team, status: :open)
          expect(iso_row_for(mine)['can_open']).to be(true)
          expect(iso_row_for(unowned)['can_assume']).to be(true)
        end

        it 'still lists the colleague attendance (awareness intact)' do
          expect(iso_row_for(colleague_conversation)).to be_present
        end

        # ESCOPO POR TIME: a flag liga a regra na caixa, a lista diz em QUAIS times ela vale.
        # Aqui o erro tem cara de botao que mente: ou oferece "Abrir" e o clique da 403,
        # ou esconde "Abrir" de uma conversa que a pessoa PODE abrir.
        it 'vetoes opening when the team list is empty (retrocompat)' do
          inbox.update!(agent_conversation_isolation_team_ids: [])
          expect(iso_row_for(colleague_conversation)['can_open']).to be(false)
        end

        it 'vetoes opening when the conversation team is in the scope list' do
          inbox.update!(agent_conversation_isolation_team_ids: [iso_team.id])
          expect(iso_row_for(colleague_conversation)['can_open']).to be(false)
        end

        it 'allows opening when the conversation team is NOT in the scope list' do
          inbox.update!(agent_conversation_isolation_team_ids: [other_team.id])
          expect(iso_row_for(colleague_conversation)['can_open']).to be(true)
        end

        it 'keeps the administrator able to open whatever the scope list' do
          inbox.update!(agent_conversation_isolation_team_ids: [iso_team.id])
          admin = create(:user, account: account, role: :administrator)
          expect(iso_row_for(colleague_conversation, user: admin)['can_open']).to be(true)
        end

        # CONVERSA SEM TIME (antes da triagem): esta regra NAO e isenta do time nulo (fica
        # fora de Inbox::TEAMLESS_EXEMPT_RULES), entao a aba continua NAO oferecendo
        # "Abrir" na conversa do colega — o botao tem que dizer a verdade que o guard
        # aplica (senao o clique leva a um 403). `reachable?` cai no inbox quando nao ha
        # time, entao "Solicitar" continua de pe.
        it 'STILL vetoes opening a colleague conversation that has no team yet' do
          conv = colleague_conversation(team: nil)
          expect(conv.reload.team_id).to be_nil
          row = iso_row_for(conv)
          expect(row['can_open']).to be(false)
          expect(row['can_request']).to be(true)
        end
      end

      describe 'my_pending_request_id' do
        it 'exposes my own pending request so the row can offer cancelling it' do
          conv = create(:conversation, account: account, inbox: inbox, assignee: owner, team: nil, status: :open)
          request = create(:conversation_takeover_request, account: account, conversation: conv,
                                                           requester: agent, owner: owner, status: :pending)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json
          row = response.parsed_body['payload'].find { |p| p['id'] == conv.display_id }
          expect(row['my_pending_request_id']).to eq(request.id)
        end

        it 'is null when the pending request is from SOMEONE ELSE' do
          conv = create(:conversation, account: account, inbox: inbox, assignee: agent, team: nil, status: :open)
          create(:conversation_takeover_request, account: account, conversation: conv,
                                                 requester: owner, owner: agent, status: :pending)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json
          row = response.parsed_body['payload'].find { |p| p['id'] == conv.display_id }
          expect(row['my_pending_request_id']).to be_nil
        end
      end

      # O sintoma que a feature existe p/ matar: o MESMO contato em 2 atendimentos.
      describe 'duplicated' do
        it 'flags every row of a contact that has two open attendances' do
          contact = create(:contact, account: account)
          first = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: owner, status: :open)
          second = create(:conversation, account: account, inbox: create(:inbox, account: account),
                                         contact: contact, assignee: owner, status: :open)
          alone = create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)

          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json
          rows = response.parsed_body['payload'].index_by { |p| p['id'] }
          expect(rows[first.display_id]['duplicated']).to be(true)
          expect(rows[second.display_id]['duplicated']).to be(true)
          expect(rows[alone.display_id]['duplicated']).to be(false)
        end
      end

      # NOTA: os GETs com parâmetro vão pela QUERY STRING de propósito. `get ...,
      # params: {...}, as: :json` faz o Rails reescrever a request como POST com
      # corpo JSON (+ X-Http-Method-Override), preservando Integer — ou seja,
      # testaria um formato que nenhum cliente real manda (o axios manda "2").
      #
      # A Fase 2 usa este filtro como FONTE DE VERDADE do aviso — nunca o
      # contactConversations, que devolve vazio p/ agente de outro time.
      it 'filters by contact_id' do
        contact = create(:contact, account: account)
        mine = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: owner, status: :open)
        create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances?contact_id=#{contact.id}",
            headers: agent.create_new_auth_token

        body = response.parsed_body
        expect(body['meta']['count']).to eq(1)
        expect(body['payload'].first['id']).to eq(mine.display_id)
      end

      it 'paginates with a stable order' do
        create_list(:conversation, 17, account: account, inbox: inbox, assignee: owner, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances?page=2", headers: agent.create_new_auth_token

        body = response.parsed_body
        expect(body['meta']['count']).to eq(17)
        # Integer mesmo vindo da query string (onde page é a String "2"), senão o
        # front compara tipo trocado ao decidir a página atual.
        expect(body['meta']['current_page']).to eq(2)
        expect(body['meta']['per_page']).to eq(15)
        expect(body['payload'].length).to eq(2)
      end

      it 'falls back to page 1 when the page param is garbage' do
        create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open)

        get "/api/v1/accounts/#{account.id}/active_attendances?page=abc", headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['meta']['current_page']).to eq(1)
        expect(response.parsed_body['payload'].length).to eq(1)
      end

      it 'does not issue more queries as more attendances are listed' do
        create(:conversation, account: account, inbox: inbox, team: create(:team, account: account),
                              assignee: create(:user, account: account, role: :agent), status: :open)
        baseline = count_queries do
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json
        end

        4.times do
          create(:conversation, account: account, inbox: create(:inbox, account: account),
                                team: create(:team, account: account),
                                assignee: create(:user, account: account, role: :agent), status: :open)
        end
        scaled = count_queries do
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token, as: :json
        end

        expect(response.parsed_body['payload'].length).to eq(5)
        expect(scaled).to eq(baseline)
      end

      # O teste acima só cobre assignee HUMANO, e o jbuilder curto-circuita no
      # `assignee.present?` — o branch do espelho captain (bot.avatar_url) nunca
      # era exercitado. Sem o preload do avatar do bot isto cresce +1 query por
      # bot distinto.
      it 'does not issue more queries as more captain-owned attendances are listed' do
        bots = Array.new(3) { create(:captain_assistant, account: account).mirror_agent_bot }

        create(:conversation, account: account, inbox: inbox, status: :open).update!(assignee_agent_bot: bots.first)
        baseline = count_queries do
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token
        end

        bots.each do |bot|
          2.times do
            create(:conversation, account: account, inbox: inbox, status: :open).update!(assignee_agent_bot: bot)
          end
        end
        scaled = count_queries do
          get "/api/v1/accounts/#{account.id}/active_attendances", headers: agent.create_new_auth_token
        end

        expect(response.parsed_body['payload'].length).to eq(7)
        expect(response.parsed_body['payload'].first['assignee']).to include('type' => 'agent_bot')
        expect(scaled).to eq(baseline)
      end
    end
  end

  def count_queries(&)
    count = 0
    counter = lambda { |_name, _started, _finished, _id, payload|
      count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] || payload[:sql].match?(/^\s*(BEGIN|COMMIT|RELEASE|SAVEPOINT|ROLLBACK)/i)
    }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end
end
