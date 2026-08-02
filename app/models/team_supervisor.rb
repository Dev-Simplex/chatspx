# == Schema Information
#
# Table name: team_supervisors
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  team_id    :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_team_supervisors_on_team_id_and_user_id  (team_id,user_id) UNIQUE
#  index_team_supervisors_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (team_id => teams.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# Supervisão de time (D1): quem supervisiona vê as conversas do time sem ser membro
# dele. Deliberadamente SEM os callbacks do TeamMember (chat interno, auto-assign):
# supervisionar é leitura ampliada, não participação na equipe.
class TeamSupervisor < ApplicationRecord
  belongs_to :team
  belongs_to :user

  validates :user_id, uniqueness: { scope: :team_id }
  validate :user_belongs_to_team_account

  # A lista de times é servida do cache local do navegador (CacheEnabledApiClient),
  # e é nela que viaja o `is_supervisor` de cada time. Team invalida essa chave por
  # AccountCacheRevalidator, mas supervisionar não altera nenhum Team — sem este
  # callback o cliente segue servindo a lista antiga e a tela do supervisor nasce
  # vazia mesmo com a linha gravada. Invalida a chave de `team` (a que o cliente
  # guarda), não a de `team_supervisor`, que ninguém consulta.
  after_commit :invalidate_team_cache, on: %i[create update destroy]

  private

  def invalidate_team_cache
    team&.account&.update_cache_key('team')
  end

  # Supervisão é sempre dentro de uma conta: um usuário de OUTRA conta não pode
  # supervisionar este time (o AgentsController já filtra os ids, isto é a rede de
  # segurança para quem cria o registro direto pelo modelo/console).
  def user_belongs_to_team_account
    return if team.blank? || user.blank?
    return if user.account_users.exists?(account_id: team.account_id)

    errors.add(:user, 'must belong to the same account as the team')
  end
end
