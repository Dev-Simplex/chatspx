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

    it 'creates a team channel (admin) including the team members' do
      admin = create(:user, account: account, role: :administrator)
      team = create(:team, account: account)
      team.add_members([bob.id])
      post "/api/v1/accounts/#{account.id}/internal_channels",
           params: { team_id: team.id }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['channel_type']).to eq('team')
    end

    it 'forbids a non-admin from creating a team channel' do
      team = create(:team, account: account)
      post "/api/v1/accounts/#{account.id}/internal_channels",
           params: { team_id: team.id }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'group management (Fase 5)' do
    let(:group) do
      g = create(:internal_channel, :group_chat, account: account)
      g.members.create!(user: alice)
      g.members.create!(user: bob)
      g
    end

    it 'renames a group for a member' do
      patch "/api/v1/accounts/#{account.id}/internal_channels/#{group.id}",
            params: { name: 'Plantão noturno' }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(group.reload.name).to eq('Plantão noturno')
    end

    it 'adds a member' do
      carol = create(:user, account: account, role: :agent)
      post "/api/v1/accounts/#{account.id}/internal_channels/#{group.id}/add_member",
           params: { user_id: carol.id }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(group.reload.users).to include(carol)
    end

    it 'removes a member' do
      delete "/api/v1/accounts/#{account.id}/internal_channels/#{group.id}/remove_member",
             params: { user_id: bob.id }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(group.reload.users).not_to include(bob)
    end

    it 'lets a member leave' do
      post "/api/v1/accounts/#{account.id}/internal_channels/#{group.id}/leave",
           headers: alice.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(group.reload.users).not_to include(alice)
    end

    it 'forbids managing a DM (rename)' do
      dm = create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob)
      patch "/api/v1/accounts/#{account.id}/internal_channels/#{dm.id}",
            params: { name: 'x' }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
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

    it 'broadcasts a read receipt to the other member' do
      expect do
        post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/read", headers: alice.create_new_auth_token
      end.to have_enqueued_job(ActionCableBroadcastJob)
        .with([bob.pubsub_token], 'internal.read', hash_including(user_id: alice.id))
    end
  end

  describe 'POST /internal_channels/:id/typing' do
    let(:channel) { create(:internal_channel, :with_two_members, account: account, user_a: alice, user_b: bob) }

    it 'broadcasts a typing event to the other member only' do
      expect do
        post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/typing",
             params: { typing: true }, headers: alice.create_new_auth_token
      end.to have_enqueued_job(ActionCableBroadcastJob)
        .with([bob.pubsub_token], 'internal.typing', hash_including(typing: true))
      expect(response).to have_http_status(:success)
    end

    it 'forbids a non-member' do
      post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/typing",
           params: { typing: true }, headers: outsider.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end
end
