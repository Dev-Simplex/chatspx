# frozen_string_literal: true

# Nó `add_participant` do motor Flow: adiciona um agente como PARTICIPANTE da conversa (um
# "seguidor" que acompanha e é notificado — NÃO o responsável/assignee). Misturado no
# Flows::ActionService (padrão de Flows::Compliance/AiActions/SnoozeAction). Depende do host:
# @conversation, @account.
#
# Reusa o model REAL ConversationParticipant (o mesmo do painel de participantes da conversa),
# que já valida acesso à inbox (assignable_agents) e tem índice único (user_id, conversation_id).
# IDEMPOTENTE: find_or_create_by! não recria um participante existente, e a corrida perde para
# o índice único (RecordNotUnique → no-op). Anti-loop: não cria mensagem nem re-entra em
# flow/macro → não toca content_attributes.flow_id nem Current.flow_depth.
#
# action_params = [user_id]  (ou [{ user_id }])
module Flows::ParticipantAction
  private

  def add_participant(action_params)
    user_id = participant_user_id(action_params)
    return if user_id.blank?

    user = @account.users.find_by(id: user_id)
    return if user.blank?

    conversation = @conversation.reload
    # Guarda de acesso à inbox: sem acesso, o model recusaria (RecordInvalid). No-op silencioso
    # (paridade com assign_agent, que também ignora agente sem acesso à inbox).
    return if conversation.inbox.assignable_agents.exclude?(user)

    ConversationParticipant.find_or_create_by!(conversation: conversation, user: user)
  rescue ActiveRecord::RecordNotUnique
    nil # corrida perdida com um create concorrente — idempotente
  end

  def participant_user_id(action_params)
    first = Array(action_params).first
    first.is_a?(Hash) ? first.with_indifferent_access[:user_id] : first
  end
end
