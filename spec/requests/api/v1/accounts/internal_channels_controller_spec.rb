# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::InternalChannelsController', type: :request do
  let(:account) { create(:account) }
  let(:alice) { create(:user, account: account, role: :agent) }
  let(:bob) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }

  describe 'GET /internal_channels' do
    it 'returns unauthorized without auth' do
      get "/api/v1/accounts/#{account.id}/internal_channels"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists only the channels the user belongs to' do
      mine = create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob)
      create(:internal_channel, :with_two_members, account: account) # not mine

      get "/api/v1/accounts/#{account.id}/internal_channels", headers: alice.create_new_auth_token

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.map { |c| c['id'] }
      expect(ids).to eq([mine.id])
    end
  end

  describe 'POST /internal_channels' do
    it 'finds-or-creates a DM with another user' do
      expect do
        post "/api/v1/accounts/#{account.id}/internal_channels",
             params: { user_id: bob.id }, headers: alice.create_new_auth_token
      end.to change(InternalChannel, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['title']).to eq(bob.name)
    end

    it 'rejects a DM with yourself' do
      post "/api/v1/accounts/#{account.id}/internal_channels",
           params: { user_id: alice.id }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'creates a group channel with chosen members' do
      post "/api/v1/accounts/#{account.id}/internal_channels",
           params: { name: 'Plantão', member_ids: [bob.id] }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['channel_type']).to eq('group_chat')
      expect(response.parsed_body['title']).to eq('Plantão')
    end

    it 'creates a team channel including the team members' do
      team = create(:team, account: account)
      team.add_members([bob.id])
      post "/api/v1/accounts/#{account.id}/internal_channels",
           params: { team_id: team.id }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['channel_type']).to eq('team')
    end
  end

  describe 'GET /internal_channels/:id' do
    let(:channel) { create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob) }

    it 'allows a member' do
      get "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}", headers: alice.create_new_auth_token
      expect(response).to have_http_status(:success)
    end

    it 'hides the channel from a non-member' do
      get "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}", headers: outsider.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /internal_channels/:id/read' do
    let(:channel) { create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob) }

    it 'stamps last_read_at for the requester' do
      post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/read", headers: alice.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(channel.members.find_by(user: alice).last_read_at).to be_present
    end
  end
end
