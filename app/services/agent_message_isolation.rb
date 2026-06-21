# frozen_string_literal: true

# Centraliza a regra de ISOLAMENTO DE MENSAGENS POR AGENTE (flag agent_message_isolation
# por inbox). Diferente do team isolation — que vive na association conversation.messages
# porque depende só da conversa — este isolamento depende de QUEM olha (Current.user),
# então precisa ser reaplicado em CADA ponto de leitura de mensagens fora do MessageFinder
# (preview da lista, histórico do contato, busca). Regra: com a flag ON num inbox, um
# agente NÃO-admin só vê mensagens com agent_id NULL (públicas) ou agent_id == ele mesmo.
# Admin e contextos sem User (jobs/widget/public API) veem tudo.
module AgentMessageIsolation
  module_function

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

  # Restrição para um único inbox (MessageFinder / conversa única): só quando a flag está ON.
  def restriction_id_for_inbox(inbox, user, account)
    return nil unless inbox&.agent_message_isolation

    viewer_restriction_id(user, account)
  end

  # Aplica o filtro a um scope de Message já restrito a um único inbox isolado.
  def filter_messages(scope, restriction_id)
    return scope if restriction_id.nil?

    scope.where('messages.agent_id IS NULL OR messages.agent_id = ?', restriction_id)
  end
end
