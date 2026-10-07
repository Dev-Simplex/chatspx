# frozen_string_literal: true

# Chat interno — aviso fora da aba: push do navegador (o mesmo web push do sino) para quem
# precisa ser avisado mesmo com o ChatSPX fechado. Só DM e menção; mensagem de grupo/time sem
# menção fica no aviso da página. Respeita "Silenciar conversa" (menção ainda avisa, como na
# página) e o "Notificações na área de trabalho" desligado no cabeçalho do chat.
#
# Lê as duas preferências do ui_settings do usuário, onde a página já as guarda: assim o
# servidor e a página decidem igual sem coluna nova.
#
# A tag é por canal e igual à da notificação da página (helper/internalChatNotify.js): com a
# aba aberta em segundo plano as duas chegam e o navegador mostra uma só.
class InternalMessages::PushService
  BODY_LIMIT = 140

  def initialize(message)
    @message = message
    @channel = message.internal_channel
    @author = message.user
  end

  def perform
    return unless VapidService.public_key

    recipients.each { |user| deliver(user) }
  end

  def recipients
    ids = @channel.direct? ? @channel.members.pluck(:user_id) : []
    ids = (ids | mentioned_ids) - [@author.id]
    User.where(id: ids).select { |user| wants_push?(user) }
  end

  private

  def mentioned_ids
    Array(@message.mentioned_user_ids).map(&:to_i)
  end

  def wants_push?(user)
    settings = user.ui_settings || {}
    return false if settings['internal_chat_desktop_notifications'] == false
    return true if mentioned_ids.include?(user.id)

    Array(settings['internal_chat_muted_channel_ids']).map(&:to_i).exclude?(@channel.id)
  end

  def deliver(user)
    payload = JSON.generate(push_message(user))
    user.notification_subscriptions.browser_push.each { |subscription| send_push(subscription, payload) }
  end

  def send_push(subscription, payload)
    attrs = subscription.subscription_attributes
    WebPush.payload_send(
      message: payload, endpoint: attrs['endpoint'], p256dh: attrs['p256dh'], auth: attrs['auth'],
      vapid: { subject: url, public_key: VapidService.public_key, private_key: VapidService.private_key },
      ssl_timeout: 5, open_timeout: 5, read_timeout: 5
    )
    Rails.logger.info("Internal chat push sent to user #{subscription.user_id} for internal message #{@message.id}")
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, WebPush::Unauthorized
    subscription.destroy!
  rescue StandardError => e
    Rails.logger.warn("Internal chat push failed for user #{subscription.user_id}: #{e.class} #{e.message}")
  end

  def push_message(user)
    I18n.with_locale(@channel.account.locale || I18n.default_locale) do
      { title: title_for(user), body: body, tag: "internal-chat-#{@channel.id}", url: url }
    end
  end

  def title_for(user)
    return @author.name if @channel.direct?

    I18n.t('internal_chat_push.mention_title', name: @author.name, channel: @channel.name) if mentioned_ids.include?(user.id)
  end

  def body
    return @message.content.to_s.squish.truncate(BODY_LIMIT) if @message.content.present?
    return I18n.t('internal_chat_push.shared_conversation', id: @message.shared_conversation.display_id) if @message.shared_conversation

    I18n.t('internal_chat_push.attachment')
  end

  def url
    "#{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{@channel.account_id}/internal-chat?channel=#{@channel.id}"
  end
end
