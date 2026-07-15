# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Funnel Item custom field values (Kanban v2)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:team) { create(:team, account: account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas', team_id: team.id) }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0) }
  let!(:value_field) do
    funnel.funnel_custom_fields.create!(key: 'valor', label: 'Valor', field_type: 'number', show_on_card: true)
  end

  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open, team: team) }
  let(:item) { FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: conversation) }
  let(:attr_key) { "funnel_#{funnel.id}_valor" }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items/#{item.id}/custom_attributes" }

  before do
    team.add_members([agent.id])
    create(:inbox_member, inbox: inbox, user: agent)
  end

  describe 'PATCH custom_attributes' do
    it 'sets a funnel-namespaced value' do
      patch endpoint,
            params: { custom_attributes: { attr_key => '1500' } },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['custom_attributes']).to eq(attr_key => '1500')
      expect(conversation.reload.custom_attributes[attr_key]).to eq('1500')
    end

    it 'never clobbers attributes outside this funnel namespace' do
      conversation.update!(custom_attributes: { 'cpf' => '123', "funnel_#{funnel.id}_valor" => '10' })

      patch endpoint,
            params: { custom_attributes: { attr_key => '2000' } },
            headers: agent.create_new_auth_token, as: :json

      expect(conversation.reload.custom_attributes).to include('cpf' => '123', attr_key => '2000')
    end

    it 'ignores keys outside this funnel namespace' do
      patch endpoint,
            params: { custom_attributes: { 'evil' => 'x', attr_key => '5' } },
            headers: agent.create_new_auth_token, as: :json

      expect(conversation.reload.custom_attributes).to eq(attr_key => '5')
    end

    it 'clears the value when sent blank' do
      conversation.update!(custom_attributes: { attr_key => '99' })

      patch endpoint,
            params: { custom_attributes: { attr_key => '' } },
            headers: agent.create_new_auth_token, as: :json

      expect(conversation.reload.custom_attributes).not_to have_key(attr_key)
    end
  end

  describe 'GET funnel_items index aggregates' do
    before { account.enable_features!('kanban_cursor_loading') }

    it 'returns sum/avg/count for numeric show_on_card fields across the stage' do
      c1 = create(:conversation, account: account, inbox: inbox, status: :open, team: team, custom_attributes: { attr_key => '100' })
      c2 = create(:conversation, account: account, inbox: inbox, status: :open, team: team, custom_attributes: { attr_key => '300' })
      c3 = create(:conversation, account: account, inbox: inbox, status: :open, team: team, custom_attributes: { attr_key => 'not-a-number' })
      FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: c1)
      FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: c2)
      FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: c3)

      get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items",
          params: { mode: 'cursor', stage_id: stage.id, limit: 50 },
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      aggregates = response.parsed_body.dig('meta', 'aggregates')
      expect(aggregates['valor']).to include('sum' => 400.0, 'count' => 2, 'label' => 'Valor')
      expect(aggregates['valor']['avg']).to eq(200.0)
    end
  end

  describe 'funnel_item serializer' do
    before { account.enable_features!('kanban_cursor_loading') }

    it 'exposes only this funnel\'s namespaced custom_attributes' do
      conversation.update!(custom_attributes: { attr_key => '42', 'cpf' => '999' })
      item

      get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items",
          params: { mode: 'cursor', stage_id: stage.id, limit: 50 },
          headers: agent.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].find { |i| i['id'] == item.id }
      expect(payload['conversation']['custom_attributes']).to eq(attr_key => '42')
    end
  end
end
