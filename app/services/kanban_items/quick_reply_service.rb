# frozen_string_literal: true

# KANBAN-P3-01: envia mensagem rápida do card (sem abrir conversa).
# Reaproveita Messages::MessageBuilder pra criar a mensagem na conversation
# vinculada ao KanbanItem. Validação de janela HSM 24h é feita upstream
# (controller), aqui só foca em construir e disparar via WAHA/Whatsapp.
#
# Returns: { message:, ok: true } ou levanta exceção.
class KanbanItems::QuickReplyService
  class WindowExpired < StandardError; end
  class ChannelOffline < StandardError; end

  attr_reader :item, :user, :content, :private_note

  def initialize(item:, user:, content:, private_note: false)
    @item = item
    @user = user
    @content = content.to_s.strip
    @private_note = ActiveModel::Type::Boolean.new.cast(private_note)
  end

  def perform
    raise ArgumentError, 'content is required' if content.blank?
    raise ArgumentError, 'content too long (max 1024)' if content.length > 1024

    message = build_message
    record_card_activity(message)
    message
  rescue Twilio::REST::RestError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    Rails.logger.tagged('kanban-quick-reply').error("channel error: #{e.message}")
    raise ChannelOffline, e.message
  end

  def self.call(**)
    new(**).perform
  end

  private

  def build_message
    conversation = item.conversation
    raise ArgumentError, 'conversation missing' if conversation.blank?

    params = ActionController::Parameters.new(
      content: content,
      message_type: 'outgoing',
      private: private_note,
      content_attributes: {}
    )
    Messages::MessageBuilder.new(user, conversation, params).perform
  end

  def record_card_activity(_message)
    item.touch # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError
    nil
  end
end
