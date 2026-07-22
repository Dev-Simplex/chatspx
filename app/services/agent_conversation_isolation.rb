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

    restriction_id = viewer_restriction_id(user, account || conversation.account)
    return false if restriction_id.nil? # admin / sem User -> acessa tudo

    owner = conversation.assignee_id
    owner.present? && owner != restriction_id
  end
end
