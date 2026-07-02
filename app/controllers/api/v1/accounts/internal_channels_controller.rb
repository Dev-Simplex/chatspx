# frozen_string_literal: true

# Chat interno (Módulo B, B1) — the agent's channels (DMs for now). `read` stamps
# last_read_at so the unread badge clears. Membership is enforced by the policy.
class Api::V1::Accounts::InternalChannelsController < Api::V1::Accounts::BaseController
  before_action :fetch_channel, only: [:show, :read, :typing, :update, :add_member, :remove_member, :leave]
  before_action :check_authorization

  def index
    # for_user already yields one row per channel (a user has a single membership
    # per channel), so no .distinct is needed — and .distinct would choke on the
    # json columns of joined tables ("no equality operator for type json").
    # Admin em modo auditoria (?scope=all) vê TODOS os canais da conta.
    base = audit_all? ? Current.account.internal_channels : policy_scope(InternalChannel)
    @channels = base.includes(:users, members: :user).to_a
    # Fase 2: compute the preview + unread badge in 2 grouped queries instead of
    # the per-channel N+1 (includes(:messages) loaded EVERY message of EVERY
    # channel, and unread_count fired one COUNT per channel).
    channel_ids = @channels.map(&:id)
    @last_messages = last_message_previews(channel_ids)
    @unread_counts = unread_counts(channel_ids)
  end

  def show; end

  def create
    return render_forbidden if params[:team_id].present? && !Current.account_user&.administrator?

    @channel = build_channel
    return render json: { error: 'Invalid channel' }, status: :unprocessable_entity if @channel.nil?

    render :show, status: :created
  end

  # Group management (Fase 5). Rename / add / remove only apply to group channels;
  # leave works on any non-DM channel. Any member may manage (collaborative).
  def update
    return render_forbidden unless @channel.group_chat?

    @channel.update!(name: params[:name]) if params[:name].present?
    broadcast_channel_update
    render :show
  end

  def add_member
    return render_forbidden unless @channel.group_chat?

    user = Current.account.users.find_by(id: params[:user_id])
    return head(:unprocessable_entity) if user.nil?

    @channel.members.find_or_create_by(user_id: user.id)
    broadcast_channel_update
    render :show
  end

  def remove_member
    return render_forbidden unless @channel.group_chat?

    @channel.members.where(user_id: params[:user_id]).destroy_all
    broadcast_channel_update
    render :show
  end

  def leave
    return render_forbidden if @channel.direct?

    @channel.members.where(user_id: Current.user.id).destroy_all
    broadcast_channel_update
    head :ok
  end

  def read
    InternalChannels::MarkReadService.new(channel: @channel, user: Current.user).perform
    head :ok
  end

  # Real-time "digitando…" — broadcast to the other members only.
  def typing
    tokens = @channel.users.where.not(id: Current.user.id).pluck(:pubsub_token).compact
    if tokens.present?
      ActionCableBroadcastJob.perform_later(tokens, 'internal.typing', {
                                              account_id: @channel.account_id,
                                              internal_channel_id: @channel.id,
                                              user: { id: Current.user.id, name: Current.user.name },
                                              typing: ActiveModel::Type::Boolean.new.cast(params[:typing])
                                            })
    end
    head :ok
  end

  private

  # Branch by params: a DM (user_id), a team channel (team_id) or a group (name + member_ids).
  def build_channel
    return build_team_channel if params[:team_id].present?
    return build_group_channel if params[:member_ids].present?

    build_dm
  end

  def build_team_channel
    team = Current.account.teams.find_by(id: params[:team_id])
    return if team.nil?

    InternalChannels::CreateService.new(account: Current.account, creator: Current.user, team: team).perform
  end

  def build_group_channel
    InternalChannels::CreateService.new(
      account: Current.account, creator: Current.user,
      name: params[:name], member_ids: params[:member_ids]
    ).perform
  end

  def build_dm
    other_user = Current.account.users.find_by(id: params[:user_id])
    InternalChannels::FindOrCreateDmService.new(account: Current.account, user: Current.user, other_user: other_user).perform
  end

  # Admin pode alcançar qualquer canal da conta (auditoria); a policy decide o que
  # ele pode fazer (show? permite admin; ações de escrita continuam member-only).
  def fetch_channel
    base = Current.account_user&.administrator? ? Current.account.internal_channels : policy_scope(InternalChannel)
    @channel = base.find(params[:id])
  end

  def audit_all?
    params[:scope] == 'all' && Current.account_user&.administrator?
  end

  # Last message per channel in ONE query (DISTINCT ON) — replaces includes(:messages).
  def last_message_previews(channel_ids)
    return {} if channel_ids.blank?

    InternalMessage
      .where(internal_channel_id: channel_ids)
      .select('DISTINCT ON (internal_channel_id) internal_messages.*')
      .order('internal_channel_id, created_at DESC, id DESC')
      .preload(:user)
      .index_by(&:internal_channel_id)
  end

  # Unread (non-deleted, from others, after my last_read_at) per channel for the
  # current user in ONE grouped query — replaces the per-channel COUNT.
  def unread_counts(channel_ids)
    return {} if channel_ids.blank?

    InternalChannelMember
      .where(user_id: Current.user.id, internal_channel_id: channel_ids)
      .joins('JOIN internal_messages im ON im.internal_channel_id = internal_channel_members.internal_channel_id')
      .where('im.user_id <> internal_channel_members.user_id AND im.deleted_at IS NULL')
      .where('internal_channel_members.last_read_at IS NULL OR im.created_at > internal_channel_members.last_read_at')
      .group('internal_channel_members.internal_channel_id')
      .count('im.id')
  end

  def check_authorization
    authorize(@channel || InternalChannel)
  end

  # Tell members to refresh their channel list after a name/membership change.
  def broadcast_channel_update
    tokens = @channel.users.pluck(:pubsub_token).compact
    return if tokens.blank?

    ActionCableBroadcastJob.perform_later(tokens, 'internal.channel.updated',
                                          { account_id: @channel.account_id, internal_channel_id: @channel.id })
  end

  def render_forbidden
    render json: { error: 'Not allowed' }, status: :forbidden
  end
end
