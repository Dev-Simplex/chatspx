# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Funnel Items API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:funnel) { Funnel.create!(account: account, name: 'Geral', color: '#94a3b8') }
  let(:open_stage) { FunnelStage.create!(funnel: funnel, name: 'Abertos', automation_type: 'open', position: 0) }
  let(:resolved_stage) { FunnelStage.create!(funnel: funnel, name: 'Resolvidos', automation_type: 'resolved', position: 1) }

  let!(:conversation_1) { create(:conversation, account: account, inbox: inbox, status: :open, last_activity_at: 3.minutes.ago) }
  let!(:conversation_2) { create(:conversation, account: account, inbox: inbox, status: :open, last_activity_at: 2.minutes.ago) }
  let!(:conversation_3) { create(:conversation, account: account, inbox: inbox, status: :open, last_activity_at: 1.minute.ago) }
  let!(:conversation_resolved) { create(:conversation, account: account, inbox: inbox, status: :open, last_activity_at: 4.minutes.ago) }

  let!(:item_1) { FunnelItem.create!(funnel: funnel, funnel_stage: open_stage, conversation: conversation_1) }
  let!(:item_2) { FunnelItem.create!(funnel: funnel, funnel_stage: open_stage, conversation: conversation_2) }
  let!(:item_3) { FunnelItem.create!(funnel: funnel, funnel_stage: open_stage, conversation: conversation_3) }
  let!(:resolved_item) { FunnelItem.create!(funnel: funnel, funnel_stage: resolved_stage, conversation: conversation_resolved) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    account.enable_features!('kanban_cursor_loading')
  end

  describe 'GET /api/v1/accounts/:account_id/funnels/:funnel_id/funnel_items' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns payload/meta in cursor mode with pagination metadata' do
        get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items",
            params: { mode: 'cursor', stage_id: open_stage.id, limit: 2 },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body

        expect(body).to include('payload', 'meta')
        expect(body['payload'].map { |item| item['id'] }).to eq([item_3.id, item_2.id])
        expect(body['meta']['stage_id']).to eq(open_stage.id)
        expect(body['meta']['has_more']).to eq(true)
        expect(body['meta']['next_cursor']).to be_present
        expect(body['meta']['limit']).to eq(2)
      end

      it 'supports next page retrieval with cursor' do
        get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items",
            params: { mode: 'cursor', stage_id: open_stage.id, limit: 2 },
            headers: agent.create_new_auth_token,
            as: :json

        next_cursor = response.parsed_body.dig('meta', 'next_cursor')

        get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items",
            params: { mode: 'cursor', stage_id: open_stage.id, limit: 2, cursor: next_cursor },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body

        expect(body['payload'].map { |item| item['id'] }).to eq([item_1.id])
        expect(body['meta']['has_more']).to eq(false)
        expect(body['meta']['next_cursor']).to be_nil
      end

      it 'applies exclude_automation_type filter in cursor mode' do
        get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items",
            params: { mode: 'cursor', exclude_automation_type: 'resolved', limit: 10 },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        payload_ids = response.parsed_body.fetch('payload').map { |item| item['id'] }
        expect(payload_ids).to match_array([item_1.id, item_2.id, item_3.id])
      end

      it 'falls back safely when cursor is invalid' do
        get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items",
            params: { mode: 'cursor', stage_id: open_stage.id, limit: 2, cursor: 'invalid-cursor' },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        payload_ids = response.parsed_body.fetch('payload').map { |item| item['id'] }
        expect(payload_ids).to eq([item_3.id, item_2.id])
      end

      it 'keeps legacy response format when mode is not cursor' do
        get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items",
            params: { stage_id: open_stage.id, page: 1, per_page: 2 },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to be_an(Array)
      end

      it 'keeps deduplication by contact phone within the stage' do
        shared_phone = '+5511988887777'
        contact_a = create(:contact, account: account, phone_number: shared_phone)
        contact_b = create(:contact, account: account, phone_number: '+5511912345678')
        contact_b.update_column(:phone_number, shared_phone)

        conversation_a = create(:conversation, account: account, inbox: inbox, contact: contact_a, assignee: agent, status: :open, last_activity_at: 10.minutes.ago)
        conversation_b = create(:conversation, account: account, inbox: inbox, contact: contact_b, assignee: agent, status: :open, last_activity_at: 30.seconds.ago)

        FunnelItem.create!(funnel: funnel, funnel_stage: open_stage, conversation: conversation_a)
        FunnelItem.create!(funnel: funnel, funnel_stage: open_stage, conversation: conversation_b)

        get "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items",
            params: { mode: 'cursor', stage_id: open_stage.id, limit: 30 },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        payload = response.parsed_body.fetch('payload')

        matching_ids = payload.map { |item| item['conversation_id'] }.select do |conversation_id|
          [conversation_a.id, conversation_b.id].include?(conversation_id)
        end

        expect(matching_ids.length).to eq(1)
        expect(matching_ids.first).to eq(conversation_b.id)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/funnels/:funnel_id/funnel_items/:id' do
    context 'when authenticated' do
      it 'moves to resolved stage and resolves conversation without team' do
        expect(conversation_1.team_id).to be_nil
        expect(conversation_1.status).to eq('open')

        patch "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items/#{item_1.id}",
              params: { funnel_item: { funnel_stage_id: resolved_stage.id } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(item_1.reload.funnel_stage_id).to eq(resolved_stage.id)
        expect(conversation_1.reload.status).to eq('resolved')
      end

      it 'returns not found when target stage does not exist' do
        patch "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items/#{item_1.id}",
              params: { funnel_item: { funnel_stage_id: 999_999 } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/funnels/:funnel_id/funnel_items' do
    context 'when authenticated' do
      it 'accepts conversation display_id as conversation_id payload' do
        expect(item_1.reload.funnel_stage_id).to eq(open_stage.id)
        expect(conversation_1.reload.status).to eq('open')

        post "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items",
             params: {
               funnel_item: {
                 conversation_id: conversation_1.display_id,
                 funnel_stage_id: resolved_stage.id
               }
             },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(item_1.reload.funnel_stage_id).to eq(resolved_stage.id)
        expect(conversation_1.reload.status).to eq('resolved')
      end
    end
  end
end
