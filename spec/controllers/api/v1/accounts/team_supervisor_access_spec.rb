# frozen_string_literal: true

require 'rails_helper'

# F2 de task/supervisor-de-time.md — prova de ponta a ponta dos dois guards de
# controller: ConversationTeamAccessConcern (isolamento por time) e
# AgentConversationAccessConcern (isolamento por agente). O supervisor abre a
# conversa do time que supervisiona mesmo sem ser membro da caixa nem do time;
# o agente comum, na mesma situação, continua levando 403.
RSpec.describe 'Team supervisor conversation access', type: :request do
  let!(:account) { create(:account) }
  let!(:team) { create(:team, account: account) }
  let!(:other_team) { create(:team, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:supervisor) { create(:user, account: account, role: :agent) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:owner) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:supervised_conversation) { create(:conversation, account: account, inbox: inbox, team: team) }
  let!(:foreign_conversation) { create(:conversation, account: account, inbox: inbox, team: other_team) }

  before do
    create(:team_supervisor, team: team, user: supervisor)
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: owner, inbox: inbox)
    create(:team_member, team: team, user: owner)
    create(:team_member, team: other_team, user: owner)
    # O assignee só "cola" depois que o dono é membro da caixa E do time —
    # AssignmentHandler#ensure_assignee_is_from_team zera o assignee_id no create.
    supervised_conversation.update!(assignee: owner)
    foreign_conversation.update!(assignee: owner)
  end

  def show_conversation(conversation, user)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}",
        headers: user.create_new_auth_token, as: :json
  end

  def show_messages(conversation, user)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
        headers: user.create_new_auth_token, as: :json
  end

  context 'with the team isolation (fork default)' do
    it 'lets the supervisor open the supervised team conversation' do
      show_conversation(supervised_conversation, supervisor)
      expect(response).to have_http_status(:success)
    end

    it 'lets the supervisor read the sub resources (messages)' do
      show_messages(supervised_conversation, supervisor)
      expect(response).to have_http_status(:success)
    end

    # 401 e não 403: sem caixa e sem supervisão a ConversationPolicy já barra, e o
    # fork traduz Pundit::NotAuthorizedError em :unauthorized (comportamento antigo).
    it 'blocks the supervisor on a team they do NOT supervise' do
      show_conversation(foreign_conversation, supervisor)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'still blocks a plain agent who is not on the team' do
      show_conversation(supervised_conversation, agent)
      expect(response).to have_http_status(:forbidden)
    end

    it 'leaves the administrator untouched' do
      show_conversation(supervised_conversation, admin)
      expect(response).to have_http_status(:success)
    end
  end

  context 'with agent_conversation_isolation enabled on the inbox' do
    before { inbox.update!(agent_conversation_isolation: true) }

    it 'lets the supervisor open a conversation owned by ANOTHER agent' do
      show_conversation(supervised_conversation, supervisor)
      expect(response).to have_http_status(:success)
    end

    it 'still returns the rich 403 to the plain agent' do
      create(:team_member, team: team, user: agent)
      show_conversation(supervised_conversation, agent)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error_code']).to eq('conversation_access_blocked')
    end

    it 'lets the owner open their own conversation' do
      show_conversation(supervised_conversation, owner)
      expect(response).to have_http_status(:success)
    end
  end
end
