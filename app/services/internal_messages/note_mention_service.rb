# frozen_string_literal: true

# Menção numa NOTA PRIVADA de conversa de cliente: além do aviso de sempre (sino/push), quem
# escreveu a nota manda na DM do chat interno, com o cartão da conversa e o trecho da nota, para
# o assunto continuar no chat. Quem foi mencionado já ganhou o push da menção (Notification tipo
# 4), então esta mensagem não dispara outro push (só o controller do chat dispara).
#
# Reprocessar a mesma nota (job repetido, evento reenviado) não duplica: se a DM já tem, depois da
# nota, a mensagem do mesmo autor com a mesma conversa e o mesmo texto, nada é criado.
class InternalMessages::NoteMentionService
  EXCERPT_LIMIT = 200

  pattr_initialize [:message!, :user_ids!]

  def perform
    return unless author.is_a?(User) && account.feature_enabled?('internal_chat')

    User.where(id: user_ids).where.not(id: author.id).find_each { |user| post_to(user) }
  end

  private

  delegate :account, :conversation, to: :message

  def author
    message.sender
  end

  def post_to(user)
    channel = InternalChannels::FindOrCreateDmService.new(account: account, user: author, other_user: user).perform
    return if channel.blank?

    channel.with_lock do
      create_message(channel) unless already_posted?(channel)
    end
  end

  def already_posted?(channel)
    channel.messages.where(user_id: author.id, shared_conversation_id: conversation.id, content: text)
           .where('internal_messages.created_at >= ?', message.created_at).exists?
  end

  def create_message(channel)
    InternalMessages::CreateService.new(
      channel: channel, user: author, content: text, shared_conversation_display_id: conversation.display_id
    ).perform
  end

  def text
    @text ||= I18n.with_locale(account.locale || I18n.default_locale) do
      I18n.t('internal_chat_push.note_mention', name: author.name, id: conversation.display_id, excerpt: excerpt)
    end
  end

  # "[@Ana](mention://user/3/Ana)" vira "@Ana"; o resto do markdown da nota fica como está.
  def excerpt
    message.content.to_s.gsub(%r{\[(@[^\]]+)\]\(mention://(?:user|team)/\d+/[^)]*\)}, '\1').squish.truncate(EXCERPT_LIMIT)
  end
end
