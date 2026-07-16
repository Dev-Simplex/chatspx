require 'rails_helper'

# O fork isola conversas por TIME: quem não é do time da conversa não pode vê-la
# (`authorize_team_access` no ConversationsController). O guard vivia SÓ lá, mas
# 13 controllers pendurados no Conversations::BaseController (mensagens, labels,
# participantes, funil...) só chamavam `authorize :show?` — e a ConversationPolicy
# aprova por ACESSO À CAIXA, que o agente tem.
#
# Resultado: `GET /conversations/:id` dava 403 e `GET /conversations/:id/messages`
# devolvia 200 com o conteúdo do outro time. A conversa ficava fechada pela porta
# da frente e aberta pela janela.
RSpec.describe 'Conversations sub-resources team access', type: :request do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:other_team) { create(:team, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, team: other_team) }

  # O agente TEM acesso à caixa (por isso a policy o aprova), mas NÃO é do time
  # da conversa: é exatamente o furo.
  let(:outsider) { create(:user, account: account, role: :agent) }

  before do
    create(:inbox_member, inbox: inbox, user: outsider)
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'segredo do outro time')
  end

  def url_for(path = nil)
    base = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}"
    path ? "#{base}/#{path}" : base
  end

  context 'when the agent is not in the conversation team' do
    it 'blocks the conversation itself (comportamento já existente)' do
      get url_for, headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    # Este é o P11: mesma conversa, porta diferente.
    it 'blocks the messages of that conversation' do
      get url_for('messages'), headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include('segredo do outro time')
    end

    it 'blocks the labels of that conversation' do
      get url_for('labels'), headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'blocks the participants of that conversation' do
      get url_for('participants'), headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'blocks WRITING a message into that conversation' do
      post url_for('messages'),
           headers: outsider.create_new_auth_token,
           params: { content: 'invadindo' },
           as: :json

      expect(response).to have_http_status(:forbidden)
      expect(conversation.reload.messages.pluck(:content)).not_to include('invadindo')
    end

    # O guard era uma lista `only:` e estas duas actions ficaram de fora — vazavam
    # metadado da conversa (assistente de IA / eventos e SLA) para quem não é do time.
    it 'blocks the inbox_assistant of that conversation' do
      get url_for('inbox_assistant'), headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    # Escalada de privilégio: sem o guard, o agente de fora tirava o time da
    # conversa (`team_id: 0`) e, com o time nulo, ela caía no colo dele.
    it 'blocks stripping the team off the conversation' do
      post url_for('assignments'),
           headers: outsider.create_new_auth_token,
           params: { team_id: 0 },
           as: :json

      expect(response).to have_http_status(:forbidden)
      expect(conversation.reload.team_id).to eq(other_team.id)
    end
  end

  # As liberações abaixo existem para o guard não trancar quem tem direito.
  context 'when the user legitimately has access' do
    it 'allows a member of the conversation team' do
      insider = create(:user, account: account, role: :agent)
      create(:inbox_member, inbox: inbox, user: insider)
      create(:team_member, user: insider, team: other_team)

      get url_for('messages'), headers: insider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'allows the assignee even if not in the team (atribuição implica acesso)' do
      assignee = create(:user, account: account, role: :agent)
      create(:inbox_member, inbox: inbox, user: assignee)
      conversation.update_columns(assignee_id: assignee.id) # rubocop:disable Rails/SkipsModelValidations

      get url_for('messages'), headers: assignee.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'allows an administrator' do
      admin = create(:user, account: account, role: :administrator)

      get url_for('messages'), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'allows any inbox member when the conversation has no team' do
      teamless = create(:conversation, account: account, inbox: inbox, team: nil)
      get "/api/v1/accounts/#{account.id}/conversations/#{teamless.display_id}/messages",
          headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end
end
