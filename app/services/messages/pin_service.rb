# frozen_string_literal: true

# Service to manage the collective pinned messages list of a conversation.
#
# Pin é coletivo (todos agents do account veem), portanto vive em
# conversations.additional_attributes.pinned_message_ids (array Integer, cap 3),
# diferente do pin per-user que vive em user_settings (PR B4).
#
# Anti-race-condition: usa jsonb_set + concat dentro de uma única instrução
# SQL row-level atomic. Dois clientes adicionando IDs distintos em paralelo
# não perdem entradas.
class Messages::PinService
  MAX_PINS = 3

  class ValidationError < StandardError; end
  class LimitReached < ValidationError; end
  class NotFound < StandardError; end

  def initialize(conversation:, message_id:)
    @conversation = conversation
    @message_id = Integer(message_id)
  rescue ArgumentError, TypeError
    raise NotFound, 'invalid_message_id'
  end

  # Adiciona @message_id ao array (idempotente). Retorna array atualizado.
  # Raises LimitReached if cap reached and id is not yet present.
  def add
    ensure_message_belongs_to_conversation!

    current = current_ids
    return current if current.include?(@message_id)
    raise LimitReached, "pin_limit_reached (max #{MAX_PINS})" if current.length >= MAX_PINS

    sql = <<~SQL.squish
      additional_attributes = jsonb_set(
        coalesce(additional_attributes, '{}'::jsonb),
        '{pinned_message_ids}',
        coalesce(additional_attributes->'pinned_message_ids', '[]'::jsonb) || ?::jsonb,
        true
      )
    SQL

    Conversation.where(id: @conversation.id).update_all([sql, [@message_id].to_json])
    @conversation.reload
    dispatch(Events::Types::CONVERSATION_PIN_ADDED)
    current_ids
  end

  # Remove @message_id do array (idempotente). Retorna array atualizado.
  def remove
    ensure_message_belongs_to_conversation!

    current = current_ids
    return current unless current.include?(@message_id)

    # Postgres jsonb does not have a native "remove value from array" operator,
    # so we recompute the filtered array in Ruby and overwrite the slot atomically.
    new_ids = current - [@message_id]

    sql = <<~SQL.squish
      additional_attributes = jsonb_set(
        coalesce(additional_attributes, '{}'::jsonb),
        '{pinned_message_ids}',
        ?::jsonb,
        true
      )
    SQL

    Conversation.where(id: @conversation.id).update_all([sql, new_ids.to_json])
    @conversation.reload
    dispatch(Events::Types::CONVERSATION_PIN_REMOVED)
    current_ids
  end

  def self.pinned_ids(conversation)
    Array((conversation.additional_attributes || {})['pinned_message_ids']).map(&:to_i)
  end

  private

  def current_ids
    self.class.pinned_ids(@conversation)
  end

  def ensure_message_belongs_to_conversation!
    return if @conversation.messages.exists?(id: @message_id)

    raise NotFound, 'message_not_found'
  end

  def dispatch(event_name)
    Rails.configuration.dispatcher.dispatch(
      event_name,
      Time.zone.now,
      conversation: @conversation,
      message_id: @message_id,
      pinned_message_ids: current_ids,
      performed_by: Current.executed_by
    )
  end
end
