# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Conversation Funnel Items API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas', color: '#2dc46f') }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Negociação', color: '#f59e0b', automation_type: 'open', position: 0) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe 'GET /api/v1/accounts/:account_id/conversations/:conversation_id/funnel_items' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get api_v1_account_conversation_funnel_items_url(account_id: account.id, conversation_id: conversation.display_id)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent with access to the conversation' do
      before { create(:inbox_member, inbox: inbox, user: agent) }

      it 'returns the funnel and stage the conversation sits in' do
        # NOTE: accounts auto-enroll conversations into a default funnel, so the
        # response may contain more than this placement — assert ours is present.
        FunnelItem.find_or_create_by(funnel: funnel, conversation: conversation) do |item|
          item.funnel_stage = stage
        end

        get api_v1_account_conversation_funnel_items_url(account_id: account.id, conversation_id: conversation.display_id),
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        entry = response.parsed_body.find { |item| item['funnel_id'] == funnel.id }
        expect(entry).to include(
          'funnel_name' => 'Vendas',
          'funnel_color' => '#2dc46f',
          'stage_id' => stage.id,
          'stage_name' => 'Negociação',
          'stage_color' => '#f59e0b'
        )
      end

      it 'returns an empty array when the conversation is in no funnel' do
        conversation.funnel_items.destroy_all

        get api_v1_account_conversation_funnel_items_url(account_id: account.id, conversation_id: conversation.display_id),
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to eq([])
      end
    end

    context 'when the agent has no access to the conversation inbox' do
      it 'returns unauthorized' do
        get api_v1_account_conversation_funnel_items_url(account_id: account.id, conversation_id: conversation.display_id),
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
