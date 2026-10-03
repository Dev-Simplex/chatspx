# Entrega os webhooks de `message_created` de uma mensagem que esperava um video .MOV virar .mp4
# (Attachment#aguardando_mp4?). Volta a olhar a cada poucos segundos; pronto (ou desistiu de esperar),
# repassa ao WebhookListener, que entrega como sempre — agora com o link do .mp4.
class Webhooks::MessageCreatedAposMp4Job < ApplicationJob
  queue_as :medium

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank?
    return self.class.set(wait: SendReplyJob::MP4_RETRY_WAIT).perform_later(message_id) if message.aguardando_mp4?

    WebhookListener.instance.message_created(Events::Base.new(::Events::Types::MESSAGE_CREATED, Time.zone.now, message: message))
  end
end
