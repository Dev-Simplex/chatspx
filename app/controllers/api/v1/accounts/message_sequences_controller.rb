# frozen_string_literal: true

# Follow-up drip (Módulo A, Fase A2) — CRUD for sequences and their steps. Steps are
# edited inline via accepts_nested_attributes_for, so the builder saves a sequence
# and its ordered steps in one request. Authoring is admin-only (MessageSequencePolicy).
class Api::V1::Accounts::MessageSequencesController < Api::V1::Accounts::BaseController
  before_action :message_sequence, except: [:index, :create]
  before_action :check_authorization

  def index
    @message_sequences = policy_scope(MessageSequence).includes(:steps).order(:name)
  end

  def show; end

  def create
    @message_sequence = Current.account.message_sequences.create!(
      message_sequence_params.merge(created_by: Current.user)
    )
    render :show, status: :created
  end

  def update
    @message_sequence.update!(message_sequence_params)
    render :show
  end

  def destroy
    @message_sequence.destroy!
    head :ok
  end

  private

  def message_sequence
    @message_sequence ||= policy_scope(MessageSequence).find(params[:id])
  end

  def message_sequence_params
    params.require(:message_sequence).permit(
      :name, :active,
      exit_conditions: {},
      steps_attributes: [:id, :position, :delay_minutes, :content, :_destroy]
    )
  end

  def check_authorization
    authorize(@message_sequence || MessageSequence.new(account: Current.account))
  end
end
