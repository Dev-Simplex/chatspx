# frozen_string_literal: true

# Isolamento de ACESSO à conversa por agente (flag agent_conversation_isolation por
# inbox). Complementa o isolamento por time (ConversationTeamAccessConcern): num
# inbox isolado, um agente só ABRE a conversa que é dele (ou sem dono humano). A
# ConversationPolicy aprova por acesso à CAIXA, então sem este guard
# `GET /conversations/:id` — e todos os sub-recursos (mensagens, etiquetas...) —
# devolveriam o conteúdo do colega. Vive num concern (before_action nos dois
# controllers) para fechar conversa + sub-recursos num lugar só e devolver um 403
# RICO — com o dono atual e o pedido pendente — para o front mostrar "não atribuída
# a você" + Solicitar, em vez de um 403 cru.
#
# NÃO esconde da busca/lista (decisão do dono): a conversa continua aparecendo, o
# bloqueio age só na abertura.
module AgentConversationAccessConcern
  extend ActiveSupport::Concern

  private

  def authorize_agent_conversation_access
    return unless AgentConversationIsolation.hidden_from?(@conversation, Current.user, Current.account)

    render_conversation_access_blocked
  end

  def render_conversation_access_blocked
    owner = @conversation.assignee
    existing = ConversationTakeoverRequest.find_by(
      conversation_id: @conversation.id, requester_id: Current.user&.id, status: :pending
    )
    render json: {
      error: I18n.t('conversations.agent_conversation_isolation.access_blocked'),
      error_code: 'conversation_access_blocked',
      meta: {
        current_assignee: owner && {
          id: owner.id,
          name: owner.try(:available_name) || owner.name,
          type: 'User'
        },
        team: @conversation.team && { id: @conversation.team.id, name: @conversation.team.name },
        existing_request: existing && { id: existing.id, status: existing.status, created_at: existing.created_at.to_i }
      }
    }, status: :forbidden
  end
end
