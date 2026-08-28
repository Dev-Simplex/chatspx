require 'rails_helper'

RSpec.describe 'Conversation Pins API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  # A mais antiga é a que vamos fixar: sem o alfinete ela fica embaixo, então a
  # subida para o topo é prova de que a fixação mandou na ordem.
  let!(:older) { create(:conversation, account: account, inbox: inbox, last_activity_at: 2.days.ago) }
  let!(:newer) { create(:conversation, account: account, inbox: inbox, last_activity_at: 1.minute.ago) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_member, inbox: inbox, user: other_agent)
  end

  def pin_url(conversation)
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/pin"
  end

  def listed_ids_for(user)
    get "/api/v1/accounts/#{account.id}/conversations", params: { status: 'open' }, headers: user.create_new_auth_token, as: :json
    response.parsed_body['data']['payload'].map { |conversation| conversation['id'] }
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/{id}/pin' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post pin_url(older)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'pins to the top, keeps it there, and unpins back to the normal order' do
        expect(listed_ids_for(agent)).to eq([newer.display_id, older.display_id])

        post pin_url(older), headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['pinned']).to be(true)
        expect(listed_ids_for(agent)).to eq([older.display_id, newer.display_id])

        post pin_url(older), headers: agent.create_new_auth_token, as: :json

        expect(response.parsed_body['pinned']).to be(false)
        expect(listed_ids_for(agent)).to eq([newer.display_id, older.display_id])
      end

      it 'does not change the list of any other agent' do
        post pin_url(older), headers: agent.create_new_auth_token, as: :json

        expect(listed_ids_for(agent)).to eq([older.display_id, newer.display_id])
        expect(listed_ids_for(other_agent)).to eq([newer.display_id, older.display_id])
      end

      it 'keeps the chosen ordering among the pinned ones' do
        pinned_older = older
        pinned_newer = create(:conversation, account: account, inbox: inbox, last_activity_at: 1.day.ago)

        post pin_url(pinned_older), headers: agent.create_new_auth_token, as: :json
        post pin_url(pinned_newer), headers: agent.create_new_auth_token, as: :json

        # As duas fixadas vêm primeiro e, entre elas, a mais recente na frente.
        expect(listed_ids_for(agent)).to eq([pinned_newer.display_id, pinned_older.display_id, newer.display_id])
      end

      it 'reports the pinned flag per user in the conversation payload' do
        post pin_url(older), headers: agent.create_new_auth_token, as: :json

        get "/api/v1/accounts/#{account.id}/conversations", params: { status: 'open' }, headers: agent.create_new_auth_token, as: :json
        mine = response.parsed_body['data']['payload'].find { |c| c['id'] == older.display_id }
        expect(mine['pinned']).to be(true)

        get "/api/v1/accounts/#{account.id}/conversations", params: { status: 'open' }, headers: other_agent.create_new_auth_token, as: :json
        theirs = response.parsed_body['data']['payload'].find { |c| c['id'] == older.display_id }
        expect(theirs['pinned']).to be(false)
      end
    end

    context 'when the agent has no access to the conversation' do
      let(:outsider) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        post pin_url(older), headers: outsider.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(ConversationPin.count).to eq(0)
      end
    end

    it 'keeps the pin out of the inbox, so it never leaks to the whole team' do
      post pin_url(older), headers: agent.create_new_auth_token, as: :json

      expect(ConversationPin.where(user: agent).pluck(:conversation_id)).to eq([older.id])
      expect(inbox.reload.additional_attributes.keys).not_to include('pin_mode', 'pinned_conversation_ids')
    end

    # "Mesmo se for admin": não existe parâmetro para fixar em nome de outro. Quem
    # tentar leva o alfinete para a própria lista e a do agente não se mexe.
    context 'when it is an authenticated administrator' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      before { create(:inbox_member, inbox: inbox, user: admin) }

      it 'ignores any attempt to pin on behalf of somebody else' do
        post pin_url(older), params: { user_id: agent.id }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(ConversationPin.pluck(:user_id)).to eq([admin.id])
        expect(listed_ids_for(admin)).to eq([older.display_id, newer.display_id])
        expect(listed_ids_for(agent)).to eq([newer.display_id, older.display_id])
      end
    end
  end

  # Sobrou um dia um segundo sistema de fixar, guardado na inbox: fixava para
  # TODOS os agentes dela. Foi removido; isto aqui existe para ele não voltar
  # pela porta dos fundos do update de inbox.
  describe 'PATCH /api/v1/accounts/{account.id}/inboxes/{id}' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'refuses to store shared pins in the inbox' do
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { additional_attributes: { pin_mode: 'per_inbox', pinned_conversation_ids: [older.display_id] } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(inbox.reload.additional_attributes.keys).not_to include('pin_mode', 'pinned_conversation_ids')
    end

    it 'still stores the other inbox settings' do
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { additional_attributes: { agent_signature_enabled: true, allowed_template_names: %w[hello bye] } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(inbox.reload.additional_attributes).to include(
        'agent_signature_enabled' => true,
        'allowed_template_names' => %w[hello bye]
      )
    end
  end
end
