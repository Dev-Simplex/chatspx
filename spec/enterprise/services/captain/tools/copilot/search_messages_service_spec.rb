require 'rails_helper'

# A busca de mensagens do copilot tem que parar no mesmo limite da tela: caixa da qual o agente
# é membro e, se ele tem time, conversa do time dele ou sem time (Conversations::PermissionFilterService).
RSpec.describe Captain::Tools::Copilot::SearchMessagesService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:own_inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    create(:inbox_member, user: agent, inbox: own_inbox)
    message_in(own_inbox, 'comprovante da minha caixa')
    message_in(other_inbox, 'comprovante de outra caixa')
  end

  def message_in(inbox, content, team: nil)
    create(:message, account: account, content: content, conversation: create(:conversation, account: account, inbox: inbox, team: team))
  end

  def search(user)
    described_class.new(assistant, user: user).execute(query: 'comprovante')
  end

  it 'does not return messages from an inbox the agent is not a member of' do
    result = search(agent)

    expect(result).to include('comprovante da minha caixa')
    expect(result).not_to include('comprovante de outra caixa')
  end

  it 'does not return messages from a conversation of another team' do
    own_team = create(:team, account: account)
    create(:team_member, team: own_team, user: agent)
    message_in(own_inbox, 'comprovante do outro time', team: create(:team, account: account))

    result = search(agent)

    expect(result).to include('comprovante da minha caixa')
    expect(result).not_to include('comprovante do outro time')
  end

  it 'keeps returning every message of the account to an administrator' do
    result = search(create(:user, account: account, role: :administrator))

    expect(result).to include('comprovante da minha caixa', 'comprovante de outra caixa')
  end
end
