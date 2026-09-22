require 'rails_helper'

# O ConversationBuilder REUSA a conversa que já existe do contato na caixa
# (lock_to_single_conversation e WAHA). Como `create` é CONVERSATIONLESS_ACTION,
# nem o guard de time nem o isolamento por agente rodavam ali: a mensagem do
# "Nova conversa" era gravada dentro do atendimento de OUTRO time e o agente
# levava 403 ao ser redirecionado para a conversa que ele mesmo acabara de
# alimentar.
RSpec.describe 'Conversations create on reused conversation', type: :request do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account, lock_to_single_conversation: true) }
  let!(:my_team) { create(:team, account: account) }
  let!(:other_team) { create(:team, account: account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:contact) { create(:contact, account: account) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: my_team, user: agent)
  end

  def create_conversation
    post "/api/v1/accounts/#{account.id}/conversations",
         params: { source_id: contact_inbox.source_id, inbox_id: inbox.id, contact_id: contact.id,
                   assignee_id: agent.id, team_id: my_team.id, message: { content: 'ola' } },
         headers: agent.create_new_auth_token, as: :json
  end

  context 'when the existing conversation belongs to another team' do
    let!(:existing) do
      create(:conversation, account: account, inbox: inbox, contact: contact,
                            contact_inbox: contact_inbox, team: other_team)
    end

    it 'blocks with 403 and does not write the message into it' do
      expect { create_conversation }.not_to change(existing.messages, :count)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error_code']).to eq('conversation_access_blocked')
      expect(existing.reload.team_id).to eq(other_team.id)
    end
  end

  context 'when the existing conversation is resolved and belongs to another team' do
    let!(:existing) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                            team: other_team, status: :resolved)
    end

    it 'blocks too — a conversa resolvida também é reusada pelo builder' do
      expect { create_conversation }.not_to change(existing.messages, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  context 'when the existing conversation has no owner and no team' do
    let!(:existing) do
      create(:conversation, account: account, inbox: inbox, contact: contact,
                            contact_inbox: contact_inbox, team: nil, assignee: nil)
    end

    it 'adota quem está iniciando: aplica agente e time do modal e envia a mensagem' do
      expect { create_conversation }.to change(existing.messages, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(existing.reload.assignee_id).to eq(agent.id)
      expect(existing.team_id).to eq(my_team.id)
    end
  end

  context 'when the existing conversation is already mine' do
    # Sem time de propósito: o modelo zera o assignee que não é membro do time
    # (AssignmentHandler), então "conversa minha" na vida real é sem time ou no
    # meu time.
    let!(:existing) do
      create(:conversation, account: account, inbox: inbox, contact: contact,
                            contact_inbox: contact_inbox, team: nil, assignee: agent)
    end

    it 'segue enviando (assignee sempre alcança a própria conversa)' do
      expect { create_conversation }.to change(existing.messages, :count).by(1)

      expect(response).to have_http_status(:success)
    end
  end

  context 'when the inbox isolates conversations by agent' do
    let!(:isolated_inbox) do
      create(:inbox, account: account, lock_to_single_conversation: true, agent_conversation_isolation: true)
    end
    let!(:isolated_contact_inbox) { create(:contact_inbox, contact: contact, inbox: isolated_inbox) }
    let!(:colleague) { create(:user, account: account, role: :agent) }
    let!(:existing) do
      create(:conversation, account: account, inbox: isolated_inbox, contact: contact,
                            contact_inbox: isolated_contact_inbox, team: nil, assignee: colleague)
    end

    before { create(:inbox_member, inbox: isolated_inbox, user: agent) }

    it 'blocks the message from landing in the colleague conversation' do
      expect do
        post "/api/v1/accounts/#{account.id}/conversations",
             params: { source_id: isolated_contact_inbox.source_id, inbox_id: isolated_inbox.id,
                       contact_id: contact.id, assignee_id: agent.id, message: { content: 'ola' } },
             headers: agent.create_new_auth_token, as: :json
      end.not_to change(existing.messages, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  context 'when there is no conversation yet' do
    it 'cria a conversa normalmente com o agente e o time escolhidos' do
      create_conversation

      expect(response).to have_http_status(:success)
      conversation = account.conversations.last
      expect(conversation.assignee_id).to eq(agent.id)
      expect(conversation.team_id).to eq(my_team.id)
    end
  end
end
