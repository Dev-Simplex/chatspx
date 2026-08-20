require 'rails_helper'

# Blocos 5.05 (`event_id` nasce no backend e volta ao widget) e 5.16 (`track()` do site).
#
# Os dois moram no MESMO endpoint de proposito. O `POST /api/v1/widget/events` ja era a unica
# porta por onde um fato do navegador entra com a sessao do widget autenticada; abrir uma segunda
# duplicaria autenticacao, throttle e a lista de nomes aceitos — e duplicar lista de nomes aceitos
# e como um dos dois lados fica permissivo sem ninguem perceber.
RSpec.describe '/api/v1/widget/events — tracking (5.05 + 5.16)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:payload) { { source_id: contact_inbox.source_id, inbox_id: inbox.id } }
  let(:token) { Widget::TokenService.new(payload: payload).generate_token }

  # UUID v4 — a versao esta no digito 13 e a variante no 17. Verificar a FORMA e nao so
  # "veio uma string" e o que separa `event_id` de um `""` devolvido por engano.
  let(:uuid_v4) { /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/ }

  def post_event(params)
    post '/api/v1/widget/events',
         params: { website_token: web_widget.website_token }.merge(params),
         headers: { 'X-Auth-Token' => token },
         as: :json
  end

  before { token }

  # ── 5.05 ────────────────────────────────────────────────────────────────────────────────
  describe 'o event_id volta ao widget' do
    it 'responde 200 com o event_id do registro, e nao mais 204 sem corpo' do
      post_event(name: 'webwidget.triggered')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['event_id']).to match(uuid_v4)

      registro = TrackingEvent.find_by(event_id: response.parsed_body['event_id'])
      expect(registro.name).to eq('chatspx_widget_opened')
      expect(registro.account_id).to eq(account.id)
      expect(registro.inbox_id).to eq(inbox.id)
      expect(registro.contact_id).to eq(contact.id)
      expect(registro.source).to eq('widget')
    end

    # A armadilha herdada do 5.03, e ela e consumida — nao contornada. A trava e o indice unico
    # (account_id, name, dedup_key); o que este exemplo prova e que a `dedup_key` deriva do FATO
    # e nao do relogio, senao o reenvio cairia noutro segundo e criaria um segundo registro com
    # um segundo event_id — que nenhum indice de (evento, destino) pegaria, porque para o banco
    # seriam eventos diferentes.
    it 'o reenvio do mesmo fato devolve o MESMO event_id e nao cria segundo registro' do
      post_event(name: 'webwidget.triggered')
      primeiro = response.parsed_body['event_id']

      travel_to(2.minutes.from_now) { post_event(name: 'webwidget.triggered') }
      segundo = response.parsed_body['event_id']

      expect(segundo).to eq(primeiro)
      expect(TrackingEvent.where(name: 'chatspx_widget_opened', account_id: account.id).count).to eq(1)
    end

    it 'visitantes diferentes na mesma conta nao colidem' do
      post_event(name: 'webwidget.triggered')
      primeiro = response.parsed_body['event_id']

      outro_contact = create(:contact, account: account)
      outro_inbox = create(:contact_inbox, contact: outro_contact, inbox: inbox)
      outro_token = Widget::TokenService.new(payload: { source_id: outro_inbox.source_id, inbox_id: inbox.id })
                                        .generate_token
      post '/api/v1/widget/events',
           params: { website_token: web_widget.website_token, name: 'webwidget.triggered' },
           headers: { 'X-Auth-Token' => outro_token },
           as: :json

      expect(response.parsed_body['event_id']).not_to eq(primeiro)
      expect(TrackingEvent.where(name: 'chatspx_widget_opened', account_id: account.id).count).to eq(2)
    end

    # `chatwoot:campaign-shown` esta declarado com `tracking: null` no contrato (§2 e
    # SDK_EVENT_CONTRACT). Inventar um `chatspx_campaign_shown` aqui seria criar vocabulario que
    # o documento nega. A chave sai presente e nula: ausencia declarada, nao omissao.
    it 'campaign.triggered responde 200 com event_id nulo e nao registra nada' do
      expect { post_event(name: 'campaign.triggered') }.not_to change(TrackingEvent, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key('event_id')
      expect(response.parsed_body['event_id']).to be_nil
    end

    it 'o barramento continua recebendo os dois nomes antigos — o pushEvent nao muda' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post_event(name: 'webwidget.triggered')
      post_event(name: 'campaign.triggered')

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with('webwidget.triggered', anything, hash_including(contact_inbox: contact_inbox))
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with('campaign.triggered', anything, anything)
    end
  end

  # ── 5.16 ────────────────────────────────────────────────────────────────────────────────
  describe 'track(name, properties) do site' do
    it 'grava o evento tipado do cliente com source `site` e devolve o event_id' do
      post_event(name: 'chatspx_orcamento_pedido',
                 properties: { plano: 'pro', valor: 199 },
                 event_key: 'k-1')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['event_id']).to match(uuid_v4)
      expect(response.parsed_body['name']).to eq('chatspx_orcamento_pedido')

      registro = TrackingEvent.find_by(event_id: response.parsed_body['event_id'])
      expect(registro).to have_attributes(source: 'site', account_id: account.id,
                                          inbox_id: inbox.id, contact_id: contact.id)
      expect(registro.properties).to eq('plano' => 'pro', 'valor' => 199)
    end

    # O nome do site NAO pode ir ao barramento. E a licao que ja custou caro neste mesmo arquivo:
    # nome livre virava publish para todos os listeners e queimava 3 tentativas da fila `critical`.
    it 'nao despacha o nome do site para o barramento de eventos' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post_event(name: 'chatspx_orcamento_pedido', event_key: 'k-1')

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
    end

    it 'o event_key e a chave de idempotencia: mesma chave, um registro; chave nova, dois' do
      post_event(name: 'chatspx_orcamento_pedido', event_key: 'k-1')
      primeiro = response.parsed_body['event_id']

      travel_to(1.hour.from_now) { post_event(name: 'chatspx_orcamento_pedido', event_key: 'k-1') }
      expect(response.parsed_body['event_id']).to eq(primeiro)

      post_event(name: 'chatspx_orcamento_pedido', event_key: 'k-2')
      expect(response.parsed_body['event_id']).not_to eq(primeiro)

      expect(TrackingEvent.where(name: 'chatspx_orcamento_pedido').count).to eq(2)
    end

    it 'recusa nome sem o prefixo do contrato, nomeando a regra' do
      expect { post_event(name: 'orcamento_pedido', event_key: 'k-1') }.not_to change(TrackingEvent, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('chatspx_')
    end

    it 'recusa nome acima dos 40 caracteres do GA4' do
      expect { post_event(name: "chatspx_#{'a' * 40}", event_key: 'k-1') }.not_to change(TrackingEvent, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('40')
    end

    it 'recusa PII crua em properties, nomeando a chave' do
      expect do
        post_event(name: 'chatspx_orcamento_pedido', properties: { email: 'ana@exemplo.com' }, event_key: 'k-1')
      end.not_to change(TrackingEvent, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('email')
    end

    it 'recusa PII crua ANINHADA em properties' do
      expect do
        post_event(name: 'chatspx_orcamento_pedido', properties: { cliente: { phone_number: '+5511' } },
                   event_key: 'k-1')
      end.not_to change(TrackingEvent, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'sem event_key o fato ainda entra, e o mesmo nome no mesmo segundo nao vira dois' do
      post_event(name: 'chatspx_orcamento_pedido')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['event_id']).to match(uuid_v4)
    end
  end
end
