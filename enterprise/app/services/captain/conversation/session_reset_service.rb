# Para contas opt-in, `resolved` vira uma fronteira dura de atendimento sem apagar
# a conversa. O histórico continua no SPX, mas a próxima reentrada começa sem dono
# e sem estado transitório, como aconteceria após destruir e recriar a conversa.
class Captain::Conversation::SessionResetService
  BOUNDARY_KEY = 'captain_session_boundary_message_id'.freeze
  SEQUENCE_KEY = 'captain_session_sequence'.freeze
  PENDING_REENTRY_KEY = 'captain_session_pending_reentry'.freeze
  ENABLED_KEY = 'captain_reset_session_on_resolve'.freeze

  pattr_initialize [:conversation!]

  class << self
    def enabled_for_resolve?(conversation)
      conversation.status_changed? && conversation.resolved? && enabled_for?(conversation)
    end

    def enabled_for?(conversation)
      boolean.cast(conversation.account.custom_attributes&.dig(ENABLED_KEY))
    end

    def boundary_message_id(conversation)
      (conversation.custom_attributes || {})[BOUNDARY_KEY].to_i
    end

    def pending_reentry?(conversation)
      boolean.cast((conversation.custom_attributes || {})[PENDING_REENTRY_KEY])
    end

    private

    def boolean
      @boolean ||= ActiveModel::Type::Boolean.new
    end
  end

  def perform
    previous_attributes = conversation.custom_attributes || {}
    conversation.custom_attributes = {
      BOUNDARY_KEY => conversation.all_messages.maximum(:id).to_i,
      SEQUENCE_KEY => previous_attributes[SEQUENCE_KEY].to_i + 1,
      PENDING_REENTRY_KEY => true
    }
    conversation.assignee_id = nil
    conversation.assignee_agent_bot_id = nil
  end
end
