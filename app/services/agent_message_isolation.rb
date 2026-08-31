# frozen_string_literal: true

# Centraliza a regra de ISOLAMENTO DE MENSAGENS POR AGENTE (flag agent_message_isolation
# por inbox). Diferente do team isolation — que vive na association conversation.messages
# porque depende só da conversa — este isolamento depende de QUEM olha (Current.user),
# então precisa ser reaplicado em CADA ponto de leitura de mensagens fora do MessageFinder
# (preview da lista, histórico do contato, busca). Regra: com a flag ON num inbox, um
# agente NÃO-admin só vê mensagens com agent_id NULL (públicas) ou agent_id == ele mesmo.
#
# A regra tem DOIS eixos ortogonais, e os dois precisam passar para o isolamento valer:
#
#   1. ALCANCE (por TIME): a flag liga a regra na caixa, mas quem decide se ela alcança
#      uma conversa é `Inbox#isolation_applies_to_team?` — flag ON + conversa COM time +
#      time dentro da lista escolhida na caixa (lista vazia = todos os times = comportamento
#      histórico). Nas listagens (SQL cru) o espelho é `Inbox.isolation_applies_sql`.
#   2. ISENÇÃO (por AGENTE): mesmo alcançada, a regra não vale para quem está em
#      `inbox_isolation_exemptions` daquela caixa (ver InboxIsolationExemption).
#
# Ou seja: isola se o escopo por time ALCANÇA **E** o agente NÃO está isento.
#
# São QUATRO isentos que convivem e não se substituem: administrador (conta inteira),
# supervisor de time (as conversas dos times que supervisiona), a exceção por caixa, e a
# conversa cujo time está fora da lista de escopo. Admin e contextos sem User
# (jobs/widget/public API) veem tudo.
module AgentMessageIsolation
  ISOLATION_TYPE = 'agent_message'

  module_function

  # true quando o usuário é EXCEÇÃO do isolamento por agente NESTA caixa: ele volta a ver
  # as mensagens dos outros ali, e só ali. false sem User (job/widget/API pública) — o
  # contexto sem viewer nunca é exceção, ele já é isento por outro caminho.
  def exempt?(user, inbox)
    return false unless user.is_a?(User)
    return false if inbox.blank?

    user.isolation_exempt_inbox_ids_for(inbox.account_id, ISOLATION_TYPE).include?(inbox.id)
  end

  # Ids das caixas isentas para este usuário na conta. É a versão para as listagens que
  # MISTURAM caixas (lista de conversas, busca): lá a flag do inbox e o escopo por time já
  # entram no SQL por linha, então a exceção entra do mesmo jeito — igualzinho ao que a
  # supervisão de time faz com `supervised_team_ids` nos mesmos três pontos.
  def exempt_inbox_ids(user, account)
    return [] unless user.is_a?(User)

    account_id = account.is_a?(Account) ? account.id : account
    return [] if account_id.blank?

    user.isolation_exempt_inbox_ids_for(account_id, ISOLATION_TYPE)
  end

  # ID do agente para restringir, ou nil quando NÃO se aplica restrição (sem User, admin,
  # ou conta inexistente). NÃO checa a flag do inbox, nem o escopo por time, nem a isenção
  # — o caller decide por-LINHA, pois uma listagem mistura inboxes com e sem isolamento e
  # conversas de times dentro e fora do escopo (esse recorte vai no SQL, via
  # `Inbox.isolation_applies_sql` mais `exempt_inbox_ids`).
  def viewer_restriction_id(user, account)
    return nil unless user.is_a?(User)

    account_id = account.is_a?(Account) ? account.id : account
    return nil if account_id.blank?
    return nil if user.account_users.find_by(account_id: account_id)&.administrator?

    user.id
  end

  # Restrição para um único inbox (MessageFinder / conversa única): só quando a regra
  # ALCANÇA o time da conversa E o usuário NÃO é exceção nesta caixa.
  # `team_id` é OBRIGATÓRIO de propósito: sem ele o caller não tem como decidir o alcance,
  # e um default silencioso escolheria o lado errado em algum dos dois sentidos.
  def restriction_id_for_inbox(inbox, user, account, team_id)
    return nil unless inbox&.isolation_applies_to_team?(:agent_message_isolation, team_id)
    return nil if exempt?(user, inbox)

    viewer_restriction_id(user, account)
  end

  # Idem, porém ciente da SUPERVISÃO DE TIME (D2): o supervisor vê TODAS as bolhas
  # das conversas do time que supervisiona, mesmo com a flag ON. Prefira esta versão
  # sempre que a conversa for conhecida — `restriction_id_for_inbox` fica para os
  # pontos que só têm o inbox em mãos.
  def restriction_id_for_conversation(conversation, user, account = nil)
    return nil if conversation.nil?

    scope = account || conversation.account_id
    return nil if TeamSupervision.supervises?(user, conversation.team_id, scope)

    restriction_id_for_inbox(conversation.inbox, user, scope, conversation.team_id)
  end

  # Aplica o filtro a um scope de Message já restrito a um único inbox isolado.
  def filter_messages(scope, restriction_id)
    return scope if restriction_id.nil?

    scope.where('messages.agent_id IS NULL OR messages.agent_id = ?', restriction_id)
  end
end
