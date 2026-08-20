require 'rails_helper'

RSpec.describe 'Agents API', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:admin) { create(:user, custom_attributes: { test: 'test' }, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, email: 'exists@example.com', role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/agents' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/agents"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let!(:agent) { create(:user, account: account, role: :agent) }

      it 'returns all agents of account' do
        get "/api/v1/accounts/#{account.id}/agents",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(response.parsed_body.size).to eq(account.users.count)
      end

      it 'returns custom fields on agents if present' do
        agent.update(custom_attributes: { test: 'test' })

        get "/api/v1/accounts/#{account.id}/agents",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        data = response.parsed_body
        expect(data.first['custom_attributes']['test']).to eq('test')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/agents/:id' do
    let(:other_agent) { create(:user, account: account, role: :agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'returns unauthorized for agents' do
        delete "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'deletes the agent and user object if associated with only one account' do
        expect(account.users).to include(other_agent)

        perform_enqueued_jobs(only: DeleteObjectJob) do
          delete "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
                 headers: admin.create_new_auth_token,
                 as: :json
        end

        expect(response).to have_http_status(:success)
        expect(account.reload.users).not_to include(other_agent)
      end

      it 'deletes only the agent object when user is associated with multiple accounts' do
        other_account = create(:account)
        create(:account_user, account_id: other_account.id, user_id: other_agent.id)

        perform_enqueued_jobs(only: DeleteObjectJob) do
          delete "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
                 headers: admin.create_new_auth_token,
                 as: :json
        end

        expect(response).to have_http_status(:success)
        expect(account.reload.users).not_to include(other_agent)
        expect(other_agent.account_users.count).to eq(1) # Should only be associated with other_account now
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/agents/:id' do
    let(:other_agent) { create(:user, account: account, role: :agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      params = { name: 'TestUser' }

      it 'returns unauthorized for agents' do
        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'modifies an agent name' do
        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: params,
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(other_agent.reload.name).to eq(params[:name])
      end

      it 'modifies an agents account user attributes' do
        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { role: 'administrator', availability: 'busy', auto_offline: false },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data['role']).to eq('administrator')
        expect(response_data['availability_status']).to eq('busy')
        expect(response_data['auto_offline']).to be(false)
        expect(other_agent.account_users.first.role).to eq('administrator')
      end
    end

    context 'when marking the agent as a team supervisor' do
      let!(:team) { create(:team, account: account) }
      let!(:other_team) { create(:team, account: account) }

      it 'lets an administrator mark the supervised teams' do
        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { supervised_team_ids: [team.id] },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['supervised_team_ids']).to eq([team.id])
        expect(other_agent.reload.supervised_teams).to contain_exactly(team)
      end

      it 'replaces the whole set (add + remove no mesmo request)' do
        create(:team_supervisor, team: team, user: other_agent)

        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { supervised_team_ids: [other_team.id] },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(other_agent.reload.supervised_teams).to contain_exactly(other_team)
      end

      it 'clears the supervision with an empty array' do
        create(:team_supervisor, team: team, user: other_agent)

        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { supervised_team_ids: [] },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(other_agent.reload.supervised_teams).to be_empty
      end

      it 'keeps the supervision untouched when the key is absent' do
        create(:team_supervisor, team: team, user: other_agent)

        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { name: 'TestUser' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(other_agent.reload.supervised_teams).to contain_exactly(team)
      end

      it 'ignores team ids from another account' do
        foreign_team = create(:team, account: create(:account))

        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { supervised_team_ids: [team.id, foreign_team.id] },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(other_agent.reload.supervised_teams).to contain_exactly(team)
      end

      # D7: senão um agente se autopromove a supervisor
      it 'returns unauthorized for an agent' do
        put "/api/v1/accounts/#{account.id}/agents/#{agent.id}",
            params: { supervised_team_ids: [team.id] },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(agent.reload.supervised_teams).to be_empty
      end
    end
  end

  # T1: o supervisor de time gerencia os agentes dos times que supervisiona — edita só o
  # nome deles. Todo o resto (função, disponibilidade, exclusão, supervisão) continua
  # sendo de admin.
  # T4: o `index` NÃO recorta nada — ele alimenta a store `agents` do dashboard inteiro
  # (menções, participantes, Kanban, filtro de responsável), e recortá-lo sumia com
  # gente em telas que nada têm a ver com supervisão. Quem mostra só "os agentes dos
  # meus times" é a TELA de Agentes, filtrando no cliente.
  describe 'quando quem chama é supervisor de time' do
    let!(:team) { create(:team, account: account) }
    let!(:other_team) { create(:team, account: account) }
    let!(:supervisor) { create(:user, account: account, role: :agent) }
    let!(:team_agent) { create(:user, account: account, role: :agent) }
    let!(:outsider) { create(:user, account: account, role: :agent) }

    before do
      create(:team_member, team: team, user: team_agent)
      create(:team_member, team: other_team, user: outsider)
      create(:team_supervisor, team: team, user: supervisor)
    end

    describe 'GET /api/v1/accounts/{account.id}/agents' do
      it 'keeps the whole account for the supervisor (a lista alimenta o app inteiro)' do
        get "/api/v1/accounts/#{account.id}/agents",
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.size).to eq(account.users.count)
      end

      it 'keeps the whole account for a supervisor whose team has no members' do
        empty_team = create(:team, account: account)
        lonely = create(:user, account: account, role: :agent)
        create(:team_supervisor, team: empty_team, user: lonely)

        get "/api/v1/accounts/#{account.id}/agents",
            headers: lonely.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.size).to eq(account.users.count)
      end

      it 'exposes team_ids so the screen can do the supervised filtering' do
        get "/api/v1/accounts/#{account.id}/agents",
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        listed = response.parsed_body.find { |payload| payload['id'] == team_agent.id }
        expect(listed['team_ids']).to contain_exactly(team.id)
      end

      it 'keeps the whole account for an administrator that also supervises a team' do
        create(:team_supervisor, team: team, user: admin)

        get "/api/v1/accounts/#{account.id}/agents",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.size).to eq(account.users.count)
      end

      it 'keeps the whole account for an agent that supervises nothing (comportamento atual)' do
        get "/api/v1/accounts/#{account.id}/agents",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.size).to eq(account.users.count)
      end
    end

    describe 'PUT /api/v1/accounts/{account.id}/agents/:id' do
      it 'renames an agent of a supervised team' do
        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { name: 'Renomeado' },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(team_agent.reload.name).to eq('Renomeado')
      end

      it 'refuses an agent outside the supervised teams' do
        put "/api/v1/accounts/#{account.id}/agents/#{outsider.id}",
            params: { name: 'Renomeado' },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(outsider.reload.name).not_to eq('Renomeado')
      end

      it 'refuses an administrator even when he is a member of the supervised team' do
        create(:team_member, team: team, user: admin)

        put "/api/v1/accounts/#{account.id}/agents/#{admin.id}",
            params: { name: 'Renomeado' },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(admin.reload.name).not_to eq('Renomeado')
      end

      it 'refuses a role change (escalada de privilégio)' do
        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { name: 'Renomeado', role: 'administrator' },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(team_agent.reload.name).not_to eq('Renomeado')
        expect(team_agent.account_users.first.role).to eq('agent')
      end

      it 'refuses an availability change' do
        availability_before = team_agent.account_users.first.availability

        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { availability: 'busy' },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(team_agent.account_users.first.reload.availability).to eq(availability_before)
      end

      it 'refuses a custom_role_id change' do
        custom_role = create(:custom_role, account: account)

        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { name: 'Renomeado', custom_role_id: custom_role.id },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(team_agent.account_users.first.custom_role_id).to be_nil
      end

      it 'keeps the custom role of the agent when only the name changes' do
        custom_role = create(:custom_role, account: account)
        team_agent.account_users.first.update!(custom_role_id: custom_role.id)

        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { name: 'Renomeado' },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(team_agent.account_users.first.reload.custom_role_id).to eq(custom_role.id)
      end

      it 'refuses to change the supervision of anybody (autopromoção)' do
        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { supervised_team_ids: [other_team.id] },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(team_agent.reload.supervised_teams).to be_empty
      end

      it 'refuses to widen his own supervision' do
        put "/api/v1/accounts/#{account.id}/agents/#{supervisor.id}",
            params: { supervised_team_ids: [team.id, other_team.id] },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(supervisor.reload.supervised_teams).to contain_exactly(team)
      end

      # T4: as variantes de FORMATO do request. A guarda lê `params[:agent]`, e é o
      # ParamsWrapper que monta esse hash — ele só embrulha o CORPO, e só quando a
      # chave `agent` ainda não veio. Cada forma abaixo monta `params` de um jeito
      # diferente, então cada uma precisa de prova própria.
      it 'refuses a role change sent inside an explicit agent wrapper' do
        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { agent: { name: 'Renomeado', role: 'administrator' } },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(team_agent.account_users.first.reload.role).to eq('agent')
      end

      it 'refuses a role change sent form-encoded (sem ParamsWrapper)' do
        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { agent: { name: 'Renomeado', role: 'administrator' } },
            headers: supervisor.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
        expect(team_agent.account_users.first.reload.role).to eq('agent')
      end

      # a query string NÃO entra no wrapper, então a guarda de chaves não a vê — o que
      # segura aqui é `agent_params` ler só de `params[:agent]`. Vale a prova.
      it 'does not escalate with the role on the query string' do
        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}?role=administrator",
            params: { name: 'Renomeado' },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(team_agent.account_users.first.reload.role).to eq('agent')
      end

      it 'does not escalate with custom_role_id on the query string' do
        custom_role = create(:custom_role, account: account)

        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}?custom_role_id=#{custom_role.id}",
            params: { name: 'Renomeado' },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(team_agent.account_users.first.reload.custom_role_id).to be_nil
      end

      it 'refuses auto_offline and email just like role' do
        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { name: 'Renomeado', auto_offline: false, email: 'novo@example.com' },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(team_agent.reload.email).not_to eq('novo@example.com')
      end

      it 'does not wipe the supervision of the agent it renames' do
        create(:team_supervisor, team: other_team, user: team_agent)

        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { name: 'Renomeado' },
            headers: supervisor.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(team_agent.reload.supervised_teams).to contain_exactly(other_team)
      end

      it 'gives no power in this account to somebody supervising a team of ANOTHER account' do
        other_account = create(:account)
        foreigner = create(:user, account: account, role: :agent)
        create(:account_user, user: foreigner, account: other_account, role: :agent)
        create(:team_supervisor, team: create(:team, account: other_account), user: foreigner)

        put "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
            params: { name: 'Renomeado' },
            headers: foreigner.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'keeps the administrator powers of an admin that also supervises' do
        create(:team_supervisor, team: team, user: admin)

        put "/api/v1/accounts/#{account.id}/agents/#{outsider.id}",
            params: { name: 'Renomeado', role: 'administrator' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(outsider.account_users.first.reload.role).to eq('administrator')
      end
    end

    describe 'DELETE /api/v1/accounts/{account.id}/agents/:id' do
      it 'stays administrator only' do
        delete "/api/v1/accounts/#{account.id}/agents/#{team_agent.id}",
               headers: supervisor.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(account.users).to include(team_agent)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/agents' do
    let(:other_agent) { create(:user, account: account, role: :agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/agents"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      params = { name: 'NewUser', email: Faker::Internet.email, role: :agent }

      it 'returns unauthorized for agents' do
        post "/api/v1/accounts/#{account.id}/agents",
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates a new agent' do
        post "/api/v1/accounts/#{account.id}/agents",
             params: params,
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(response.parsed_body['email']).to eq(params[:email])
        expect(account.users.last.name).to eq('NewUser')
      end

      context 'when the account email limit is exhausted' do
        before do
          allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
          account.update!(limits: { 'emails' => 0 })
        end

        it 'does not create an agent' do
          expect do
            post "/api/v1/accounts/#{account.id}/agents", params: params, headers: admin.create_new_auth_token, as: :json
          end.not_to change(User, :count)

          expect(response).to have_http_status(:too_many_requests)
          expect(response.parsed_body['error']).to eq('The daily email limit for this account has been reached')
        end
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/agents/bulk_create' do
    let(:emails) { ['test1@example.com', 'test2@example.com', 'test3@example.com'] }
    let(:bulk_create_params) { { emails: emails } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/agents/bulk_create", params: bulk_create_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as admin' do
      it 'creates multiple agents successfully' do
        expect do
          post "/api/v1/accounts/#{account.id}/agents/bulk_create", params: bulk_create_params, headers: admin.create_new_auth_token
        end.to change(User, :count).by(3)

        expect(response).to have_http_status(:ok)
      end

      it 'ignores errors if account_user already exists' do
        params = { emails: ['exists@example.com', 'test1@example.com', 'test2@example.com'] }

        expect do
          post "/api/v1/accounts/#{account.id}/agents/bulk_create", params: params,
                                                                    headers: admin.create_new_auth_token
        end.to change(User, :count).by(2)

        expect(response).to have_http_status(:ok)
      end

      context 'when the account email limit is exhausted' do
        before do
          allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
          account.update!(limits: { 'emails' => 0 })
        end

        it 'does not create new agents' do
          expect do
            post "/api/v1/accounts/#{account.id}/agents/bulk_create", params: bulk_create_params, headers: admin.create_new_auth_token
          end.not_to change(User, :count)

          expect(response).to have_http_status(:too_many_requests)
          expect(response.parsed_body['error']).to eq('The daily email limit for this account has been reached')
        end

        it 'adds existing users and continues processing after a rejected invitation' do
          first_existing_user = create(:user, email: 'first-existing@example.com')
          second_existing_user = create(:user, email: 'second-existing@example.com')
          params = {
            emails: [
              first_existing_user.email,
              'rejected-invitation@example.com',
              second_existing_user.email
            ]
          }

          expect do
            post "/api/v1/accounts/#{account.id}/agents/bulk_create", params: params, headers: admin.create_new_auth_token
          end.not_to change(User, :count)

          expect(response).to have_http_status(:too_many_requests)
          expect(account.reload.users).to include(first_existing_user, second_existing_user)
          expect(User.from_email('rejected-invitation@example.com')).to be_nil
          expect(account.emails_sent_today).to eq(0)
        end

        it 'keeps the onboarding step when an invitation is rejected' do
          account.update!(custom_attributes: { onboarding_step: 'completed' })

          post "/api/v1/accounts/#{account.id}/agents/bulk_create", params: bulk_create_params, headers: admin.create_new_auth_token

          expect(response).to have_http_status(:too_many_requests)
          expect(account.reload.custom_attributes['onboarding_step']).to eq('completed')
        end
      end

      context 'when the account has capacity for only part of the batch' do
        before do
          allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
          account.update!(limits: { 'emails' => 1 })
        end

        it 'persists the successful invitation without leaking email capacity' do
          expect do
            post "/api/v1/accounts/#{account.id}/agents/bulk_create", params: bulk_create_params, headers: admin.create_new_auth_token
          end.to change(User, :count).by(1)

          expect(response).to have_http_status(:too_many_requests)
          expect(User.from_email(emails.first)).to be_present
          expect(User.from_email(emails.second)).to be_nil
          expect(User.from_email(emails.third)).to be_nil
          expect(account.emails_sent_today).to eq(1)
        end
      end
    end
  end
end
