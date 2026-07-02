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
    @account.internal_channels.create!(channel_type: :direct, dm_key: dm_key).tap do |channel|
      channel.members.create!(user: @user)
      channel.members.create!(user: @other_user)
    end
  rescue ActiveRecord::RecordNotUnique
    # Lost a race — the unique index on (account_id, dm_key) rejected the insert.
    # The other request's channel row already exists (even if its members are a
    # beat behind), so find by dm_key, falling back to the membership lookup.
    @account.internal_channels.direct.find_by(dm_key: dm_key) || find_existing_dm
  end

  # Canonical key for the participant pair, so the DB can enforce one DM per pair.
  def dm_key
    [@user.id, @other_user.id].sort.join('-')
  end
end
