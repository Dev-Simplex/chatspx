# frozen_string_literal: true

# Gate "assumir para responder": com a flag ligada, só o dono da conversa responde o cliente.
#
# Mora num concern porque toda porta que escreve resposta precisa da MESMA régua — mensagem,
# localização, contato e, a partir da C8, produto do catálogo. Um caminho novo que esqueça o gate
# não dá erro: ele simplesmente vira o furo por onde qualquer agente volta a responder conversa
# alheia, e ninguém percebe até o cliente reclamar.
#
# Controller-level de propósito: macros, campanhas, agendadas e IA criam Message por job e nunca
# passam por aqui; o chat interno tem controller próprio, fora do gate.
module ReplyAssignmentGateConcern
  extend ActiveSupport::Concern

  private

  def enforce_reply_assignment_gate
    return unless Current.account.reply_assignment_gate_enabled? # helper da Fase C (C-F0)

    user = Current.user || @resource
    return unless user.is_a?(User) # bot-token (AgentBot) e nil ficam fora
    return if fora_do_gate?
    return if @conversation.assignee_id == user.id

    render_assignment_required
  end

  # Três casos que nunca foram "resposta de agente" e por isso não passam pelo gate.
  def fora_do_gate?
    params[:private].to_s == 'true' ||        # nota privada — padrão do fork
      params[:source_id].present? ||          # echo do app WAHA externo (User real id=1)
      params[:message_type].to_s == 'incoming' # incoming via API não é resposta de agente
  end

  def render_assignment_required
    assignee = @conversation.assigned_entity              # assignee_agent_bot || assignee (Fase A)
    render json: {
      error: I18n.t('conversations.reply_assignment_gate.assignment_required'),
      error_code: 'assignment_required',
      meta: {
        current_assignee: assignee && {
          id: assignee.id,
          name: assignee.try(:available_name) || assignee.name,
          type: @conversation.assignee_type               # 'AgentBot' | 'User' | nil
        },
        team: @conversation.team && { id: @conversation.team.id, name: @conversation.team.name }
      }
    }, status: :unprocessable_entity
  end
end
