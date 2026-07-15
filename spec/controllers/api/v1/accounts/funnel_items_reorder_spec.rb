# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Funnel Items reorder API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:team) { create(:team, account: account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Time X', color: '#94a3b8', team_id: team.id) }
  let(:open_stage) { FunnelStage.create!(funnel: funnel, name: 'Abertos', automation_type: 'open', position: 0) }
  let(:other_stage) { FunnelStage.create!(funnel: funnel, name: 'Fechados', automation_type: 'resolved', position: 1) }

  let!(:conversation_1) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let!(:conversation_2) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let!(:conversation_3) { create(:conversation, account: account, inbox: inbox, status: :open) }

  let!(:item_1) { FunnelItem.create!(funnel: funnel, funnel_stage: open_stage, conversation: conversation_1, position: 1) }
  let!(:item_2) { FunnelItem.create!(funnel: funnel, funnel_stage: open_stage, conversation: conversation_2, position: 2) }
  let!(:item_3) { FunnelItem.create!(funnel: funnel, funnel_stage: open_stage, conversation: conversation_3, position: 3) }

  before do
    team.add_members([agent.id])
    create(:inbox_member, inbox: inbox, user: agent)
  end

  def reorder(params, headers: agent.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items/reorder",
         params: params, headers: headers, as: :json
  end

  describe 'POST reorder' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        reorder({ funnel_stage_id: open_stage.id, item_ids: [item_3.id, item_1.id, item_2.id] }, headers: {})
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'persists the new order as 1-based positions' do
        reorder({ funnel_stage_id: open_stage.id, item_ids: [item_3.id, item_1.id, item_2.id] })

        expect(response).to have_http_status(:success)
        expect(item_3.reload.position).to eq(1)
        expect(item_1.reload.position).to eq(2)
        expect(item_2.reload.position).to eq(3)
      end

      it 'ignores ids that do not belong to the stage' do
        stranger = FunnelItem.create!(funnel: funnel, funnel_stage: other_stage, conversation: create(:conversation, account: account, inbox: inbox))
        original = stranger.position

        reorder({ funnel_stage_id: open_stage.id, item_ids: [stranger.id, item_2.id, item_1.id] })

        expect(response).to have_http_status(:success)
        # stranger is on another stage: untouched. Only the two valid ids get 1..2.
        expect(stranger.reload.position).to eq(original)
        expect(item_2.reload.position).to eq(1)
        expect(item_1.reload.position).to eq(2)
      end

      it 'does not bump moved_at (reorder is not a stage change)' do
        before_moved_at = item_1.reload.moved_at
        reorder({ funnel_stage_id: open_stage.id, item_ids: [item_1.id, item_2.id, item_3.id] })
        expect(item_1.reload.moved_at).to eq(before_moved_at)
      end

      it 'is a no-op with blank item_ids' do
        reorder({ funnel_stage_id: open_stage.id, item_ids: [] })
        expect(response).to have_http_status(:success)
        expect(item_1.reload.position).to eq(1)
      end
    end
  end
end
