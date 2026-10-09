# MIDIA-01: video que o atendente manda pelo WhatsApp acima de 16 MB (o limite do WhatsApp para video) sai como
# DOCUMENTO, ate o teto de 100 MB. Regra unica para o canal oficial (WhatsappCloudService#resolve_media_type), para
# o WAHA (WebhookListener + Waha::OutboundSpecialMessageService mandam pelo /api/sendFile) e para a tela (o balao
# mostra "Enviado como documento").
module AttachmentEnvioComoDocumento
  extend ActiveSupport::Concern

  WHATSAPP_VIDEO_LIMIT_MB = 16

  def vai_como_documento?
    video_acima_do_limite? && saindo_pelo_whatsapp?
  end

  private

  def video_acima_do_limite?
    file_type.to_s == 'video' && file.attached? && file.byte_size > WHATSAPP_VIDEO_LIMIT_MB.megabytes
  end

  # Enviado pelo painel numa caixa WhatsApp (oficial ou WAHA). O eco do celular ja foi pelo WhatsApp.
  def saindo_pelo_whatsapp?
    return false unless message&.outgoing? && !message.already_through_whatsapp?

    inbox = message.inbox
    inbox.channel_type == 'Channel::Whatsapp' || (inbox.channel_type == 'Channel::Api' && inbox.waha_session_name.present?)
  end
end
