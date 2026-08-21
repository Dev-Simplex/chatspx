require 'rails_helper'

RSpec.describe 'Conversation Message Reactions API', type: :request do
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:other_agent) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let!(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_member, inbox: inbox, user: other_agent)
  end

  def reactions_path
    api_v1_account_conversation_message_reactions_url(
      account_id: account.id,
      conversation_id: conversation.display_id,
      message_id: message.id
    )
  end

  def reaction_path(reaction_id)
    api_v1_account_conversation_message_reaction_url(
      account_id: account.id,
      conversation_id: conversation.display_id,
      message_id: message.id,
      id: reaction_id
    )
  end

  describe 'GET index' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get reactions_path
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns aggregated reactions grouped by emoji' do
        create(:message_reaction, message: message, account: account, reactor: agent, emoji: '👍')
        create(:message_reaction, message: message, account: account, reactor: other_agent, emoji: '👍')
        create(:message_reaction, message: message, account: account, reactor: admin, emoji: '🔥')

        get reactions_path, headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['counts']).to eq('👍' => 2, '🔥' => 1)
        thumbs = body['payload'].find { |row| row['emoji'] == '👍' }
        expect(thumbs['count']).to eq(2)
        expect(thumbs['users'].pluck('id')).to contain_exactly(agent.id, other_agent.id)
      end
    end
  end

  describe 'POST create' do
    context 'when unauthenticated' do
      it 'returns 401' do
        post reactions_path, params: { emoji: '👍' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when emoji is not whitelisted' do
      it 'returns 422' do
        post reactions_path,
             params: { emoji: '🍕' },
             headers: agent.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid_emoji')
      end
    end

    context 'when emoji exceeds length limit' do
      it 'returns 422' do
        post reactions_path,
             params: { emoji: 'a' * 11 },
             headers: agent.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it 'creates a new reaction and dispatches MESSAGE_REACTION_ADDED' do
      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
        Events::Types::MESSAGE_REACTION_ADDED, anything, hash_including(:message, :reaction)
      )

      post reactions_path,
           params: { emoji: '👍' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['emoji']).to eq('👍')
      expect(body['user_id']).to eq(agent.id)
      expect(message.reload.reactions.count).to eq(1)
    end

    it 'is idempotent when re-reacting with the same emoji' do
      create(:message_reaction, message: message, account: account, reactor: agent, emoji: '👍')

      post reactions_path,
           params: { emoji: '👍' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(message.reload.reactions.count).to eq(1)
    end

    it 'updates the existing reaction when re-reacting with a different emoji' do
      reaction = create(:message_reaction, message: message, account: account, reactor: agent, emoji: '👍')

      post reactions_path,
           params: { emoji: '🔥' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(reaction.reload.emoji).to eq('🔥')
      expect(message.reload.reactions.count).to eq(1)
    end
  end

  describe 'DELETE destroy' do
    let!(:reaction) { create(:message_reaction, message: message, account: account, reactor: agent, emoji: '👍') }

    context 'when unauthenticated' do
      it 'returns 401' do
        delete reaction_path(reaction.id)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when owner' do
      it 'deletes the reaction and returns 204' do
        # O evento de remocao carrega VALORES (reaction_id, emoji, user_id, user_type), nao o
        # registro: aqui ele ja foi apagado, e serializar por GlobalID faria o job estourar ao
        # reidratar o que nao existe mais. Ver dispatch_removed no controller.
        expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
          Events::Types::MESSAGE_REACTION_REMOVED, anything,
          hash_including(:message, :reaction_id, :emoji, :user_id, :user_type)
        )

        delete reaction_path(reaction.id), headers: agent.create_new_auth_token

        expect(response).to have_http_status(:no_content)
        expect(MessageReaction.exists?(reaction.id)).to be(false)
      end
    end

    context 'when administrator' do
      it 'deletes the reaction of another user' do
        delete reaction_path(reaction.id), headers: admin.create_new_auth_token
        expect(response).to have_http_status(:no_content)
      end
    end

    context 'when not owner and not admin' do
      it 'returns 403' do
        delete reaction_path(reaction.id), headers: other_agent.create_new_auth_token
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when reaction does not exist' do
      it 'returns 404' do
        delete reaction_path(0), headers: agent.create_new_auth_token
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
