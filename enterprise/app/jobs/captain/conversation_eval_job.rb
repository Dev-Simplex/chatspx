# Avalia UMA conversa e faz upsert do veredito. Idempotente: se já existe um eval
# com o mesmo nº de mensagens, é no-op (nada mudou desde a última avaliação).
class Captain::ConversationEvalJob < ApplicationJob
  queue_as :low

  def perform(conversation)
    account = conversation.account
    return unless Captain::ConversationEval.enabled_for?(account)

    message_count = countable_messages_count(conversation)
    return if message_count.zero?

    existing = Captain::ConversationEval.find_by(conversation_id: conversation.id)
    return if existing && existing.mensagens_avaliadas == message_count

    result = Captain::ConversationEvalService.new(
      account: account,
      conversation_display_id: conversation.display_id
    ).perform
    return if result[:error].present? || result[:verdict].blank?

    persist(conversation, account, result[:verdict], message_count, existing)
  end

  private

  def countable_messages_count(conversation)
    conversation.messages.where(message_type: %i[incoming outgoing]).where(private: false).count
  end

  def persist(conversation, account, verdict, message_count, existing)
    record = existing || Captain::ConversationEval.new(conversation_id: conversation.id)
    record.assign_attributes(
      account_id: account.id,
      captain_assistant_id: assistant_id_for(conversation),
      mensagens_avaliadas: message_count,
      avaliado_em: Time.now.utc,
      **verdict
    )
    record.save!
  end

  def assistant_id_for(conversation)
    conversation.assignee_agent_bot&.captain_assistant&.id ||
      conversation.messages.where(sender_type: 'Captain::Assistant').order(:created_at).last&.sender_id
  end
end
