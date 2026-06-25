# frozen_string_literal: true

# Chat interno (Módulo B, B1) — the agent's channels (DMs for now). `read` stamps
# last_read_at so the unread badge clears. Membership is enforced by the policy.
class Api::V1::Accounts::InternalChannelsController < Api::V1::Accounts::BaseController
  before_action :fetch_channel, only: [:show, :read]
  before_action :check_authorization

  def index
    # for_user already yields one row per channel (a user has a single membership
    # per channel), so no .distinct is needed — and .distinct would choke on the
    # json columns of joined tables ("no equality operator for type json").
    @channels = policy_scope(InternalChannel).includes(:members, :users, :messages)
  end

  def show; end

  def create
    other_user = Current.account.users.find_by(id: params[:user_id])
    @channel = InternalChannels::FindOrCreateDmService.new(
      account: Current.account, user: Current.user, other_user: other_user
    ).perform
    return render json: { error: 'Invalid user' }, status: :unprocessable_entity if @channel.nil?

    render :show, status: :created
  end

  def read
    @channel.members.find_by(user_id: Current.user.id)&.update(last_read_at: Time.current)
    head :ok
  end

  private

  def fetch_channel
    @channel = policy_scope(InternalChannel).find(params[:id])
  end

  def check_authorization
    authorize(@channel || InternalChannel)
  end
end
