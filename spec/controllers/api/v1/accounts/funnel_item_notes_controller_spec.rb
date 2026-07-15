# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Funnel Item Notes API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:team) { create(:team, account: account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas', team_id: team.id) }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:item) { FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: conversation) }
  let(:base) { "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items/#{item.id}/notes" }

  before { team.add_members([agent.id]) }

  describe 'unauthenticated' do
    it 'returns unauthorized' do
      get base
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    it 'creates a note authored by the current user' do
      post base, params: { content: 'Cliente pediu retorno amanhã' },
                 headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('content' => 'Cliente pediu retorno amanhã', 'user_id' => agent.id)
      expect(response.parsed_body['user']['name']).to be_present
      expect(item.funnel_item_notes.count).to eq(1)
    end

    it 'rejects a blank note' do
      post base, params: { content: '   ' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET index' do
    it 'lists notes newest-first' do
      item.funnel_item_notes.create!(user: agent, content: 'first', created_at: 2.minutes.ago)
      item.funnel_item_notes.create!(user: agent, content: 'second', created_at: 1.minute.ago)

      get base, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.map { |n| n['content'] }).to eq(%w[second first])
    end
  end

  describe 'DELETE destroy' do
    it 'lets the author delete their note' do
      note = item.funnel_item_notes.create!(user: agent, content: 'mine')

      delete "#{base}/#{note.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(item.funnel_item_notes.exists?(note.id)).to be(false)
    end

    it 'forbids deleting another user\'s note' do
      note = item.funnel_item_notes.create!(user: other_agent, content: 'theirs')

      delete "#{base}/#{note.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(item.funnel_item_notes.exists?(note.id)).to be(true)
    end
  end
end
