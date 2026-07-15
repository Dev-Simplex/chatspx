# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Funnel Custom Fields API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas', team_id: team.id) }
  let(:base) { "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/custom_fields" }

  before { team.add_members([agent.id]) }

  describe 'unauthenticated' do
    it 'returns unauthorized' do
      get base
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    it 'creates a custom field definition' do
      post base,
           params: { custom_field: { key: 'deal_value', label: 'Valor', field_type: 'number', show_on_card: true } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('key' => 'deal_value', 'field_type' => 'number', 'show_on_card' => true)
      expect(response.parsed_body['attribute_key']).to eq("funnel_#{funnel.id}_deal_value")
      expect(funnel.funnel_custom_fields.count).to eq(1)
    end

    it 'stores dropdown choices in options' do
      post base,
           params: { custom_field: { key: 'size', label: 'Tamanho', field_type: 'dropdown', options: { choices: %w[P M G] } } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['options']).to eq('choices' => %w[P M G])
    end

    it 'rejects an invalid field type with errors' do
      post base,
           params: { custom_field: { key: 'x', label: 'X', field_type: 'nope' } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to be_present
    end
  end

  describe 'GET index' do
    it 'lists fields ordered by position' do
      funnel.funnel_custom_fields.create!(key: 'b', label: 'B', field_type: 'text', position: 1)
      funnel.funnel_custom_fields.create!(key: 'a', label: 'A', field_type: 'text', position: 0)

      get base, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.map { |f| f['key'] }).to eq(%w[a b])
    end
  end

  describe 'PATCH update' do
    it 'toggles show_on_card' do
      field = funnel.funnel_custom_fields.create!(key: 'valor', label: 'Valor', field_type: 'number', show_on_card: false)

      patch "#{base}/#{field.id}",
            params: { custom_field: { show_on_card: true } },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(field.reload.show_on_card).to be(true)
    end
  end

  describe 'DELETE destroy' do
    it 'removes the field' do
      field = funnel.funnel_custom_fields.create!(key: 'valor', label: 'Valor', field_type: 'number')

      delete "#{base}/#{field.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(funnel.funnel_custom_fields.exists?(field.id)).to be(false)
    end
  end

  describe 'funnel payload' do
    it 'includes custom_fields on the funnels index' do
      funnel.funnel_custom_fields.create!(key: 'valor', label: 'Valor', field_type: 'number', show_on_card: true)

      get "/api/v1/accounts/#{account.id}/funnels", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body.find { |f| f['id'] == funnel.id }
      expect(payload['custom_fields'].map { |f| f['key'] }).to include('valor')
    end
  end
end
