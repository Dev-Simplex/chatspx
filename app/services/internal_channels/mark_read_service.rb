# frozen_string_literal: true

# Chat interno (v2 Fase 2B) — stamps a member's last_read_at.
# No real-time 'internal.read' broadcast: no screen shows read receipts, and in a
# team channel every viewer marking read re-broadcast to every other member
# (V viewers x N members publications per message). Bring it back with the receipt UI.
class InternalChannels::MarkReadService
  def initialize(channel:, user:)
    @channel = channel
    @user = user
  end

  def perform
    @channel.members.find_by(user_id: @user.id)&.update(last_read_at: Time.current)
  end
end
