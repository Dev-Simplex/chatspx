class Api::V1::Accounts::Conversations::Messages::ReactionsController < Api::V1::Accounts::Conversations::BaseController
  ALLOWED_EMOJIS = %w[👍 ❤️ 😂 😮 😢 🙏 👏 🔥].freeze

  def create
    emoji = params[:emoji].to_s
    return render(json: { error: 'invalid_emoji' }, status: :unprocessable_entity) unless ALLOWED_EMOJIS.include?(emoji)

    user_id = Current.user&.id
    return render(json: { error: 'unauthenticated' }, status: :unauthorized) if user_id.blank?

    reactions = toggle_reaction(message.additional_attributes['reactions'] || {}, user_id.to_s, emoji)
    message.additional_attributes['reactions'] = reactions
    message.save!
    notify_message_updated
    render json: { reactions: reactions }
  end

  private

  def message
    @message ||= @conversation.messages.find(params[:message_id])
  end

  def toggle_reaction(reactions, user_key, emoji)
    reactions = reactions.dup
    user_emojis = Array(reactions[user_key])
    user_emojis = user_emojis.include?(emoji) ? user_emojis - [emoji] : user_emojis + [emoji]
    user_emojis.empty? ? reactions.tap { |r| r.delete(user_key) } : reactions.merge(user_key => user_emojis)
  end

  def notify_message_updated
    Rails.configuration.dispatcher.dispatch(
      ::Events::Types::MESSAGE_UPDATED,
      Time.zone.now,
      message: message,
      performed_by: Current.user
    )
  end
end
