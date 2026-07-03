# frozen_string_literal: true

# Follow-up drip (Módulo A, Fase A2) — enroll / list / cancel a conversation's
# sequence enrollments. Agent-level (handling a conversation), unlike authoring.
# conversation_id is the conversation's DB id (the dashboard passes currentChat.id).
class Api::V1::Accounts::MessageSequenceEnrollmentsController < Api::V1::Accounts::BaseController
  before_action :enrollment, only: [:destroy]
  before_action :check_authorization

  def index
    @enrollments = MessageSequenceEnrollment
                   .joins(:message_sequence)
                   .where(message_sequences: { account_id: Current.account.id })
                   .where(conversation_id: params[:conversation_id])
                   .includes(:message_sequence)
                   .order(created_at: :desc)
  end

  def create
    sequence = Current.account.message_sequences.find(params[:message_sequence_id])
    conversation = Current.account.conversations.find(params[:conversation_id])
    @enrollment = MessageSequences::EnrollService.new(
      sequence: sequence, conversation: conversation, enrolled_by: Current.user
    ).perform

    return render :show, status: :created if @enrollment.present?

    render json: { error: 'Conversation is already enrolled or the sequence has no steps' },
           status: :unprocessable_entity
  end

  def destroy
    @enrollment.cancelled!
    head :ok
  end

  private

  def enrollment
    @enrollment ||= MessageSequenceEnrollment
                    .joins(:message_sequence)
                    .where(message_sequences: { account_id: Current.account.id })
                    .find(params[:id])
  end

  def check_authorization
    authorize(@enrollment || MessageSequenceEnrollment.new)
  end
end
