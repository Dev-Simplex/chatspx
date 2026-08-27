# frozen_string_literal: true

# Centraliza a regra de ISOLAMENTO DE MENSAGENS POR AGENTE (flag agent_message_isolation
# por inbox). Diferente do team isolation — que vive na association conversation.messages
# porque depende só da conversa — este isolamento depende de QUEM olha (Current.user),
# então precisa ser reaplicado em CADA ponto de leitura de mensagens fora do MessageFinder
# (preview da lista, histórico do contato, busca). Regra: com a flag ON num inbox, um
# agente NÃO-admin só vê mensagens com agent_id NULL (públicas) ou agent_id == ele mesmo.
# Admin e contextos sem User (jobs/widget/public API) veem tudo.
#
# ESCOPO POR TIME: a flag liga a regra na caixa, mas quem decide se ela alcança uma
# conversa é `Inbox#isolation_applies_to_team?` — a regra mora lá, num lugar só. Conversa
# SEM time nunca é isolada; lista de times vazia = todos os times (comportamento histórico).
# Nas listagens (SQL cru) o espelho da mesma regra é `Inbox.isolation_applies_sql`.
module AgentMessageIsolation
  module_function

  # ID do agente para restringir, ou nil quando NÃO se aplica restrição (sem User, admin,
  # ou conta inexistente). NÃO checa a flag do inbox nem o escopo por time — o caller decide
  # por-LINHA, pois uma listagem mistura inboxes com e sem isolamento e conversas de times
  # dentro e fora do escopo (esse recorte vai no SQL, via `Inbox.isolation_applies_sql`).
  def viewer_restriction_id(user, account)
    return nil unless user.is_a?(User)

    account_id = account.is_a?(Account) ? account.id : account
    return nil if account_id.blank?
    return nil if user.account_users.find_by(account_id: account_id)&.administrator?

    user.id
  end

  # Restrição para um único inbox (MessageFinder / conversa única): só quando a regra
  # ALCANÇA o time da conversa — flag ON + conversa COM time + time dentro da lista
  # escolhida na caixa (lista vazia = todos os times = comportamento histórico).
  # `team_id` é OBRIGATÓRIO de propósito: sem ele o caller não tem como decidir, e um
  # default silencioso escolheria o lado errado em algum dos dois sentidos.
  def restriction_id_for_inbox(inbox, user, account, team_id)
    return nil unless inbox&.isolation_applies_to_team?(:agent_message_isolation, team_id)

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
