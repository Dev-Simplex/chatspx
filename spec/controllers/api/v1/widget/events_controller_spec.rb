require 'rails_helper'

RSpec.describe '/api/v1/widget/events', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:payload) { { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id } }
  let(:token) { Widget::TokenService.new(payload: payload).generate_token }

  describe 'POST /api/v1/widget/events' do
    let(:params) { { website_token: web_widget.website_token, name: 'webwidget.triggered', event_info: { test_id: 'test' } } }

    context 'with invalid website token' do
      it 'returns unauthorized' do
        post '/api/v1/widget/events', params: { website_token: '' }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with correct website token' do
      before do
        allow(Rails.configuration.dispatcher).to receive(:dispatch)
      end

      it 'dispatches the webwidget event' do
        post '/api/v1/widget/events',
             params: params,
             headers: { 'X-Auth-Token' => token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(params[:name], anything, contact_inbox: contact_inbox,
                                         event_info: { test_id: 'test', browser_language: nil, widget_language: nil, browser: anything })
      end

      it 'dispatches the campaign event' do
        post '/api/v1/widget/events',
             params: params.merge(name: 'campaign.triggered'),
             headers: { 'X-Auth-Token' => token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with('campaign.triggered', anything, anything)
      end
    end

    # ── Bloco 5.05 — `event_id` nasce no backend e VOLTA ao widget ──────────────────────────
    #
    # A resposta era `204 No Content`. Virou `200` com corpo, e a mudanca e ADITIVA de proposito:
    # `widget/api/events.js` faz `API.post` e ignora o retorno, entao `2xx` com corpo e `2xx` sem
    # corpo sao indistinguiveis para o `pushEvent` que ja esta em producao.
    describe 'o event_id de volta (5.05)' do
      def post_event(name, event_info = { test_id: 'test' })
        post '/api/v1/widget/events',
             params: { website_token: web_widget.website_token, name: name, event_info: event_info },
             headers: { 'X-Auth-Token' => token },
             as: :json
      end

      it 'responde 200 com o UUID que o servidor gerou, e grava o fato' do
        expect { post_event('webwidget.triggered') }.to change(TrackingEvent, :count).by(1)

        expect(response).to have_http_status(:ok)
        event_id = response.parsed_body['event_id']
        expect(event_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
        expect(TrackingEvent.last.event_id).to eq(event_id)
      end

      it 'grava o evento #2 do contrato, com os parametros que ele declara' do
        post_event('webwidget.triggered', { referer: 'https://loja.exemplo.com.br/produto?email=ana@exemplo.com.br' })

        evento = TrackingEvent.last
        expect(evento.name).to eq('chatspx_widget_opened')
        expect(evento.source).to eq('widget')
        expect(evento.inbox_id).to eq(web_widget.inbox.id)
        expect(evento.contact_id).to eq(contact.id)
        expect(evento.properties['inbox_id']).to eq(web_widget.inbox.id)
        # PII escondida na QUERY: `TrackingEvent` recusa chave de PII, mas nao tem como recusar um
        # e-mail dentro de uma URL. Por isso `page_url` sai sem query string (RC5).
        expect(evento.properties['page_url']).to eq('https://loja.exemplo.com.br/produto')
        expect(evento.properties.to_json).not_to include('ana@exemplo.com.br')
      end

      # A ARMADILHA DO 5.03, CONSUMIDA E NAO CONTORNADA. O `EventDispatcherJob` e retentado, e o
      # widget reenvia `webwidget.triggered` a cada abertura da bolha. Sem chave natural, cada
      # reenvio criaria um evento novo com `event_id` novo — e o indice unico de (evento, destino)
      # nao tocaria em nenhum, porque para o banco seriam eventos diferentes.
      it 'abrir a bolha tres vezes e UM fato, com UM event_id' do
        expect do
          3.times { post_event('webwidget.triggered') }
        end.to change(TrackingEvent, :count).by(1)

        ids = TrackingEvent.where(name: 'chatspx_widget_opened').pluck(:event_id)
        expect(ids.uniq.size).to eq(1)
      end

      it 'campanha exibida NAO vira evento de tracking — a ausencia e declarada no contrato' do
        expect { post_event('campaign.triggered') }.not_to change(TrackingEvent, :count)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['event_id']).to be_nil
      end

      it 'registro que falha NAO derruba o endpoint' do
        allow(Tracking::EventRecorder).to receive(:record!).and_raise(StandardError, 'banco fora')

        post_event('webwidget.triggered')

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['event_id']).to be_nil
      end
    end

    # ── Bloco 5.16 — `track()`: o evento tipado do site ─────────────────────────────────────
    describe 'o evento do site (5.16)' do
      def post_track(name, properties = {})
        post '/api/v1/widget/events',
             params: { website_token: web_widget.website_token, name: name, event_info: properties },
             headers: { 'X-Auth-Token' => token },
             as: :json
      end

      before do
        # Materializa as factories ANTES do stub: elas disparam `account.created`/`contact.created`
        # de verdade, e sem isso o `not_to have_received(:dispatch)` mediria ruido de setup em vez
        # do endpoint. E a mesma precaucao do contexto de allowlist acima.
        token
        allow(Rails.configuration.dispatcher).to receive(:dispatch)
      end

      it 'grava o evento proprio do cliente e devolve o event_id' do
        expect { post_track('chatspx_orcamento_pedido', { valor: 990 }) }.to change(TrackingEvent, :count).by(1)

        expect(response).to have_http_status(:ok)
        evento = TrackingEvent.last
        expect(evento.name).to eq('chatspx_orcamento_pedido')
        expect(evento.source).to eq('site')
        expect(evento.properties).to eq({ 'valor' => 990 })
        expect(response.parsed_body['event_id']).to eq(evento.event_id)
      end

      # O nome do integrador NAO pode virar publish no barramento do Rails: e exatamente o buraco
      # que a lista fechada de nomes existe para tapar.
      it 'NAO publica no barramento interno' do
        post_track('chatspx_orcamento_pedido')

        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      end

      it 'recusa nome fora das tres regras do contrato, nomeando a regra' do
        post_track('chatspx_OrcamentoPedido')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('snake_case')
        expect(TrackingEvent.count).to eq(0)
      end

      it 'recusa PII crua em properties, nomeando a chave' do
        post_track('chatspx_orcamento_pedido', { email: 'ana@exemplo.com.br' })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('email')
        expect(response.parsed_body['error']).not_to include('ana@exemplo.com.br')
        expect(TrackingEvent.count).to eq(0)
      end

      it 'recusa nome acima do limite de 40 caracteres do GA4' do
        post_track("chatspx_#{'a' * 40}")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('40')
      end
    end

    # O nome ia direto do site do cliente para o barramento. Qualquer string
    # virava um publish para todos os listeners, e o EventDispatcherJob ainda
    # gastava 3 tentativas na fila `critical` com cada nome que explodisse.
    context 'with an event name outside the allowlist' do
      before do
        # Materializa account/web_widget/contact_inbox ANTES do stub: as
        # factories disparam account.created e contact.created de verdade, e sem
        # isso o `not_to have_received(:dispatch)` mediria ruido de setup em vez
        # do endpoint. Com o setup fora do caminho, a assercao pode ser a mais
        # forte que existe: nada foi despachado.
        token
        allow(Rails.configuration.dispatcher).to receive(:dispatch)
      end

      def post_event(name)
        post '/api/v1/widget/events',
             params: params.merge(name: name),
             headers: { 'X-Auth-Token' => token },
             as: :json
      end

      it 'returns 422 with a legible error and dispatches nothing' do
        post_event('conversation.resolved')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('name must be one of: webwidget.triggered, campaign.triggered')
        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      end

      it 'refuses every internal event name the visitor could reach for' do
        %w[message.created contact.deleted conversation.status_changed account.created
           conversation.typing_on funnel_item.moved].each do |name|
          post_event(name)
          expect(response).to have_http_status(:unprocessable_entity)
        end

        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      end

      it 'refuses a name that is not an event at all' do
        post_event('qualquer coisa que o script do site inventar')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      end

      it 'refuses a blank name' do
        post_event('')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      end
    end
  end
end
