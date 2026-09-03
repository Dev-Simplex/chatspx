require 'rails_helper'

# 6.02 — o conjunto de casos é do cliente: ele cria, edita e apaga.
RSpec.describe 'Api::V1::Accounts::Captain::EvalCases', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/eval_cases" }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'POST' do
    let(:payload) do
      { eval_case: { titulo: 'diz o horário', mensagens: [{ role: 'user', content: 'que horas abre?' }],
                     expectativas: { contem: ['das 9h'] } } }
    end

    it 'creates the case' do
      post base_url, params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response[:data][:titulo]).to eq('diz o horário')
      expect(assistant.eval_cases.count).to eq(1)
    end

    it 'refuses an expectation nobody can judge, saying which' do
      post base_url, params: { eval_case: { titulo: 'x', mensagens: [{ role: 'user', content: 'oi' }],
                                            expectativas: { seja_simpatico: true } } },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('seja_simpatico')
    end

    it 'refuses a case with no visitor turn' do
      post base_url, params: { eval_case: { titulo: 'x', mensagens: [] } },
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses an agent' do
      post base_url, params: payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET' do
    it 'lists in the declared order' do
      create(:captain_eval_case, captain_assistant: assistant, account: account, titulo: 'segundo', posicao: 2)
      create(:captain_eval_case, captain_assistant: assistant, account: account, titulo: 'primeiro', posicao: 1)

      get base_url, headers: admin.create_new_auth_token, as: :json

      expect(json_response[:data].map { |c| c[:titulo] }).to eq(%w[primeiro segundo])
    end

    it 'does not leak cases of another assistant' do
      outro = create(:captain_assistant, account: account)
      create(:captain_eval_case, captain_assistant: outro, account: account)

      get base_url, headers: admin.create_new_auth_token, as: :json

      expect(json_response[:data]).to be_empty
    end
  end

  describe 'PATCH e DELETE' do
    let!(:eval_case) { create(:captain_eval_case, captain_assistant: assistant, account: account) }

    it 'updates' do
      patch "#{base_url}/#{eval_case.id}", params: { eval_case: { titulo: 'outro nome' } },
                                           headers: admin.create_new_auth_token, as: :json

      expect(json_response[:data][:titulo]).to eq('outro nome')
    end

    it 'destroys' do
      expect do
        delete "#{base_url}/#{eval_case.id}", headers: admin.create_new_auth_token, as: :json
      end.to change(Captain::EvalCase, :count).by(-1)
    end
  end
end
