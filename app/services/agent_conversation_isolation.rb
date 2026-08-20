# frozen_string_literal: true

# ISOLAMENTO DE ACESSO À CONVERSA POR AGENTE (flag agent_conversation_isolation por
# inbox). Mais forte que AgentMessageIsolation: lá esconde as BOLHAS de outros
# agentes; aqui BLOQUEIA abrir a conversa inteira (403 + tela de aviso "não está
# atribuída a você" + Solicitar). Viewer-dependent: depende de QUEM olha, então é
# reaplicado no guard de acesso e nas capacidades da aba "Em atendimento".
#
# Regra (inbox ON, agente NÃO-admin): acessa sse for o assignee OU a conversa não
# tiver dono HUMANO (assignee_id nil — cobre fila e IA, que vivem em
# assignee_agent_bot_id). Dono humano != ele -> bloqueado. Admin / AgentBot /
# contexto sem User sempre acessam.
#
# Decisão do dono: NÃO esconder da busca/lista/notificação — a conversa continua
# aparecendo; o isolamento age SÓ na abertura.
module AgentConversationIsolation
  module_function

  # Reusa a resolução de "quem restringir" do isolamento de mensagem: nil quando
  # NÃO se aplica (sem User, admin, ou conta inexistente); senão user.id.
  def viewer_restriction_id(user, account)
    AgentMessageIsolation.viewer_restriction_id(user, account)
  end

  # Dada 1 conversa + quem olha: o acesso está bloqueado para esse usuário?
  def hidden_from?(conversation, user, account = nil)
    return false unless conversation&.inbox&.agent_conversation_isolation

    scope = account || conversation.account
    restriction_id = viewer_restriction_id(user, scope)
    return false if restriction_id.nil? # admin / sem User -> acessa tudo
    # Supervisão de time (D2) vence o isolamento por agente: o supervisor abre a
    # conversa do time que supervisiona mesmo com a flag ON e dono humano diferente.
    return false if TeamSupervision.supervises?(user, conversation.team_id, scope)

    blocked_owner?(conversation, restriction_id)
  end

  # Dono humano diferente de quem olha = bloqueado. Sem dono humano (fila/IA) passa.
  def blocked_owner?(conversation, restriction_id)
    owner = conversation.assignee_id
    owner.present? && owner != restriction_id
  end

  # Mesma regra de `hidden_from?`, porém como CONDIÇÃO SQL — remove de uma relation
  # os registros de conversas isoladas de OUTRO agente. Serve às superfícies de
  # nível de conta que não passam pelo guard por-conversa (galeria de anexos, links,
  # download em massa). A relation precisa ter as tabelas `inboxes` e `conversations`
  # já unidas (JOIN). Admin / sem User -> relation intacta (acessam tudo).
  def exclude_hidden(relation, user, account)
    restriction_id = viewer_restriction_id(user, account)
    return relation if restriction_id.nil?

    # Espelho SQL da exceção de supervisão de `hidden_from?`: a conversa do time
    # supervisionado nunca é removida. Sem supervisão a cláusula some (no-op).
    supervised = TeamSupervision.team_ids(user, account)
    supervised_clause = supervised.any? ? ' OR conversations.team_id IN (:supervised)' : ''

    relation.where(
      'NOT (inboxes.agent_conversation_isolation AND conversations.assignee_id IS NOT NULL ' \
      "AND conversations.assignee_id <> :restriction_id)#{supervised_clause}",
      restriction_id: restriction_id, supervised: supervised
    )
  end
end
