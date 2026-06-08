# frozen_string_literal: true

# Wisper publish/subscribe — listeners globais para eventos de domínio.
# Conversation publica eventos (conversation_created, conversation_status_changed,
# conversation_team_changed) e listeners reagem sem acoplamento.
Rails.application.config.to_prepare do
  Wisper.subscribe(KanbanItems::ConversationListener.new)
end
