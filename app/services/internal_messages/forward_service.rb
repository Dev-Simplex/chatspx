# frozen_string_literal: true

# Chat interno — "Encaminhar": copia uma mensagem para outros canais do usuário (grupos/times de que
# ele participa) e para DMs com colegas da conta (criadas se ainda não existem). A cópia leva o texto,
# os anexos (o mesmo arquivo, sem novo upload) e o cartão de conversa compartilhada, com o selo
# content_attributes.forwarded. Quem encaminha precisa participar da conversa de origem.
class InternalMessages::ForwardService
  MAX_TARGETS = 20

  def initialize(message:, user:, channel_ids: [], user_ids: [])
    @message = message
    @user = user
    @channel_ids = Array(channel_ids).map(&:to_i).uniq
    @user_ids = Array(user_ids).map(&:to_i).uniq - [user.id]
  end

  def perform
    targets.map { |channel| forward_to(channel) }
  end

  def targets
    @targets ||= (member_channels + dm_channels).uniq(&:id).first(MAX_TARGETS)
  end

  private

  def account
    @message.internal_channel.account
  end

  def member_channels
    return [] if @channel_ids.blank?

    account.internal_channels.for_user(@user).where(id: @channel_ids).to_a
  end

  def dm_channels
    return [] if @user_ids.blank?

    account.users.where(id: @user_ids).filter_map do |other|
      InternalChannels::FindOrCreateDmService.new(account: account, user: @user, other_user: other).perform
    end
  end

  def forward_to(channel)
    InternalMessages::CreateService.new(
      channel: channel, user: @user, content: @message.content,
      attachments: @message.attachments.map { |attachment| attachment.blob.signed_id },
      shared_conversation_display_id: @message.shared_conversation&.display_id,
      content_attributes: { 'forwarded' => true }
    ).perform
  end
end
