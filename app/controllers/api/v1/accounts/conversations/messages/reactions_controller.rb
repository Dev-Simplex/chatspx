class Api::V1::Accounts::Conversations::Messages::ReactionsController < Api::V1::Accounts::Conversations::BaseController
  before_action :set_message
  before_action :set_reaction, only: [:destroy]

  def create
    @reaction = @message.reactions.find_or_initialize_by(
      user_type: current_user.class.name,
      user_id: current_user.id,
      account_id: @message.account_id
    )

    @reaction.emoji = permitted_params[:emoji]

    if @reaction.save
      render json: reaction_json(@reaction), status: :created
    else
      render json: { error: @reaction.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @reaction.destroy
    head :no_content
  end

  private

  def set_message
    @message = conversation.messages.find(params[:message_id])
  end

  def set_reaction
    @reaction = @message.reactions.find_by!(
      user_type: current_user.class.name,
      user_id: current_user.id
    )
  end

  def reaction_json(reaction)
    {
      id: reaction.id,
      message_id: reaction.message_id,
      emoji: reaction.emoji,
      user: {
        id: reaction.user_id,
        type: reaction.user_type,
        name: current_user.name,
        thumbnail: current_user.try(:avatar_url)
      },
      created_at: reaction.created_at
    }
  end

  def permitted_params
    params.require(:reaction).permit(:emoji)
  end
end



