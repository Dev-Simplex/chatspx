class Captain::Conversation::DebouncedResponseJob < ApplicationJob
  queue_as :default

  def perform(conversation, assistant, token)
    key = format(Redis::RedisKeys::CAPTAIN_DEBOUNCE_TOKEN,
                 conversation_id: conversation.id,
                 assistant_id: assistant.id)

    stored_token = Redis::Alfred.get(key)
    return unless stored_token == token

    Redis::Alfred.delete(key)

    # Token Redis NÃO protege contra troca de dono (chave por conversa+assistant). O
    # re-check do ResponseBuilderJob é a autoridade; aqui só evitamos log 'debounce_fire' falso.
    return unless conversation.assignee_agent_bot&.captain_assistant_id == assistant.id

    Captain::AssistantLog.create!(
      captain_assistant: assistant,
      conversation: conversation,
      event_type: 'debounce_fire'
    )

    Captain::Conversation::ResponseBuilderJob.perform_now(conversation, assistant)
  end
end
