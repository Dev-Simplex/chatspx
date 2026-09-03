# Persisted message reactions controller (PR B1).
#
# Replaces the previous in-place `additional_attributes['reactions']` toggling
# with rows on the `message_reactions` table. The DB has a unique index on
# (message_id, user_type, user_id) so a single user can only have ONE reaction
# per message at a time — re-reacting with a different emoji UPDATEs the row,
# re-reacting with the same emoji is a no-op (idempotent).
#
# Authorization:
#   - index/create are allowed for any agent with access to the conversation
#     (the parent BaseController already authorizes the conversation).
#   - destroy requires owner or administrator (see MessageReactionPolicy).
class Api::V1::Accounts::Conversations::Messages::ReactionsController < Api::V1::Accounts::Conversations::BaseController
  ALLOWED_EMOJIS = %w[👍 ❤️ 😂 😮 😢 🙏 👏 🔥].freeze
  EMOJI_MAX_LENGTH = 10

  before_action :ensure_user!
  before_action :ensure_message!

  def index
    @reactions = message.reactions.order(:created_at).to_a
  end

  def create # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    emoji = params[:emoji].to_s
    return render_invalid_emoji unless valid_emoji?(emoji)

    user_type, user_id = current_actor_tuple
    existing = message.reactions.find_by(user_type: user_type, user_id: user_id)

    if existing
      return render_existing(existing) if existing.emoji == emoji

      # O emoji ANTERIOR vai como valor, nao como registro: `existing.dup` produzia um
      # MessageReaction NOVO e sem id, e o ActiveJob estourava
      # `SerializationError: Unable to serialize MessageReaction without an id` ao enfileirar o
      # evento — 500 em toda troca de emoji.
      emoji_anterior = existing.emoji
      existing.update!(emoji: emoji)
      @reaction = existing
      dispatch_removed(existing, emoji: emoji_anterior)
      dispatch_added(@reaction)
      render :create, status: :ok
    else
      @reaction = message.reactions.create!(
        account_id: message.account_id,
        emoji: emoji,
        user_type: user_type,
        user_id: user_id
      )
      dispatch_added(@reaction)
      render :create, status: :created
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    reaction = message.reactions.find(params[:id])
    authorize reaction, :destroy?
    reaction.destroy!
    dispatch_removed(reaction)
    head :no_content
  rescue Pundit::NotAuthorizedError
    render json: { error: 'forbidden' }, status: :forbidden
  end

  private

  def message
    @message ||= @conversation.messages.find(params[:message_id])
  end

  def ensure_message!
    message
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'message_not_found' }, status: :not_found
  end

  def ensure_user!
    return if Current.user.present? || @resource.present?

    render json: { error: 'unauthenticated' }, status: :unauthorized
  end

  def valid_emoji?(emoji)
    return false if emoji.blank?
    return false if emoji.length > EMOJI_MAX_LENGTH

    ALLOWED_EMOJIS.include?(emoji)
  end

  def current_actor_tuple
    if Current.user.present?
      ['User', Current.user.id]
    else
      ['Contact', @resource.id]
    end
  end

  def render_invalid_emoji
    render json: { error: 'invalid_emoji' }, status: :unprocessable_entity
  end

  def render_existing(reaction)
    @reaction = reaction
    render :create, status: :ok
  end

  def dispatch_added(reaction)
    Rails.configuration.dispatcher.dispatch(
      ::Events::Types::MESSAGE_REACTION_ADDED,
      Time.zone.now,
      message: message,
      reaction: reaction,
      performed_by: Current.user
    )
  end

  # O evento de REMOCAO carrega VALORES, nunca o registro. Os dois caminhos que o disparam
  # tornam o registro impróprio para serializar:
  #
  # - `destroy`: a linha ja foi APAGADA quando o evento sai. O ActiveJob serializa por GlobalID
  #   e o job estouraria `DeserializationError` ao tentar reidratar o que nao existe mais;
  # - troca de emoji: o registro sobrevive, mas com o emoji NOVO — e o assinante precisa
  #   justamente do antigo para tirar da tela a reacao certa.
  #
  # `ActionCableListener#message_reaction_removed` so usa atributos escalares, entao passar os
  # valores nao perde nada.
  def dispatch_removed(reaction, emoji: nil)
    Rails.configuration.dispatcher.dispatch(
      ::Events::Types::MESSAGE_REACTION_REMOVED,
      Time.zone.now,
      message: message,
      reaction_id: reaction.id,
      emoji: emoji || reaction.emoji,
      user_id: reaction.user_id,
      user_type: reaction.user_type,
      performed_by: Current.user
    )
  end
end
