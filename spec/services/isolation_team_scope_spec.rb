# frozen_string_literal: true

require 'rails_helper'

# ESCOPO POR TIME DAS 3 REGRAS DE ISOLAMENTO DA CAIXA.
#
# A flag booleana LIGA a regra na caixa; a lista de times diz EM QUAIS times ela vale.
# A regra mora num lugar so — `Inbox#isolation_applies_to_team?` (e o espelho SQL
# `Inbox.isolation_applies_sql`) — e cada ponto de leitura so faz a pergunta.
#
# A matriz da regra pura esta em spec/models/inbox_spec.rb. Este arquivo cobre os pontos
# de aplicacao que nao tinham spec proprio (a associacao `messages` e o ConversationFinder);
# os demais foram cobertos dentro do spec de cada ponto: message_finder_spec,
# list_preloader_spec, search_service_spec, agent_message_isolation_spec,
# active_attendances_controller_spec e agent_conversation_isolation_spec.
#
# As quatro perguntas se repetem em todo ponto, e nas quatro a resposta errada tem DOIS
# lados ruins — vazar mensagem entre times, ou esconder o que deveria aparecer:
#
#   lista VAZIA        -> isola (retrocompat: e o estado de toda caixa ja configurada);
#   time ESCOLHIDO     -> isola;
#   time NAO escolhido -> abre;
#   conversa SEM time  -> abre nas 2 regras de MENSAGEM (nasce assim, antes da triagem);
#   admin              -> ve tudo, sempre.
#
# A conversa SEM time e a UNICA linha em que as familias de regra divergem: as duas de
# mensagem sao isentas (Inbox::TEAMLESS_EXEMPT_RULES), `agent_conversation_isolation` NAO
# — ali o criterio de fechamento e o dono humano, nao o time, e isentar abriria no deploy
# a conversa do colega ainda sem triagem. Este arquivo cobre as 2 regras de mensagem; a
# outra ponta esta em spec/models/inbox_spec.rb e spec/services/agent_conversation_isolation_spec.rb.
#
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Isolamento por caixa escopado por time' do
  let!(:account) { create(:account) }
  let!(:team) { create(:team, account: account) }
  let!(:other_team) { create(:team, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:colleague) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  # PONTO 1 — a lambda da association `Conversation#messages`.
  #
  # Este e o codigo que derrubou em silencio o no de mensagem do flow, o CSAT, o NPS e o
  # encerramento automatico quando o time da conversa mudou: mensagem com team_id defasado
  # sumia da associacao. Quem precisa da conversa INTEIRA le `all_messages` — ver o
  # comentario em conversations/message_window_service.rb, que NAO passa por aqui.
  describe 'team_message_isolation na associacao Conversation#messages' do
    let!(:conversation) { create(:conversation, account: account, inbox: inbox, team: team) }
    let!(:public_message) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
    end
    # Carimbada com o time ANTIGO: e a mensagem que some quando a regra alcanca a conversa.
    let!(:stale_message) do
      msg = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing)
      msg.update_column(:team_id, other_team.id) # rubocop:disable Rails/SkipsModelValidations
      msg
    end

    def visible_ids
      conversation.reload.messages.pluck(:id)
    end

    it 'shows every message when the flag is off, whatever the list says' do
      inbox.update!(team_message_isolation: false, team_message_isolation_team_ids: [team.id])
      expect(visible_ids).to include(public_message.id, stale_message.id)
    end

    it 'hides the other-team message when the list is empty (retrocompat)' do
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [])
      expect(visible_ids).to include(public_message.id)
      expect(visible_ids).not_to include(stale_message.id)
    end

    it 'hides the other-team message when the conversation team is in the list' do
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [team.id])
      expect(visible_ids).not_to include(stale_message.id)
    end

    it 'shows everything when the conversation team is NOT in the list' do
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [other_team.id])
      expect(visible_ids).to include(public_message.id, stale_message.id)
    end

    it 'shows everything on a conversation without a team' do
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [team.id])
      conversation.update!(team: nil)
      expect(visible_ids).to include(public_message.id, stale_message.id)
    end

    # Esta regra depende SO da conversa (nao de quem olha), entao nao ha isencao de admin
    # para checar aqui: o admin ve o mesmo recorte que o agente. O que garante que nada
    # sumiu de verdade e `all_messages`.
    it 'keeps every message reachable through all_messages even while isolated' do
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [team.id])
      expect(conversation.reload.all_messages.pluck(:id)).to include(public_message.id, stale_message.id)
    end
  end

  # PONTO 2 — ConversationFinder#filter_by_query: nao descobrir a conversa do colega so
  # pelo CONTEUDO da mensagem dele. O recorte agora e por conversa (o time e da conversa),
  # nao mais por caixa.
  describe 'agent_message_isolation na busca da lista (ConversationFinder)' do
    let!(:conversation) { create(:conversation, account: account, inbox: inbox, team: team) }
    # A mensagem e o ISCA da busca: e so por ela que a conversa aparece no `q`.
    let!(:colleague_message) do # rubocop:disable RSpec/LetSetup
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :outgoing, sender: colleague, content: 'expelliarmus do colega')
    end

    before do
      [agent, colleague, admin].each { |user| create(:inbox_member, user: user, inbox: inbox) }
      [agent, colleague].each { |user| create(:team_member, team: team, user: user) }
      Current.account = account
      inbox.update!(agent_message_isolation: true)
    end

    after { Current.account = nil }

    def found_by(user)
      ConversationFinder.new(user, { status: 'all', q: 'expelliarmus' }).perform[:conversations]
    end

    it 'hides the colleague conversation when the team list is empty (retrocompat)' do
      inbox.update!(agent_message_isolation_team_ids: [])
      expect(found_by(agent)).not_to include(conversation)
    end

    it 'hides the colleague conversation when the conversation team is in the list' do
      inbox.update!(agent_message_isolation_team_ids: [team.id])
      expect(found_by(agent)).not_to include(conversation)
    end

    it 'finds the conversation when the conversation team is NOT in the list' do
      inbox.update!(agent_message_isolation_team_ids: [other_team.id])
      expect(found_by(agent)).to include(conversation)
    end

    # O agente aqui e membro de `team`, e o ConversationFinder ESCOPA a lista aos times do
    # agente nao-admin (set_team, conversation_finder.rb:168) — comportamento que existe desde
    # antes desta feature. Entao uma conversa sem time some da lista dele por ESSE filtro, nao
    # pelo isolamento. Para provar o que este exemplo se propoe a provar — que a regra de
    # isolamento NAO alcanca conversa sem time — o observador tem que ser um agente SEM time,
    # que nao sofre o escopo.
    it 'finds a conversation without a team (observador sem time, fora do escopo por time)' do
      solitario = create(:user, account: account, role: :agent)
      create(:inbox_member, user: solitario, inbox: inbox)
      inbox.update!(agent_message_isolation_team_ids: [team.id])
      conversation.update!(team: nil)
      expect(found_by(solitario)).to include(conversation)
    end

    it 'lets the author find their own conversation whatever the list' do
      inbox.update!(agent_message_isolation_team_ids: [team.id])
      expect(found_by(colleague)).to include(conversation)
    end

    it 'lets an administrator find it whatever the list' do
      inbox.update!(agent_message_isolation_team_ids: [team.id])
      expect(found_by(admin)).to include(conversation)
    end

    it 'is a no-op when the flag is off, whatever the list says' do
      inbox.update!(agent_message_isolation: false, agent_message_isolation_team_ids: [team.id])
      expect(found_by(agent)).to include(conversation)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
