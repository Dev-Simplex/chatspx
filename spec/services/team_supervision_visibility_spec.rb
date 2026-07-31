# frozen_string_literal: true

require 'rails_helper'

# F2 de task/supervisor-de-time.md — VISIBILIDADE DAS CONVERSAS.
#
# O cenário é sempre o mesmo: `supervisor` NÃO é membro da caixa nem do time, só
# supervisiona `team`. Cada bloco cobre uma superfície de leitura e checa as três
# pontas: supervisor passa, agente comum continua bloqueado, admin inalterado.
RSpec.describe TeamSupervision do
  let!(:account) { create(:account) }
  let!(:team) { create(:team, account: account) }
  let!(:other_team) { create(:team, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:supervisor) { create(:user, account: account, role: :agent) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:owner) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  # A conversa do time supervisionado vive numa caixa da qual o supervisor NÃO é
  # membro e está atribuída a OUTRO agente — o caso que a feature promete destravar.
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
    Current.account = account
  end

  after { Current.account = nil }

  describe Conversations::PermissionFilterService do
    def filter_for(user)
      described_class.new(account.conversations, user, account).perform
    end

    it 'includes the supervised team conversation even without inbox access' do
      expect(filter_for(supervisor)).to include(supervised_conversation)
    end

    it 'does not include a team the user does not supervise' do
      expect(filter_for(supervisor)).not_to include(foreign_conversation)
    end

    it 'keeps the plain agent seeing everything in their own inbox' do
      expect(filter_for(agent)).to include(supervised_conversation, foreign_conversation)
    end

    it 'keeps an agent with neither inbox access nor supervision locked out' do
      outsider = create(:user, account: account, role: :agent)
      expect(filter_for(outsider)).to be_empty
    end

    it 'leaves the administrator untouched' do
      expect(filter_for(admin)).to include(supervised_conversation, foreign_conversation)
    end

    it 'adds to (does not replace) the supervisor own inbox conversations' do
      own_inbox = create(:inbox, account: account)
      create(:inbox_member, user: supervisor, inbox: own_inbox)
      own_conversation = create(:conversation, account: account, inbox: own_inbox, team: nil)

      expect(filter_for(supervisor)).to include(supervised_conversation, own_conversation)
    end
  end

  describe ConversationPolicy do
    def policy_for(user, conversation)
      account_user = account.account_users.find_by(user_id: user.id)
      described_class.new({ user: user, account: account, account_user: account_user }, conversation)
    end

    it 'authorizes the supervisor on the supervised team conversation' do
      expect(policy_for(supervisor, supervised_conversation).show?).to be(true)
    end

    it 'does not authorize a team the user does not supervise' do
      expect(policy_for(supervisor, foreign_conversation).show?).to be(false)
    end

    it 'keeps the plain agent authorized through inbox access' do
      expect(policy_for(agent, supervised_conversation).show?).to be(true)
    end
  end

  describe AgentConversationIsolation do
    before { inbox.update!(agent_conversation_isolation: true) }

    describe '.hidden_from?' do
      it 'does not block the supervisor of the conversation team' do
        expect(described_class.hidden_from?(supervised_conversation, supervisor, account)).to be(false)
      end

      it 'still blocks a plain agent who is not the owner' do
        expect(described_class.hidden_from?(supervised_conversation, agent, account)).to be(true)
      end

      it 'still blocks the supervisor on a team they do not supervise' do
        expect(described_class.hidden_from?(foreign_conversation, supervisor, account)).to be(true)
      end
    end

    describe '.exclude_hidden' do
      let(:relation) { account.conversations.joins(:inbox) }

      it 'keeps the supervised team conversation in scope' do
        expect(described_class.exclude_hidden(relation, supervisor, account)).to include(supervised_conversation)
      end

      it 'still removes a colleague owned conversation for the plain agent' do
        expect(described_class.exclude_hidden(relation, agent, account)).not_to include(supervised_conversation)
      end

      it 'still removes the non supervised team' do
        expect(described_class.exclude_hidden(relation, supervisor, account)).not_to include(foreign_conversation)
      end
    end
  end

  describe MessageFinder do
    let!(:owner_message) do
      create(:message, account: account, inbox: inbox, conversation: supervised_conversation,
                       content: 'bolha do colega', agent_id: owner.id)
    end

    before { inbox.update!(agent_message_isolation: true) }

    after { Current.user = nil }

    def messages_for(user)
      Current.user = user
      described_class.new(supervised_conversation, {}).perform
    end

    it 'returns every bubble to the supervisor of the team' do
      expect(messages_for(supervisor)).to include(owner_message)
    end

    it 'still hides the colleague bubble from the plain agent' do
      expect(messages_for(agent)).not_to include(owner_message)
    end

    it 'leaves the administrator untouched' do
      expect(messages_for(admin)).to include(owner_message)
    end
  end

  describe Conversations::ListPreloader do
    let!(:owner_message) do
      create(:message, account: account, inbox: inbox, conversation: supervised_conversation,
                       content: 'ultima do colega', agent_id: owner.id)
    end

    before { inbox.update!(agent_message_isolation: true) }

    it 'previews the real last message for the supervisor' do
      result = described_class.call([supervised_conversation], user: supervisor)
      expect(result.last_messages[supervised_conversation.id]).to eq(owner_message)
    end

    it 'still hides the colleague last message from the plain agent' do
      result = described_class.call([supervised_conversation], user: agent)
      expect(result.last_messages[supervised_conversation.id]).to be_nil
    end
  end

  describe ConversationFinder do
    def list_for(user)
      described_class.new(user, { status: 'all' }).perform[:conversations]
    end

    it 'lists the supervised team conversation for a non inbox member' do
      expect(list_for(supervisor)).to include(supervised_conversation)
    end

    it 'does not list the team the user does not supervise' do
      expect(list_for(supervisor)).not_to include(foreign_conversation)
    end

    it 'keeps the plain agent view unchanged' do
      expect(list_for(agent)).to include(supervised_conversation, foreign_conversation)
    end

    context 'when the supervisor is ALSO a member of a team' do
      let!(:own_team) { create(:team, account: account) }
      let!(:own_conversation) { create(:conversation, account: account, inbox: inbox, team: own_team) }

      before do
        create(:team_member, team: own_team, user: supervisor)
        create(:inbox_member, user: supervisor, inbox: inbox)
      end

      it 'unions the teams: own plus supervised' do
        expect(list_for(supervisor)).to include(own_conversation, supervised_conversation)
      end

      it 'still leaves out the foreign team' do
        expect(list_for(supervisor)).not_to include(foreign_conversation)
      end
    end
  end

  describe SearchService do
    let!(:supervised_message) do
      create(:message, account: account, inbox: inbox, conversation: supervised_conversation,
                       content: 'expelliarmus do colega', agent_id: owner.id)
    end

    def search_for(user, type)
      described_class.new(current_user: user, current_account: account, params: { q: 'expelliarmus' }, search_type: type).perform
    end

    it 'finds the supervised team message even in a foreign inbox' do
      expect(search_for(supervisor, 'Message')[:messages]).to include(supervised_message)
    end

    it 'still hides the colleague message from the plain agent in an isolated inbox' do
      inbox.update!(agent_message_isolation: true)
      expect(search_for(agent, 'Message')[:messages]).not_to include(supervised_message)
    end

    it 'finds the supervised team conversation by display_id' do
      result = described_class.new(
        current_user: supervisor, current_account: account,
        params: { q: supervised_conversation.display_id.to_s }, search_type: 'Conversation'
      ).perform
      expect(result[:conversations]).to include(supervised_conversation)
    end
  end
end
