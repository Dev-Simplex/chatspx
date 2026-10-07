# frozen_string_literal: true

# Chat interno — decide um pedido (message_type request): aprovar/recusar uma
# aprovação, ou "Eu ajudo" num pedido de ajuda. Mesmo molde do
# ConversationTakeoverRequest (pendente → respondido, com quem e quando), mas o
# pedido mora no próprio balão. O lock impede duas decisões ao mesmo tempo; o
# broadcast atualiza o cartão de todos e leva o aviso (`notice`) a quem pediu.
class InternalMessages::DecideService
  class NotAllowed < StandardError; end
  class AlreadyDecided < StandardError; end

  DECISIONS = { 'approval' => %w[approve deny], 'help' => %w[help] }.freeze
  STATUS = { 'approve' => 'approved', 'deny' => 'denied', 'help' => 'taken' }.freeze

  def initialize(message:, user:, decision:, reason: nil)
    @message = message
    @user = user
    @decision = decision.to_s
    @reason = reason.to_s.strip.truncate(280).presence
  end

  def perform
    @message.with_lock do
      raise AlreadyDecided if @message.message_type_request? && !@message.request_pending?
      raise NotAllowed unless @message.can_decide?(@user) && DECISIONS[@message.request_data['kind']]&.include?(@decision)

      @message.update!(content_attributes: @message.content_attributes.merge('request' => decided_request))
    end
    InternalMessages::BroadcastService.updated(@message, notice: notice)
    @message
  end

  private

  def decided_request
    @message.request_data.merge(
      'status' => STATUS[@decision],
      'decided_by_id' => @user.id,
      'decided_by_name' => @user.name,
      'decided_at' => Time.current.to_i,
      'reason' => (@reason if @decision == 'deny')
    ).compact
  end

  # Texto do aviso a quem pediu, já no idioma da conta (o nome de quem decidiu
  # vai no título do aviso).
  def notice
    I18n.with_locale(@message.internal_channel.account.locale || I18n.default_locale) do
      I18n.t("internal_chat.request_notice.#{STATUS[@decision]}", title: @message.content)
    end
  end
end
