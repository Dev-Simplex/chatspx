# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Kanban AI status (Fase 7)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/kanban_ai/status" }

  it 'requires authentication' do
    get endpoint
    expect(response).to have_http_status(:unauthorized)
  end

  it 'reports unavailable when AI is not configured' do
    get endpoint, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['available']).to be(false)
  end

  it 'reports available when the feature + key are present' do
    account.enable_features!('captain_tasks')
    allow_any_instance_of(Captain::OpenaiHookService).to receive(:configured?).and_return(true)

    get endpoint, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['available']).to be(true)
  end
end
