class Public::Api::V1::NpsSurveyController < PublicController
  before_action :set_conversation
  before_action :set_message

  def show; end

  def update
    render json: { error: 'You cannot update the NPS survey after 14 days' }, status: :unprocessable_entity and return if check_nps_locked

    score = message_update_params.dig(:message, :submitted_values, :nps_response, :score)
    comment = message_update_params.dig(:message, :submitted_values, :nps_response, :comment)

    return render json: { error: 'Invalid score' }, status: :unprocessable_entity unless valid_score?(score)

    @message.update!(message_update_params[:message])

    # Process the response
    NpsSurveys::ResponseBuilder.new(message: @message.reload).perform

    render json: { message: 'NPS response recorded successfully' }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_conversation
    return if params[:id].blank?

    @conversation = Conversation.find_by!(uuid: params[:id])
  end

  def set_message
    @message = @conversation.messages.find_by!(content_type: 'input_nps')
  end

  def message_update_params
    params.permit(message: [{ submitted_values: [{ nps_response: [:score, :comment] }] }])
  end

  def check_nps_locked
    (Time.zone.now.to_date - @message.created_at.to_date).to_i > 14
  end

  def valid_score?(score)
    return false if score.blank?

    score_int = score.to_i
    score_int >= 0 && score_int <= 10
  end
end
