# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public Funnel Forms API (Kanban v2 / Fase 8)', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account) }
  let(:inbox) { channel.inbox }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let!(:open_stage) { FunnelStage.create!(funnel: funnel, name: 'Novo', position: 0, automation_type: 'open') }
  let!(:field) { funnel.funnel_custom_fields.create!(key: 'motivo', label: 'Motivo', field_type: 'text') }
  let(:token) { 'tok-abc-123' }

  before do
    funnel.update!(settings: { 'form_enabled' => true, 'form_token' => token, 'form_inbox_id' => inbox.id })
  end

  describe 'GET show' do
    it 'returns the public form config' do
      get "/public/api/v1/funnel_forms/#{token}"

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['title']).to eq('Vendas')
      expect(response.parsed_body['fields'].map { |f| f['key'] }).to include('motivo')
    end

    it 'returns 404 for an unknown token' do
      get '/public/api/v1/funnel_forms/nope'
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when the form is disabled' do
      funnel.update!(settings: funnel.settings.merge('form_enabled' => false))
      get "/public/api/v1/funnel_forms/#{token}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST create' do
    it 'creates a contact + conversation + card in the first stage' do
      expect do
        post "/public/api/v1/funnel_forms/#{token}",
             params: { name: 'Maria', email: 'maria@example.com', message: 'Quero um orçamento' }, as: :json
      end.to change { funnel.funnel_items.count }.by(1)

      expect(response).to have_http_status(:created)
      item = funnel.funnel_items.last
      expect(item.funnel_stage_id).to eq(open_stage.id)
      expect(item.conversation.contact.name).to eq('Maria')
      expect(item.conversation.messages.where(message_type: :incoming).first.content).to eq('Quero um orçamento')
    end

    it 'applies only this funnel\'s custom fields, ignoring foreign keys' do
      post "/public/api/v1/funnel_forms/#{token}",
           params: { name: 'João', custom_fields: { motivo: 'Dúvida', evil: 'x' } }, as: :json

      expect(response).to have_http_status(:created)
      conversation = funnel.funnel_items.last.conversation
      expect(conversation.custom_attributes["funnel_#{funnel.id}_motivo"]).to eq('Dúvida')
      expect(conversation.custom_attributes).not_to have_key('evil')
    end

    it 'rejects submission to a disabled form' do
      funnel.update!(settings: funnel.settings.merge('form_enabled' => false))
      post "/public/api/v1/funnel_forms/#{token}", params: { name: 'X' }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'rejects an unknown token' do
      post '/public/api/v1/funnel_forms/nope', params: { name: 'X' }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
