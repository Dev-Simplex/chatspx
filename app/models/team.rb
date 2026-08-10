# == Schema Information
#
# Table name: teams
#
#  id                :bigint           not null, primary key
#  allow_auto_assign :boolean          default(TRUE)
#  description       :text
#  name              :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  index_teams_on_account_id           (account_id)
#  index_teams_on_name_and_account_id  (name,account_id) UNIQUE
#
class Team < ApplicationRecord
  include AccountCacheRevalidator

  belongs_to :account
  has_many :team_members, dependent: :destroy_async
  has_many :members, through: :team_members, source: :user
  # Supervisão (D1): coleção separada dos membros de propósito — supervisor não conta
  # como membro em nada (auto-assign, chat interno, etiquetas "de-time").
  has_many :team_supervisors, dependent: :destroy_async
  has_many :supervisors, through: :team_supervisors, source: :user
  has_many :conversations, dependent: :nullify
  # As 3 tabelas que este fork acrescentou apontando para `teams` nasceram com FK
  # sem `on_delete` e sem associação aqui — ou seja, cada uma trancava o destroy
  # do time com ActiveRecord::InvalidForeignKey (500 na tela).
  # Semântica escolhida por tabela:
  #   - grupo do chat interno: morre junto (um canal `team` sem time é inválido);
  #   - funil do Kanban: sobrevive com team_id NULL (vira o funil "Geral"), porque
  #     destruir levaria junto o quadro e todos os cartões, sem o admin pedir;
  #   - histórico de atribuição: é trilha de auditoria, sobrevive sem o time.
  has_many :internal_channels, dependent: :destroy
  has_many :funnels, dependent: :nullify
  has_many :conversation_assignment_histories, dependent: :nullify

  validates :name,
            presence: { message: I18n.t('errors.validations.presence') },
            uniqueness: { scope: :account_id }

  before_validation do
    self.name = name.downcase if attribute_present?('name')
  end

  after_create :create_default_funnel
  # Chat interno: todo time tem um "grupo de time" no chat interno, com os membros
  # espelhando a equipe. Cria o grupo ao criar o time e renomeia se o time muda de
  # nome. Best-effort — uma falha no chat nunca pode bloquear o CRUD do time.
  after_create :sync_internal_team_channel
  after_update :sync_internal_team_channel, if: :saved_change_to_name?
  # A FK de Label.team já faz nullify, mas isso deixaria labels "de-time" com
  # visibility=team e team_id=NULL (inválidas na próxima validação). Rebaixa para
  # everyone antes do destroy (roda antes do dependent: :destroy_async dos membros).
  before_destroy :rebase_team_labels
  # Mesma razão do rebase_team_labels: a FK de CannedResponse.team faz nullify, mas
  # isso deixaria respostas "de-time" com visibility=team e team_id=NULL (inválidas).
  # Rebaixa para everyone antes do destroy.
  before_destroy :rebase_team_canned_responses

  # Adds multiple members to the team
  # @param user_ids [Array<Integer>] Array of user IDs to add as members
  # @return [Array<User>] Array of newly added members
  def add_members(user_ids)
    team_members_to_create = user_ids.map { |user_id| { user_id: user_id } }
    created_members = team_members.create(team_members_to_create)
    added_users = created_members.filter_map(&:user)

    update_account_cache
    added_users
  end

  # Removes multiple members from the team
  # @param user_ids [Array<Integer>] Array of user IDs to remove
  # @return [void]
  def remove_members(user_ids)
    team_members.where(user_id: user_ids).destroy_all
    update_account_cache
  end

  def messages
    account.messages.where(conversation_id: conversations.select(:id))
  end

  def reporting_events
    account.reporting_events.where(conversation_id: conversations.select(:id))
  end

  def push_event_data
    {
      id: id,
      name: name
    }
  end

  private

  def create_default_funnel
    Kanban::CreateFunnelForTeamService.new(team: self).perform
  rescue StandardError => e
    Rails.logger.error "Error creating default funnel for team #{id}: #{e.message}"
  end

  def sync_internal_team_channel
    # Sem este guard, TODA conta ganhava canal de chat interno mesmo com a feature
    # desligada — e junto vinham os cadeados de FK acima. A flag off tem que
    # significar "não cria nada".
    return unless account.feature_enabled?('internal_chat')

    InternalChannels::SyncTeamChannelsService.new(account: account, team: self).perform
  rescue StandardError => e
    Rails.logger.warn "[internal_chat] team channel sync failed for team ##{id}: #{e.message}"
  end

  def rebase_team_labels
    Label.where(team_id: id, visibility: :team).update_all(visibility: :everyone, team_id: nil) # rubocop:disable Rails/SkipsModelValidations
  end

  def rebase_team_canned_responses
    CannedResponse.where(team_id: id, visibility: :team).update_all(visibility: :everyone, team_id: nil) # rubocop:disable Rails/SkipsModelValidations
  end
end

Team.include_mod_with('Audit::Team')
