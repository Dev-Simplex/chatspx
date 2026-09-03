require 'rails_helper'

# 6.02 — a API que a tela usa. O disparo NÃO roda IA aqui: ele enfileira o job, e o
# exemplo prova que enfileirou (o job não é executado neste teste).
RSpec.describe 'Api::V1::Accounts::Captain::EvalRuns', type: :request do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}" }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET eval_runs/estimate' do
    before { create_list(:captain_eval_case, 2, captain_assistant: assistant, account: account) }

    it 'answers the cost BEFORE anything runs' do
      expect do
        get "#{base_url}/eval_runs/estimate", headers: admin.create_new_auth_token, as: :json
      end.not_to change(Captain::EvalRun, :count)

      expect(response).to have_http_status(:success)
      expect(json_response[:data][:casos]).to eq(2)
      expect(json_response[:data][:respostas]).to eq(2)
      expect(json_response[:data][:tokens_estimados]).to be > 0
    end

    it 'refuses an agent — conjunto de casos é configuração de conta' do
      get "#{base_url}/eval_runs/estimate", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an anonymous request' do
      get "#{base_url}/eval_runs/estimate", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST eval_runs' do
    before { create(:captain_eval_case, captain_assistant: assistant, account: account) }

    it 'creates a pending run and enqueues the work, without calling the model in the request' do
      expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)

      expect do
        post "#{base_url}/eval_runs", headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Captain::Eval::RunJob)

      expect(response).to have_http_status(:created)
      expect(json_response[:data][:status]).to eq('pendente')
      expect(json_response[:data][:dry_run]).to be(true)
    end

    it 'stores the estimate that was shown, so it can be checked later' do
      post "#{base_url}/eval_runs", headers: admin.create_new_auth_token, as: :json

      expect(json_response[:data][:custo_estimado][:casos]).to eq(1)
    end
  end

  describe 'GET eval_runs/compare' do
    it 'answers with the regressions between two runs' do
      eval_case = create(:captain_eval_case, captain_assistant: assistant, account: account, titulo: 'horário')
      antes = Captain::EvalRun.create!(account_id: account.id, captain_assistant_id: assistant.id,
                                       status: 'concluida', prompt_fingerprint: 'aaa', casos_total: 1, casos_ok: 1)
      depois = Captain::EvalRun.create!(account_id: account.id, captain_assistant_id: assistant.id,
                                        status: 'concluida', prompt_fingerprint: 'bbb', casos_total: 1, casos_falha: 1)
      Captain::EvalCaseResult.create!(account_id: account.id, eval_run_id: antes.id, eval_case_id: eval_case.id,
                                      passou: true)
      Captain::EvalCaseResult.create!(account_id: account.id, eval_run_id: depois.id, eval_case_id: eval_case.id,
                                      passou: false)

      get "#{base_url}/eval_runs/compare", params: { base_id: antes.id, comparada_id: depois.id },
                                           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response[:data][:regrediram].first[:titulo]).to eq('horário')
      expect(json_response[:data][:mesmo_prompt]).to be(false)
    end
  end

  describe 'GET eval_runs' do
    it 'lists the history, newest first' do
      antiga = Captain::EvalRun.create!(account_id: account.id, captain_assistant_id: assistant.id,
                                        status: 'concluida', created_at: 2.days.ago)
      nova = Captain::EvalRun.create!(account_id: account.id, captain_assistant_id: assistant.id, status: 'concluida')

      get "#{base_url}/eval_runs", headers: admin.create_new_auth_token, as: :json

      expect(json_response[:data].map { |r| r[:id] }).to eq([nova.id, antiga.id])
    end

    it 'does not leak runs of another account' do
      outra = create(:account)
      outro_assistant = create(:captain_assistant, account: outra)
      Captain::EvalRun.create!(account_id: outra.id, captain_assistant_id: outro_assistant.id, status: 'concluida')

      get "#{base_url}/eval_runs", headers: admin.create_new_auth_token, as: :json

      expect(json_response[:data]).to be_empty
    end
  end
end
