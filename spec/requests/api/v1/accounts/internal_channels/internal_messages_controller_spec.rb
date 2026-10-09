# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::InternalChannels::InternalMessagesController', type: :request do
  # A API do chat interno exige a feature ligada na conta (InternalChatFeatureGuard).
  let(:account) { create(:account).tap { |acc| acc.enable_features!('internal_chat') } }
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

    # O admin lê qualquer canal para auditoria, mas apagar é irreversível
    # (soft_delete! zera o conteúdo e purga anexos). Moderar exige participar.
    it 'forbids an admin who is not a member of the channel' do
      admin = create(:user, account: account, role: :administrator)

      delete "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages/#{message.id}",
             headers: admin.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
      expect(message.reload.deleted?).to be(false)
    end

    it 'allows an admin who is a member of the channel to moderate' do
      admin = create(:user, account: account, role: :administrator)
      create(:internal_channel_member, internal_channel: channel, user: admin)

      delete "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages/#{message.id}",
             headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(message.reload.deleted?).to be(true)
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

  describe 'POST /internal_messages/:id/forward' do
    let(:message) { create(:internal_message, internal_channel: channel, user: bob, content: 'repassa isso') }
    let(:carol) { create(:user, account: account, role: :agent) }
    let(:group) { create(:internal_channel, :group_chat, account: account) }
    let(:url) { "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages/#{message.id}/forward" }

    before { create(:internal_channel_member, internal_channel: group, user: alice) }

    it 'copies the message to a group I belong to and to a new DM, with the forwarded seal' do
      post url, params: { channel_ids: [group.id], user_ids: [carol.id] }, headers: alice.create_new_auth_token

      expect(response).to have_http_status(:success)
      copies = InternalMessage.where(user: alice, content: 'repassa isso')
      expect(copies.count).to eq(2)
      expect(copies.map { |m| m.content_attributes['forwarded'] }).to all(be(true))
      dm = copies.map(&:internal_channel).find(&:direct?)
      expect(dm.users).to contain_exactly(alice, carol)
    end

    it 'keeps the attachment (same file) on the copy' do
      message.attachments.attach(io: StringIO.new('pdf'), filename: 'proposta.pdf', content_type: 'application/pdf')
      message.save!

      post url, params: { channel_ids: [group.id] }, headers: alice.create_new_auth_token

      copy = group.messages.last
      expect(copy.attachments.first.blob).to eq(message.attachments.first.blob)
    end

    it 'ignores channels I am not a member of' do
      other_group = create(:internal_channel, :group_chat, account: account)

      post url, params: { channel_ids: [other_group.id] }, headers: alice.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(other_group.messages).to be_empty
    end

    it 'forbids forwarding from a conversation I do not belong to (admin audit is read-only)' do
      admin = create(:user, account: account, role: :administrator)
      create(:internal_channel_member, internal_channel: group, user: admin)

      post url, params: { channel_ids: [group.id] }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
      expect(group.messages).to be_empty
    end
  end

  describe 'GET /internal_messages/:id/receipts' do
    let(:group) { create(:internal_channel, :group_chat, account: account) }
    let(:carol) { create(:user, account: account, role: :agent, name: 'Carol') }
    let(:message) { create(:internal_message, internal_channel: group, user: alice, content: 'reunião às 15h') }
    let(:url) { "/api/v1/accounts/#{account.id}/internal_channels/#{group.id}/internal_messages/#{message.id}/receipts" }

    before do
      create(:internal_channel_member, internal_channel: group, user: alice, last_read_at: 1.minute.from_now)
      create(:internal_channel_member, internal_channel: group, user: bob)
      create(:internal_channel_member, internal_channel: group, user: carol)
    end

    it 'splits the other members by last_read_at: read after the message vs not yet' do
      message
      group.members.find_by(user: bob).update!(last_read_at: 2.minutes.from_now)
      group.members.find_by(user: carol).update!(last_read_at: 1.hour.ago)

      get url, headers: alice.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['read'].pluck('id')).to eq([bob.id])
      expect(response.parsed_body['read'].first['last_read_at']).to be_present
      expect(response.parsed_body['unread'].pluck('id')).to eq([carol.id])
    end

    it 'never lists the author' do
      get url, headers: bob.create_new_auth_token

      ids = response.parsed_body.values.flatten.pluck('id')
      expect(ids).not_to include(alice.id)
    end

    it 'is not available to someone outside the conversation' do
      get url, headers: outsider.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /internal_messages/:id/star (favoritas por usuário)' do
    let(:message) { create(:internal_message, internal_channel: channel, user: bob, content: 'senha do wifi: 1234') }
    let(:star_url) { "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages/#{message.id}/star" }
    let(:list_url) { "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/starred" }

    it 'stars only for me and lists only my stars' do
      post star_url, params: { starred: true }, headers: alice.create_new_auth_token
      expect(response.parsed_body['starred']).to be(true)

      get list_url, headers: alice.create_new_auth_token
      expect(response.parsed_body.pluck('id')).to eq([message.id])

      get list_url, headers: bob.create_new_auth_token
      expect(response.parsed_body).to be_empty
    end

    it 'is idempotent and unstars' do
      2.times { post star_url, params: { starred: true }, headers: alice.create_new_auth_token }
      expect(message.stars.count).to eq(1)

      post star_url, params: { starred: false }, headers: alice.create_new_auth_token
      expect(response.parsed_body['starred']).to be(false)
      expect(message.stars.count).to eq(0)
    end

    it 'leaves deleted messages out of the list' do
      post star_url, params: { starred: true }, headers: alice.create_new_auth_token
      message.soft_delete!

      get list_url, headers: alice.create_new_auth_token
      expect(response.parsed_body).to be_empty
    end

    it 'refuses someone outside the conversation' do
      post star_url, params: { starred: true }, headers: outsider.create_new_auth_token
      expect(response).to have_http_status(:not_found)
      expect(message.stars).to be_empty
    end
  end
end
