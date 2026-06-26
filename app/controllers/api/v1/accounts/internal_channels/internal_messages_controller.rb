# frozen_string_literal: true

# Chat interno — messages within a channel. Fetching marks the channel read for
# the requester; posting/editing/deleting/reacting broadcasts in real time.
# Edit: author only. Delete: author or admin. React: any member.
class Api::V1::Accounts::InternalChannels::InternalMessagesController < Api::V1::Accounts::BaseController
  before_action :fetch_channel
  before_action :authorize_channel
  before_action :fetch_message, only: [:update, :destroy, :react]

  def index
    @messages = @channel.messages.includes(:user, attachments_attachments: :blob).order(:created_at)
    InternalChannels::MarkReadService.new(channel: @channel, user: Current.user).perform
  end

  def create
    @message = InternalMessages::CreateService.new(
      channel: @channel, user: Current.user,
      content: params[:content], attachments: params[:attachments],
      mentioned_user_ids: params[:mentioned_user_ids]
    ).perform
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    return render_forbidden unless author?
    return head(:unprocessable_entity) if @message.deleted?

    @message.update!(content: params[:content].to_s, edited_at: Time.current)
    InternalMessages::BroadcastService.updated(@message)
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    return render_forbidden unless author? || Current.account_user&.administrator?

    @message.soft_delete!
    InternalMessages::BroadcastService.updated(@message)
    render :show
  end

  def react
    emoji = params[:emoji].to_s
    return head(:unprocessable_entity) if emoji.blank? || @message.deleted?

    @message.toggle_reaction!(emoji, Current.user.id)
    InternalMessages::BroadcastService.updated(@message)
    render :show
  end

  private

  def fetch_channel
    @channel = policy_scope(InternalChannel).find(params[:internal_channel_id])
  end

  def fetch_message
    @message = @channel.messages.find(params[:id])
  end

  # All message actions require channel membership; the finer author/admin checks
  # live in the actions themselves. Always query the membership rule (show?).
  def authorize_channel
    authorize(@channel, :show?)
  end

  def author?
    @message.user_id == Current.user.id
  end

  def render_forbidden
    render json: { error: 'Not allowed' }, status: :forbidden
  end
end
