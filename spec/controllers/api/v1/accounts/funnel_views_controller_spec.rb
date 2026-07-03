# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Funnel Views API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let(:base) { "/api/v1/accounts/#{account.id}/funnel_views" }

  describe 'unauthenticated' do
    it 'returns unauthorized' do
      get base
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    it 'creates a view owned by the current user' do
      post base,
           params: { funnel_view: { funnel_id: funnel.id, name: 'SLA estourando',
                                    view_mode: 'kanban', filters: { status: 'open', priority: ['high'] } } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('name' => 'SLA estourando', 'user_id' => agent.id)
      expect(response.parsed_body['filters']).to eq('status' => 'open', 'priority' => ['high'])
    end
  end

  describe 'GET index' do
    it 'returns own + shared views, scoped to the funnel' do
      mine = account.funnel_views.create!(funnel: funnel, user: agent, name: 'Mine', view_mode: 'kanban')
      shared = account.funnel_views.create!(funnel: funnel, user: other_agent, name: 'Shared', is_shared: true, view_mode: 'kanban')
      account.funnel_views.create!(funnel: funnel, user: other_agent, name: 'Hidden', view_mode: 'kanban')

      get base, params: { funnel_id: funnel.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      names = response.parsed_body.map { |v| v['id'] }
      expect(names).to contain_exactly(mine.id, shared.id)
    end
  end

  describe 'PATCH update' do
    it 'lets the owner rename their view' do
      view = account.funnel_views.create!(funnel: funnel, user: agent, name: 'Old', view_mode: 'kanban')

      patch "#{base}/#{view.id}", params: { funnel_view: { name: 'New' } },
                                  headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(view.reload.name).to eq('New')
    end

    it 'forbids editing another user\'s private view' do
      view = account.funnel_views.create!(funnel: funnel, user: other_agent, name: 'Theirs', view_mode: 'kanban')

      patch "#{base}/#{view.id}", params: { funnel_view: { name: 'Hijack' } },
                                  headers: agent.create_new_auth_token, as: :json

      # Chatwoot renders Pundit denials as 401; the key point is the view is untouched.
      expect(response).to have_http_status(:unauthorized)
      expect(view.reload.name).to eq('Theirs')
    end
  end

  describe 'DELETE destroy' do
    it 'lets the owner delete their view' do
      view = account.funnel_views.create!(funnel: funnel, user: agent, name: 'Tmp', view_mode: 'kanban')

      delete "#{base}/#{view.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.funnel_views.exists?(view.id)).to be(false)
    end
  end
end
