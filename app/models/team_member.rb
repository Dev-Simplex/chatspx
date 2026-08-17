# == Schema Information
#
# Table name: team_members
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  team_id    :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_team_members_on_team_id              (team_id)
#  index_team_members_on_team_id_and_user_id  (team_id,user_id) UNIQUE
#  index_team_members_on_user_id              (user_id)
#
class TeamMember < ApplicationRecord
  belongs_to :user
  belongs_to :team
  validates :user_id, uniqueness: { scope: :team_id }

  # Chat interno (Fase 2): keep the team's internal channel membership mirrored
  # when people join/leave the team (the channel snapshots members at creation).
  # Best-effort — a chat sync hiccup must never block team membership changes.
  after_create :sync_internal_team_channel_add
  after_destroy :sync_internal_team_channel_remove
  after_commit :invalidate_filtered_unread_count_visibility, on: [:create, :destroy]

  private

  def team_internal_channel
    InternalChannel.team.find_by(account_id: team.account_id, team_id: team_id)
  end

  def sync_internal_team_channel_add
    team_internal_channel&.members&.find_or_create_by(user_id: user_id)
  rescue StandardError => e
    Rails.logger.warn("[internal_chat] team channel sync (add) failed: #{e.message}")
  end

  def sync_internal_team_channel_remove
    team_internal_channel&.members&.where(user_id: user_id)&.destroy_all
  rescue StandardError => e
    Rails.logger.warn("[internal_chat] team channel sync (remove) failed: #{e.message}")
  end

  def invalidate_filtered_unread_count_visibility
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(team&.account).user_visibility_changed!(user_id: user_id)
  end
end

TeamMember.include_mod_with('Audit::TeamMember')
