# frozen_string_literal: true

# Finds the existing 1:1 channel between two users, or creates one. Idempotent —
# two agents always share exactly one DM channel.
class InternalChannels::FindOrCreateDmService
  def initialize(account:, user:, other_user:)
    @account = account
    @user = user
    @other_user = other_user
  end

  def perform
    return if @other_user.blank? || @other_user.id == @user.id

    find_existing_dm || create_dm
  end

  private

  def find_existing_dm
    @account.internal_channels.direct
            .joins(:members)
            .where(internal_channel_members: { user_id: [@user.id, @other_user.id] })
            .group('internal_channels.id')
            .having('COUNT(DISTINCT internal_channel_members.user_id) = 2')
            .first
  end

  def create_dm
    @account.internal_channels.create!(channel_type: :direct).tap do |channel|
      channel.members.create!(user: @user)
      channel.members.create!(user: @other_user)
    end
  rescue ActiveRecord::RecordNotUnique
    find_existing_dm # lost a race — return the channel the other request created
  end
end
