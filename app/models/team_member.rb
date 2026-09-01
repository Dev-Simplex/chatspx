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
  # A lista de times e servida do cache local do navegador (CacheEnabledApiClient), e e nela que
  # viaja o `is_member` de cada time. Team invalida essa chave por AccountCacheRevalidator, mas
  # entrar ou sair de um time nao altera nenhum Team — sem este callback o navegador segue com a
  # lista antiga e o agente continua vendo cadeado nas mensagens do time que acabou de ganhar
  # (`useTeamIsolation` filtra por `is_member`). Medido na AGN em 25/08/2026: a chave estava em
  # zero desde a criacao da conta, entao o cache NUNCA tinha sido revalidado ali.
  #
  # Espelha TeamSupervisor#invalidate_team_cache: `is_member` e `is_supervisor` alimentam o mesmo
  # getVisibleTeams, e so o segundo invalidava. Invalida a chave de `team` (a que o cliente
  # guarda), nao a de `team_member`, que ninguem consulta.
  after_commit :invalidate_team_cache, on: %i[create destroy]

  private

  def invalidate_team_cache
    team&.account&.update_cache_key('team')
  end

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
end

TeamMember.include_mod_with('Audit::TeamMember')
