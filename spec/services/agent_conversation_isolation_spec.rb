# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentConversationIsolation do
  let!(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:owner) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  # A conversa precisa TER time: o isolamento e escopado pelo time da conversa
  # (Inbox#isolation_applies_to_team?). `allow_auto_assign: false` para o
  # AssignmentHandler nao inventar um assignee no caso "sem dono".
  let!(:team) { create(:team, account: account, allow_auto_assign: false) }
  let!(:other_team) { create(:team, account: account, allow_auto_assign: false) }

  # Sem isso o `before_save :ensure_assignee_is_from_team` ZERA o assignee de quem
  # nao e membro do time — e o caso "conversa do colega" deixaria de existir.
  before do
    [agent, owner].each do |user|
      create(:team_member, team: team, user: user)
      create(:team_member, team: other_team, user: user)
    end
  end

  describe '.hidden_from?' do
    context 'when the inbox is NOT isolated' do
      it 'never hides, even a colleague conversation' do
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: owner)
        expect(described_class.hidden_from?(conv, agent, account)).to be(false)
      end
    end

    context 'when the inbox IS isolated' do
      before { inbox.update!(agent_conversation_isolation: true) }

      it 'hides a colleague-owned conversation from a non-owner agent' do
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: owner)
        expect(described_class.hidden_from?(conv, agent, account)).to be(true)
      end

      it 'does not hide my own conversation' do
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent)
        expect(described_class.hidden_from?(conv, agent, account)).to be(false)
      end

      it 'does not hide an unassigned conversation (queue/AI accessible to assume)' do
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: nil)
        expect(described_class.hidden_from?(conv, agent, account)).to be(false)
      end

      it 'never hides from an administrator' do
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: owner)
        expect(described_class.hidden_from?(conv, admin, account)).to be(false)
      end

      it 'never hides when there is no user (jobs/widget/public context)' do
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: owner)
        expect(described_class.hidden_from?(conv, nil, account)).to be(false)
      end

      it 'derives the account from the conversation when not passed' do
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: owner)
        expect(described_class.hidden_from?(conv, agent)).to be(true)
      end
    end

    # ESCOPO POR TIME: a flag liga a regra na caixa, a lista diz em QUAIS times ela vale.
    context 'when isolation is scoped to teams' do
      before { inbox.update!(agent_conversation_isolation: true) }

      it 'hides the colleague conversation when the team list is empty (retrocompat)' do
        inbox.update!(agent_conversation_isolation_team_ids: [])
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: owner)
        expect(described_class.hidden_from?(conv, agent, account)).to be(true)
      end

      it 'hides it when the conversation team is in the list' do
        inbox.update!(agent_conversation_isolation_team_ids: [team.id])
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: owner)
        expect(described_class.hidden_from?(conv, agent, account)).to be(true)
      end

      it 'does NOT hide it when the conversation team is NOT in the list' do
        inbox.update!(agent_conversation_isolation_team_ids: [other_team.id])
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: owner)
        expect(described_class.hidden_from?(conv, agent, account)).to be(false)
      end

      it 'never hides from an administrator whatever the list' do
        inbox.update!(agent_conversation_isolation_team_ids: [team.id])
        conv = create(:conversation, account: account, inbox: inbox, team: team, assignee: owner)
        expect(described_class.hidden_from?(conv, admin, account)).to be(false)
      end
    end

    # A CONVERSA SEM TIME — a distincao que separa esta regra das duas de MENSAGEM.
    #
    # Nas regras de mensagem a conversa sem time e ISENTA (Inbox::TEAMLESS_EXEMPT_RULES):
    # ela nasce assim, antes da triagem, e esconder as bolhas esconderia o lead novo.
    # Aqui NAO: o que fecha a conversa nesta regra e "tem dono humano diferente de mim",
    # criterio que nao e o time. Se o escopo por time isentasse a conversa sem time, o
    # deploy da feature ABRIRIA para todo agente a conversa do colega ainda sem triagem —
    # regressao de seguranca, nao o relaxamento que o admin pediu.
    context 'with a conversation that has no team yet' do
      before { inbox.update!(agent_conversation_isolation: true) }

      it 'STILL hides a colleague-owned conversation (empty list = state of every inbox on deploy)' do
        inbox.update!(agent_conversation_isolation_team_ids: [])
        conv = create(:conversation, account: account, inbox: inbox, team: nil, assignee: owner)
        expect(described_class.hidden_from?(conv, agent, account)).to be(true)
      end

      it 'still lets the owner in' do
        conv = create(:conversation, account: account, inbox: inbox, team: nil, assignee: agent)
        expect(described_class.hidden_from?(conv, agent, account)).to be(false)
      end

      it 'still lets anyone take the unowned queue conversation' do
        conv = create(:conversation, account: account, inbox: inbox, team: nil, assignee: nil)
        expect(described_class.hidden_from?(conv, agent, account)).to be(false)
      end

      it 'never hides from an administrator' do
        conv = create(:conversation, account: account, inbox: inbox, team: nil, assignee: owner)
        expect(described_class.hidden_from?(conv, admin, account)).to be(false)
      end

      # Uma vez que o admin RESTRINGE a lista a times, a conversa sem time deixa de casar
      # a lista e sai do escopo — decisao explicita do admin, nao efeito colateral do deploy.
      it 'stops hiding it once the admin restricts the list to specific teams' do
        inbox.update!(agent_conversation_isolation_team_ids: [team.id])
        conv = create(:conversation, account: account, inbox: inbox, team: nil, assignee: owner)
        expect(described_class.hidden_from?(conv, agent, account)).to be(false)
      end
    end
  end

  describe '.exclude_hidden' do
    let(:relation) { account.conversations.joins(:inbox) }

    context 'when the inbox IS isolated' do
      before { inbox.update!(agent_conversation_isolation: true) }

      let!(:mine) { create(:conversation, account: account, inbox: inbox, team: team, assignee: agent) }
      let!(:foreign) { create(:conversation, account: account, inbox: inbox, team: team, assignee: owner) }
      let!(:unassigned) { create(:conversation, account: account, inbox: inbox, team: team, assignee: nil) }

      it 'removes a colleague-owned conversation for a non-owner agent' do
        result = described_class.exclude_hidden(relation, agent, account)
        expect(result).to include(mine, unassigned)
        expect(result).not_to include(foreign)
      end

      it 'keeps everything for an administrator' do
        result = described_class.exclude_hidden(relation, admin, account)
        expect(result).to include(mine, foreign, unassigned)
      end

      it 'returns the relation untouched when there is no user' do
        expect(described_class.exclude_hidden(relation, nil, account)).to eq(relation)
      end
    end

    context 'when the inbox is NOT isolated' do
      let!(:foreign) { create(:conversation, account: account, inbox: inbox, team: team, assignee: owner) }

      it 'keeps a colleague conversation' do
        expect(described_class.exclude_hidden(relation, agent, account)).to include(foreign)
      end
    end

    # ESCOPO POR TIME no espelho SQL da regra: se ele divergir do `hidden_from?` em Ruby,
    # a galeria/o download em massa escondem o que a conversa aberta mostra (ou o contrario).
    context 'when isolation is scoped to teams' do
      before { inbox.update!(agent_conversation_isolation: true) }

      let!(:foreign) { create(:conversation, account: account, inbox: inbox, team: team, assignee: owner) }

      it 'removes the colleague conversation when the team list is empty (retrocompat)' do
        inbox.update!(agent_conversation_isolation_team_ids: [])
        expect(described_class.exclude_hidden(relation, agent, account)).not_to include(foreign)
      end

      it 'removes it when the conversation team is in the list' do
        inbox.update!(agent_conversation_isolation_team_ids: [team.id])
        expect(described_class.exclude_hidden(relation, agent, account)).not_to include(foreign)
      end

      it 'keeps it when the conversation team is NOT in the list' do
        inbox.update!(agent_conversation_isolation_team_ids: [other_team.id])
        expect(described_class.exclude_hidden(relation, agent, account)).to include(foreign)
      end

      it 'keeps everything for an administrator whatever the list' do
        inbox.update!(agent_conversation_isolation_team_ids: [team.id])
        expect(described_class.exclude_hidden(relation, admin, account)).to include(foreign)
      end

      # O espelho SQL tem que concordar com o Ruby linha a linha.
      it 'agrees with hidden_from? on every case' do
        inbox.update!(agent_conversation_isolation_team_ids: [team.id])
        outside = create(:conversation, account: account, inbox: inbox, team: other_team, assignee: owner)
        kept = described_class.exclude_hidden(relation, agent, account)

        expect(kept.include?(foreign)).to be(!described_class.hidden_from?(foreign, agent, account))
        expect(kept.include?(outside)).to be(!described_class.hidden_from?(outside, agent, account))
      end
    end

    # A CONVERSA SEM TIME no espelho SQL. Este e o caminho da galeria de anexos, dos links
    # e do download em massa — as superficies de CONTA, que nao passam pelo guard
    # por-conversa. Se o SQL isentasse a conversa sem time, a midia da conversa do colega
    # ainda sem triagem vazaria por aqui mesmo com o guard bloqueando a abertura.
    context 'with a conversation that has no team yet' do
      before { inbox.update!(agent_conversation_isolation: true) }

      let!(:teamless_foreign) { create(:conversation, account: account, inbox: inbox, team: nil, assignee: owner) }
      let!(:teamless_mine) { create(:conversation, account: account, inbox: inbox, team: nil, assignee: agent) }

      it 'STILL removes the colleague-owned conversation with an empty list' do
        inbox.update!(agent_conversation_isolation_team_ids: [])
        result = described_class.exclude_hidden(relation, agent, account)
        expect(result).to include(teamless_mine)
        expect(result).not_to include(teamless_foreign)
      end

      it 'keeps it for an administrator' do
        expect(described_class.exclude_hidden(relation, admin, account)).to include(teamless_foreign)
      end

      # O SQL e o Ruby tem que responder a MESMA coisa aqui — divergir e como a galeria
      # entrega o anexo de uma conversa que o guard bloqueia (ou esconde a que ele abre).
      it 'agrees with hidden_from? on the teamless conversation, empty list and restricted list' do
        [[], [team.id]].each do |list|
          inbox.update!(agent_conversation_isolation_team_ids: list)
          kept = described_class.exclude_hidden(relation, agent, account)
          expect(kept.include?(teamless_foreign)).to be(!described_class.hidden_from?(teamless_foreign.reload, agent, account))
        end
      end
    end
  end
end
