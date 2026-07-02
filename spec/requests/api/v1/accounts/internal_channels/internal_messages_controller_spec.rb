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
      expect(response.parsed_body['messages'].first['content']).to eq('oi alice')
      expect(response.parsed_body['has_more']).to be(false)
      expect(channel.members.find_by(user: alice).last_read_at).to be_present
    end

    it 'forbids a non-member' do
      get "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
          headers: outsider.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'paginates: newest page + has_more, and older via before' do
      create_list(:internal_message, 35, internal_channel: channel, user: bob)
      get "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
          headers: alice.create_new_auth_token
      body = response.parsed_body
      expect(body['messages'].size).to eq(30)
      expect(body['has_more']).to be(true)

      oldest = body['messages'].first['id']
      get "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
          params: { before: oldest }, headers: alice.create_new_auth_token
      older = response.parsed_body['messages']
      expect(older.size).to eq(5)
      expect(older.last['id']).to be < oldest
    end
  end

  describe 'reply / quote' do
    let(:original) { create(:internal_message, internal_channel: channel, user: bob, content: 'pergunta') }

    it 'creates a reply that quotes the original' do
      post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
           params: { content: 'resposta', reply_to_id: original.id }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['reply_to']['id']).to eq(original.id)
      expect(response.parsed_body['reply_to']['content']).to eq('pergunta')
    end

    it 'ignores a reply_to from another channel' do
      other = create(:internal_channel, :with_two_members, account: account)
      foreign = create(:internal_message, internal_channel: other, user: other.users.first)
      post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
           params: { content: 'oi', reply_to_id: foreign.id }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['reply_to']).to be_nil
    end
  end

  describe 'sharing a conversation' do
    let(:conversation) { create(:conversation, account: account) }

    it 'attaches a shared conversation preview by display_id' do
      post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
           params: { content: 'me ajuda nessa', shared_conversation_id: conversation.display_id },
           headers: alice.create_new_auth_token
      expect(response).to have_http_status(:created)
      shared = response.parsed_body['shared_conversation']
      expect(shared['display_id']).to eq(conversation.display_id)
      expect(shared['contact_name']).to eq(conversation.contact.name)
    end

    it 'ignores a conversation from another account' do
      foreign = create(:conversation)
      post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
           params: { content: 'oi', shared_conversation_id: foreign.display_id },
           headers: alice.create_new_auth_token
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['shared_conversation']).to be_nil
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

    it 'echoes back the client echo_id so the sender can reconcile (Fase 1.5)' do
      post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages",
           params: { content: 'oi', echo_id: 'abc-123' }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['echo_id']).to eq('abc-123')
    end
  end

  describe 'PATCH /internal_messages/:id (edit)' do
    let(:message) { create(:internal_message, internal_channel: channel, user: alice, content: 'oi') }

    it 'lets the author edit and marks it edited' do
      patch "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages/#{message.id}",
            params: { content: 'oi corrigido' }, headers: alice.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['content']).to eq('oi corrigido')
      expect(response.parsed_body['edited']).to be(true)
    end

    it 'forbids a non-author from editing' do
      patch "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages/#{message.id}",
            params: { content: 'hack' }, headers: bob.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE /internal_messages/:id' do
    let(:message) { create(:internal_message, internal_channel: channel, user: alice, content: 'oi') }

    it 'soft-deletes for the author' do
      delete "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages/#{message.id}",
             headers: alice.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['deleted']).to be(true)
      expect(response.parsed_body['content']).to be_nil
    end

    it 'forbids a non-author non-admin' do
      delete "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages/#{message.id}",
             headers: bob.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /internal_messages/:id/react' do
    let(:message) { create(:internal_message, internal_channel: channel, user: alice, content: 'oi') }

    it 'toggles a reaction for any member' do
      post "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages/#{message.id}/react",
           params: { emoji: '👍' }, headers: bob.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['reactions']).to eq('👍' => [bob.id])
    end
  end
end
