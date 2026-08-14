# frozen_string_literal: true

require 'rails_helper'

# Abrir uma conversa de GRUPO agenda a atualizacao dos integrantes; abrir uma
# conversa 1:1 nao pode agendar nada (seria chamada externa a toa em 100% do
# trafego normal).
RSpec.describe 'Sync automatico dos integrantes ao abrir a conversa', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def open_conversation(conversation)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}",
        headers: agent.create_new_auth_token, as: :json
  end

  context 'when the conversation is a WhatsApp group' do
    let(:contact) { create(:contact, account: account, identifier: '120363040285567246@g.us') }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

    it 'agenda o sync sem bloquear a resposta' do
      expect { open_conversation(conversation) }
        .to have_enqueued_job(Waha::GroupSyncJob).with(conversation.id)

      expect(response).to have_http_status(:success)
    end

    it 'devolve a conversa normalmente mesmo se o enfileiramento falhar' do
      allow(Waha::GroupSyncJob).to receive(:perform_later).and_raise(StandardError, 'redis fora')

      open_conversation(conversation)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(conversation.display_id)
    end
  end

  context 'when the conversation is one-to-one' do
    let(:contact) { create(:contact, account: account, identifier: '5566999991234@c.us') }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

    it 'nao agenda sync nenhum' do
      expect { open_conversation(conversation) }.not_to have_enqueued_job(Waha::GroupSyncJob)
    end
  end
end
