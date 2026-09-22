# frozen_string_literal: true

# O ConversationBuilder REUSA a conversa que já existe do contato na caixa (regra
# do WAHA e do lock_to_single_conversation), e no reuso o assignee_id/team_id
# escolhidos no "Nova conversa" eram descartados — eles só valem em
# create_new_conversation. Resultado medido em campo: a mensagem do agente era
# gravada dentro do atendimento de OUTRO time (o `create` é
# CONVERSATIONLESS_ACTION, então nem o guard de time nem o isolamento por agente
# rodam ali) e, ao ser redirecionado, ele levava 403 na própria mensagem que
# acabara de mandar.
#
# Conversa órfã (sem dono e sem time) adota quem está iniciando; conversa de
# outro barra ANTES de a mensagem existir, com o mesmo 403 rico que o front já
# sabe ler.
module ReusedConversationAccessConcern
  extend ActiveSupport::Concern

  private

  def adopt_or_block_reused_conversation
    return if @conversation.previously_new_record?
    return if adopt_unowned_conversation
    return unless reused_conversation_blocked?

    render_conversation_access_blocked(I18n.t('conversations.compose.blocked_by_existing_attendance'))
  end

  def adopt_unowned_conversation
    return false if @conversation.assignee_id.present? || @conversation.team_id.present?

    attributes = { assignee_id: params[:assignee_id], team_id: params[:team_id] }.compact_blank
    return false if attributes.blank?

    @conversation.update!(attributes)
    true
  end

  def reused_conversation_blocked?
    team_access_blocked? || AgentConversationIsolation.hidden_from?(@conversation, Current.user, Current.account)
  end
end
