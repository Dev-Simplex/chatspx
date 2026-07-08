# frozen_string_literal: true

# Chat interno — messages within a channel. Fetching marks the channel read for
# the requester; posting/editing/deleting/reacting broadcasts in real time.
# Edit: author only. Delete: author or admin. React: any member.
class Api::V1::Accounts::InternalChannels::InternalMessagesController < Api::V1::Accounts::BaseController
  before_action :fetch_channel
  before_action :authorize_channel
  before_action :fetch_message, only: [:update, :destroy, :react]

  PAGE_SIZE = 30

  # Newest page by default; pass `before` (a message id) to load older history.
  def index
    scope = @channel.messages.includes(
      :user, { reply_to: :user }, { shared_conversation: [:contact, :inbox] }, attachments_attachments: :blob
    )
    scope = scope.where('internal_messages.id < ?', params[:before]) if params[:before].present?
    # reorder (not order): the messages association defaults to created_at ASC,
    # which would otherwise dominate and make limit() take the OLDEST rows.
    page = scope.reorder(id: :desc).limit(PAGE_SIZE).to_a
    @has_more = page.size == PAGE_SIZE
    @messages = page.reverse
    # Only the latest page (an actual "open") marks the channel read.
    InternalChannels::MarkReadService.new(channel: @channel, user: Current.user).perform if params[:before].blank?
  end

  def create
    return render_forbidden unless channel_member?

    @message = InternalMessages::CreateService.new(
      channel: @channel, user: Current.user,
      content: params[:content], attachments: params[:attachments],
      mentioned_user_ids: params[:mentioned_user_ids], reply_to_id: params[:reply_to_id],
      shared_conversation_display_id: params[:shared_conversation_id], echo_id: params[:echo_id]
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
    return render_forbidden unless channel_member?

    emoji = params[:emoji].to_s
    return head(:unprocessable_entity) if emoji.blank? || @message.deleted?

    @message.toggle_reaction!(emoji, Current.user.id)
    InternalMessages::BroadcastService.updated(@message)
    render :show
  end

  private

  # Admin alcança qualquer canal (para ler em auditoria); a policy (show?) libera
  # admin para leitura, e channel_member? barra escrita em canais que ele não participa.
  def fetch_channel
    base = Current.account_user&.administrator? ? Current.account.internal_channels : policy_scope(InternalChannel)
    @channel = base.find(params[:internal_channel_id])
  end

  def channel_member?
    @channel.members.exists?(user_id: Current.user.id)
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
