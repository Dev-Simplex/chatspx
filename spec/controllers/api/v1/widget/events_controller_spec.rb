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
