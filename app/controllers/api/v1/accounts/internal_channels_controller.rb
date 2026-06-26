# frozen_string_literal: true

# Chat interno (Módulo B, B1) — the agent's channels (DMs for now). `read` stamps
# last_read_at so the unread badge clears. Membership is enforced by the policy.
class Api::V1::Accounts::InternalChannelsController < Api::V1::Accounts::BaseController
  before_action :fetch_channel, only: [:show, :read, :typing]
  before_action :check_authorization

  def index
    # for_user already yields one row per channel (a user has a single membership
    # per channel), so no .distinct is needed — and .distinct would choke on the
    # json columns of joined tables ("no equality operator for type json").
    @channels = policy_scope(InternalChannel).includes(:users, :messages, members: :user)
  end

  def show; end

  def create
    @channel = build_channel
    return render json: { error: 'Invalid channel' }, status: :unprocessable_entity if @channel.nil?

    render :show, status: :created
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

  def fetch_channel
    @channel = policy_scope(InternalChannel).find(params[:id])
  end

  def check_authorization
    authorize(@channel || InternalChannel)
  end
end
