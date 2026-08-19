# frozen_string_literal: true

# Centraliza a regra de ISOLAMENTO DE MENSAGENS POR AGENTE (flag agent_message_isolation
# por inbox). Diferente do team isolation — que vive na association conversation.messages
# porque depende só da conversa — este isolamento depende de QUEM olha (Current.user),
# então precisa ser reaplicado em CADA ponto de leitura de mensagens fora do MessageFinder
# (preview da lista, histórico do contato, busca). Regra: com a flag ON num inbox, um
# agente NÃO-admin só vê mensagens com agent_id NULL (públicas) ou agent_id == ele mesmo.
# Admin e contextos sem User (jobs/widget/public API) veem tudo, e desde a task de
# EXCEÇÕES POR AGENTE também quem estiver na tabela inbox_isolation_exemptions daquela
# caixa. São TRÊS isentos que convivem e não se substituem: administrador (conta inteira),
# supervisor de time (as conversas dos times que supervisiona) e a exceção por caixa.
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
  # MISTURAM caixas (lista de conversas, busca): lá a flag do inbox já entra no SQL por
  # linha, então a exceção entra do mesmo jeito — igualzinho ao que a supervisão de time
  # faz com `supervised_team_ids` nos mesmos três pontos.
  def exempt_inbox_ids(user, account)
    return [] unless user.is_a?(User)

    account_id = account.is_a?(Account) ? account.id : account
    return [] if account_id.blank?

    user.isolation_exempt_inbox_ids_for(account_id, ISOLATION_TYPE)
  end

  # ID do agente para restringir, ou nil quando NÃO se aplica restrição (sem User, admin,
  # ou conta inexistente). NÃO checa a flag do inbox — o caller decide por-inbox, pois uma
  # listagem pode misturar inboxes com e sem isolamento (filtro vai no SQL/scope por linha).
  def viewer_restriction_id(user, account)
    return nil unless user.is_a?(User)

    account_id = account.is_a?(Account) ? account.id : account
    return nil if account_id.blank?
    return nil if user.account_users.find_by(account_id: account_id)&.administrator?

    user.id
  end

  # Restrição para um único inbox (MessageFinder / conversa única): só quando a flag está ON
  # e o usuário NÃO é exceção nesta caixa.
  def restriction_id_for_inbox(inbox, user, account)
    return nil unless inbox&.agent_message_isolation
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

    restriction_id_for_inbox(conversation.inbox, user, scope)
  end

  # Aplica o filtro a um scope de Message já restrito a um único inbox isolado.
  def filter_messages(scope, restriction_id)
    return scope if restriction_id.nil?

    scope.where('messages.agent_id IS NULL OR messages.agent_id = ?', restriction_id)
  end
end
