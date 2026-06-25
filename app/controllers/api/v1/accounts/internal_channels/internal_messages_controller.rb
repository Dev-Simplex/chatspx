# frozen_string_literal: true

# Chat interno (Módulo B, B1) — messages within a channel. Fetching marks the
# channel read for the requester; posting broadcasts in real time.
class Api::V1::Accounts::InternalChannels::InternalMessagesController < Api::V1::Accounts::BaseController
  before_action :fetch_channel
  before_action :authorize_channel

  def index
    @messages = @channel.messages.includes(:user, attachments_attachments: :blob).order(:created_at)
    @channel.members.find_by(user_id: Current.user.id)&.update(last_read_at: Time.current)
  end

  def create
    @message = InternalMessages::CreateService.new(
      channel: @channel, user: Current.user,
      content: params[:content], attachments: params[:attachments]
    ).perform
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def fetch_channel
    @channel = policy_scope(InternalChannel).find(params[:internal_channel_id])
  end

  def authorize_channel
    authorize(@channel)
  end
end
