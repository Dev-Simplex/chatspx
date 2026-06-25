# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::InternalChannels::InternalMessagesController', type: :request do
  let(:account) { create(:account) }
  let(:alice) { create(:user, account: account, role: :agent) }
  let(:bob) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob) }

  describe 'GET /internal_channels/:id/internal_messages' do
    it 'returns the thread and marks it read' do
      create(:internal_message, internal_channel: channel, user: bob, content: 'oi alice')

      get "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
          headers: alice.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['content']).to eq('oi alice')
      expect(channel.members.find_by(user: alice).last_read_at).to be_present
    end

    it 'forbids a non-member' do
      get "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
          headers: outsider.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /internal_channels/:id/internal_messages' do
    it 'posts a message authored by the current user' do
      expect do
        post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
             params: { content: 'bom dia' }, headers: alice.create_new_auth_token
      end.to change(InternalMessage, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['content']).to eq('bom dia')
      expect(response.parsed_body['user']['id']).to eq(alice.id)
    end

    it 'rejects an empty message' do
      post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
           params: { content: '' }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
