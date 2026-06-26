# frozen_string_literal: true

# Chat interno (v2 Fase 2B) — stamps a member's last_read_at and tells the other
# members in real time (read receipts) via the RoomChannel.
class InternalChannels::MarkReadService
  def initialize(channel:, user:)
    @channel = channel
    @user = user
  end

  def perform
    member = @channel.members.find_by(user_id: @user.id)
    return if member.nil?

    member.update(last_read_at: Time.current)
    broadcast(member)
  end

  private

  def broadcast(member)
    tokens = @channel.users.where.not(id: @user.id).pluck(:pubsub_token).compact
    return if tokens.blank?

    ActionCableBroadcastJob.perform_later(tokens, 'internal.read', {
                                            internal_channel_id: @channel.id,
                                            user_id: @user.id,
                                            last_read_at: member.last_read_at.to_i
                                          })
  end
end
