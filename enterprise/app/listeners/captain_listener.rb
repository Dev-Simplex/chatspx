class CaptainListener < BaseListener
  include ::Events::Types

  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    assistant = assistant_for(conversation)
    return unless assistant
    return unless conversation.inbox.captain_active?

    Captain::Llm::ContactNotesService.new(assistant, conversation).generate_and_update_notes if assistant.config['feature_memory'].present?
    Captain::Llm::ConversationFaqService.new(assistant, conversation).generate_and_deduplicate if assistant.config['feature_faq'].present?
  end

  private

  # Dono atual (espelho) ou, pós-handoff (bot já desatribuído por A2e), o participante:
  # última mensagem com sender Captain::Assistant.
  def assistant_for(conversation)
    conversation.assignee_agent_bot&.captain_assistant ||
      conversation.messages.where(sender_type: 'Captain::Assistant').order(:created_at).last&.sender
  end
end
