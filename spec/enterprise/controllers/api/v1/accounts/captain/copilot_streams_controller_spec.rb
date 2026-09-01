require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::CopilotStreams', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: agent, assistant: assistant) }
  let(:chunks) { ['Bom ', 'dia, ', 'agente!'] }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/copilot_threads/#{copilot_thread.id}/stream" }
  let(:lock_key) { format(Api::V1::Accounts::Captain::CopilotStreamsController::LOCK_KEY_FORMAT, thread_id: copilot_thread.id) }

  before { create(:integrations_hook, :openai, account: account, settings: { api_key: 'test-account-key' }) }

  after { Redis::Alfred.delete(lock_key) }

  describe 'POST /stream' do
    describe 'sem autenticacao' do
      it 'devolve 401' do
        post url, params: { message: 'oi' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe 'thread de outro agente' do
      it 'devolve 404' do
        post url, params: { message: 'oi' }, headers: other_agent.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end

    describe 'conta sem chave de IA configurada' do
      let(:account_without_key) { create(:account) }
      let(:agent_without_key) { create(:user, account: account_without_key, role: :agent) }
      let(:thread_without_key) do
        create(:captain_copilot_thread, account: account_without_key, user: agent_without_key,
                                        assistant: create(:captain_assistant, account: account_without_key))
      end

      it 'devolve 422 com codigo estavel antes de abrir o stream' do
        post "/api/v1/accounts/#{account_without_key.id}/captain/copilot_threads/#{thread_without_key.id}/stream",
             params: { message: 'oi' }, headers: agent_without_key.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['code']).to eq('captain_api_key_missing')
      end
    end

    describe 'sem pergunta pendente' do
      it 'devolve 422 nothing_to_generate' do
        post url, params: {}, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['code']).to eq('nothing_to_generate')
      end
    end

    describe 'thread ja gerando' do
      before { Redis::Alfred.set(lock_key, Time.now.to_f.to_s, nx: true, ex: 60) }

      it 'devolve 409 busy com Retry-After' do
        post url, params: { message: 'oi' }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body['code']).to eq('busy')
        expect(response.headers['Retry-After']).to eq('2')
      end
    end

    describe 'cota de respostas esgotada' do
      before { account.update!(limits: { Enterprise::Account::PlanUsageAndLimits::CAPTAIN_RESPONSES => 0 }) }

      it 'devolve 429 quota_exceeded' do
        post url, params: { message: 'oi' }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body['code']).to eq('quota_exceeded')
      end
    end

    describe 'caminho feliz' do
      before { stub_copilot_llm(chunks: chunks, account: account) }

      it 'responde com text/event-stream sem buffering' do
        post url, params: { message: 'Resume a conversa' }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(response.headers['Content-Type']).to include('text/event-stream')
        expect(response.headers['X-Accel-Buffering']).to eq('no')
        expect(response.headers['Cache-Control']).to include('no-store')
      end

      it 'emite start, tokens e done com a mensagem ja persistida' do
        post url, params: { message: 'Resume a conversa' }, headers: agent.create_new_auth_token

        expect(sse_events(response.body).map(&:first)).to eq(%w[start token token token done])
        expect(sse_deltas(response.body)).to eq(chunks)

        persisted = copilot_thread.copilot_messages.assistant.first
        expect(persisted.message['content']).to eq('Bom dia, agente!')
        expect(sse_events(response.body).last.last).to eq({ 'message_id' => persisted.id, 'finish_reason' => 'stop' })
      end

      it 'libera o lock da thread ao terminar' do
        post url, params: { message: 'Resume a conversa' }, headers: agent.create_new_auth_token

        expect(Redis::Alfred.exists?(lock_key)).to be(false)
      end
    end

    describe 'chave da OpenAI revogada (401)' do
      before do
        stub_copilot_llm(error: RubyLLM::UnauthorizedError.new(nil, 'Incorrect API key provided: sk-proj-abcdef123456'),
                         account: account)
      end

      it 'devolve 200 e reporta o erro dentro do stream, sem vazar a chave' do
        post url, params: { message: 'Resume a conversa' }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(sse_events(response.body).map(&:first)).to eq(%w[start error done])
        expect(sse_events(response.body)[1].last['code']).to eq('unauthorized')
        expect(sse_events(response.body).last.last['finish_reason']).to eq('error')
        expect(response.body).not_to include('sk-proj')
      end
    end
  end

  describe 'DELETE /stream (botao parar)' do
    after { Copilot::StreamCancellation.new(copilot_thread.id).clear! }

    it 'marca o cancelamento da thread e responde 204' do
      delete url, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:no_content)
      expect(Copilot::StreamCancellation.new(copilot_thread.id).requested?).to be(true)
    end

    it 'nao deixa um agente parar a thread de outro' do
      delete url, headers: other_agent.create_new_auth_token

      expect(response).to have_http_status(:not_found)
      expect(Copilot::StreamCancellation.new(copilot_thread.id).requested?).to be(false)
    end

    it 'nao herda cancelamento antigo na proxima geracao' do
      stub_copilot_llm(chunks: chunks, account: account)
      delete url, headers: agent.create_new_auth_token

      post url, params: { message: 'Resume a conversa' }, headers: agent.create_new_auth_token

      expect(sse_events(response.body).map(&:first)).to eq(%w[start token token token done])
      expect(sse_events(response.body).last.last['finish_reason']).to eq('stop')
    end
  end

  describe 'POST /stream pelo alias do contrato (sem /captain)' do
    before { stub_copilot_llm(chunks: chunks, account: account) }

    it 'atende no mesmo controller' do
      post "/api/v1/accounts/#{account.id}/copilot_threads/#{copilot_thread.id}/stream",
           params: { message: 'Resume a conversa' }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(sse_events(response.body).map(&:first)).to eq(%w[start token token token done])
    end
  end
end
