require 'rails_helper'

# Vetores de ouro das três assinaturas do nível 2, os mesmos do captador-v2
# (docs/contrato-chatspx-vetores.md e internal/chatspx/assinatura_test.go). Se um lado mudar a
# fórmula, este spec quebra antes de chegar em produção. Não ajuste os valores para passar.
RSpec.describe 'Contrato Captador ↔ ChatSPX: vetores de ouro', type: :request do
  include CaptadorSigningHelpers

  let(:timestamp) { 1_790_000_000 }
  let(:lead_id) { '0199aaaa-0000-7000-8000-000000000001' }
  let(:account) { create(:account) }
  let!(:hook) { captador_hook_for(account, shared_secret: 'segredo-compartilhado-de-teste-32-caracteres-ou-mais') }

  around { |example| travel_to(Time.zone.at(1_790_000_000)) { example.run } }

  describe 'Captador → ChatSPX (Spx::Captador::BaseController)' do
    # Literal, sem to_json: a ordem das chaves e o "á" em UTF-8 (dois bytes) fazem parte do vetor.
    let(:corpo_leads) do
      '{"lead":{"id":"0199aaaa-0000-7000-8000-000000000001","nome":"Padaria X Ltda","telefone":"+5565999998888"},' \
        '"acting_user_id":42,"inbox_id":91,"assignee_id":42,"preview":"Olá!"}'
    end
    let(:assinatura_leads) { 'sha256=6fdd0299d443f299afd9e97f4366c11046b85cf0521366f7d24e292d53db514b' }
    let(:assinatura_catalogo) { 'sha256=a700ecaa2bd86b743c6586676385d8a612cd183e17ac8cee0af0c1c489cdab72' }

    def assinado(assinatura)
      { 'X-Captador-Account' => account.id.to_s, 'X-Captador-Timestamp' => timestamp.to_s, 'X-Captador-Signature' => assinatura }
    end

    def post_leads(corpo, assinatura)
      post '/spx/captador/v1/leads', params: corpo, headers: assinado(assinatura).merge('CONTENT_TYPE' => 'application/json')
    end

    it 'aceita o POST leads do vetor (passa da assinatura e cai na regra de negócio)' do
      post_leads(corpo_leads, assinatura_leads)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error_code']).to eq('idempotency_key_required')
    end

    it 'aceita o GET catalogo do vetor' do
      get '/spx/captador/v1/catalogo', headers: assinado(assinatura_catalogo)

      expect(response).to have_http_status(:ok)
    end

    it 'recusa com um byte trocado no corpo ou na assinatura' do
      post_leads(corpo_leads.sub('Olá!', 'Olá?'), assinatura_leads)
      expect(response).to have_http_status(:unauthorized)

      post_leads(corpo_leads, assinatura_leads.sub(/b\z/, 'c'))
      expect(response).to have_http_status(:unauthorized)

      get '/spx/captador/v1/catalogo', headers: assinado(assinatura_catalogo.sub(/2\z/, '3'))
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'ChatSPX → Captador, painel (Spx::Captador::Client)' do
    let(:client) { Spx::Captador::Client.new(hook, instance_double(User, id: 42)) }
    let(:cabecalhos) { { 'X-Captador-Instancia' => 'inst-1', 'X-Chatspx-Usuario' => '42', 'X-Captador-Timestamp' => timestamp.to_s } }

    it 'assina o GET leads com a query em ordem alfabética' do
      stub = stub_request(:get, 'https://captador.test/integracao/chatspx/v1/leads?contact_id=5012&conversation_id=1234')
             .with(headers: cabecalhos.merge(
               'X-Captador-Assinatura' => 'sha256=a4f3c9098bbd5309516f50747e7da46a6969fb2d33d9acc75a32d64be5d59811'
             ))
             .to_return(status: 200, body: '{"lead":null}')

      expect(client.lead(conversation_id: 1234, contact_id: 5012).status).to eq(200)
      expect(stub).to have_been_requested
    end

    it 'assina o POST mover' do
      stub = stub_request(:post, "https://captador.test/integracao/chatspx/v1/leads/#{lead_id}/mover")
             .with(body: '{"etapa_id":3}', headers: cabecalhos.merge(
               'X-Captador-Assinatura' => 'sha256=4b6edfc053d88c6d213dd44f2a0f1a7a75d5b78942dbd99a164047eec7b237a8'
             ))
             .to_return(status: 200, body: '{"lead":null}')

      expect(client.move(lead_id, 3).status).to eq(200)
      expect(stub).to have_been_requested
    end
  end

  describe 'ChatSPX → Captador, eventos (Webhooks::Trigger com o segredo do hook)' do
    it 'assina "<ts>.<corpo>", sem método nem caminho' do
      url = 'https://captador.test/webhooks/chatspx/inst-1'
      stub = stub_request(:post, url)
             .with(body: '{"event":"message_created","id":99881}', headers: {
                     'X-Chatwoot-Delivery' => 'entrega-1',
                     'X-Chatwoot-Timestamp' => timestamp.to_s,
                     'X-Chatwoot-Signature' => 'sha256=63760e545467138ef344010c05ccadb22910b9b277df7bf285c42150ef756e36'
                   })
             .to_return(status: 200)

      Webhooks::Trigger.execute(url, { event: 'message_created', id: 99_881 }, :account_webhook,
                                secret: hook.settings['shared_secret'], delivery_id: 'entrega-1')

      expect(stub).to have_been_requested
    end
  end
end
