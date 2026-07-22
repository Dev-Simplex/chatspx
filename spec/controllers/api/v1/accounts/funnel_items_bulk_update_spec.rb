# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Funnel Items bulk_update (Kanban v2 / Fase 3)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assignee) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:team) { create(:team, account: account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas', team_id: team.id) }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0) }
  let(:c1) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:c2) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items/bulk_update" }

  before do
    team.add_members([agent.id])
    create(:inbox_member, inbox: inbox, user: agent)
    FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: c1)
    FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: c2)
  end

  it 'requires authentication' do
    post endpoint, params: { operation: 'reassign', conversation_ids: [c1.id] }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an unknown operation' do
    post endpoint,
         params: { operation: 'nuke', conversation_ids: [c1.id] },
         headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  describe 'reassign' do
    it 'assigns the chosen agent to all selected conversations' do
      post endpoint,
           params: { operation: 'reassign', conversation_ids: [c1.id, c2.id], assignee_id: assignee.id },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('processed' => 2, 'failed' => 0)
      expect(c1.reload.assignee_id).to eq(assignee.id)
      expect(c2.reload.assignee_id).to eq(assignee.id)
    end

    # D1 (guard d): o bulk do Kanban e a 4a porta de troca de dono. Com o modo de
    # pedido ligado, roubar a conversa de um colega por aqui deve ser BARRADO (sem
    # criar pedido em massa) — senao o D1 seria contornavel pelo Kanban.
    it 'skips reassigning a colleague human-owned conversation when the takeover mode is on' do
      colleague = create(:user, account: account, role: :agent)
      create(:inbox_member, inbox: inbox, user: colleague)
      c1.update!(assignee: colleague)
      account.update!(takeover_request_gate: true)

      post endpoint,
           params: { operation: 'reassign', conversation_ids: [c1.id], assignee_id: assignee.id },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(c1.reload.assignee_id).to eq(colleague.id) # nao foi roubada
      expect(ConversationTakeoverRequest.count).to eq(0) # e nao virou pedido em massa
    end
  end

  describe 'tag' do
    it 'adds labels without removing existing ones' do
      c1.add_labels(['vip'])

      post endpoint,
           params: { operation: 'tag', conversation_ids: [c1.id], labels: ['urgente'] },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(c1.reload.label_list).to include('vip', 'urgente')
    end
  end

  describe 'archive' do
    it 'resolves conversations that pass the team gate and skips those that fail' do
      team = create(:team, account: account)
      c1.update!(team: team)

      post endpoint,
           params: { operation: 'archive', conversation_ids: [c1.id, c2.id] },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      # c1 (has team) resolves; c2 (no team) is skipped by the resolve gate.
      expect(response.parsed_body['processed']).to eq(1)
      expect(response.parsed_body['failed']).to eq(1)
      expect(c1.reload.status).to eq('resolved')
      expect(c2.reload.status).to eq('open')
    end
  end
end
