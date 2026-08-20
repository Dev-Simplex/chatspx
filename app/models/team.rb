# == Schema Information
#
# Table name: teams
#
#  id                :bigint           not null, primary key
#  allow_auto_assign :boolean          default(TRUE)
#  description       :text
#  icon              :string           default("")
#  icon_color        :string           default("")
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

  after_create :create_default_funnel
  # Chat interno: todo time tem um "grupo de time" no chat interno, com os membros
  # espelhando a equipe. Cria o grupo ao criar o time e renomeia se o time muda de
  # nome. Best-effort — uma falha no chat nunca pode bloquear o CRUD do time.
  after_create :sync_internal_team_channel
  after_update :sync_internal_team_channel, if: :saved_change_to_name?
  before_destroy :capture_filtered_unread_count_member_ids, prepend: true
  after_destroy_commit :invalidate_filtered_unread_counts_after_destroy

  validates :name,
            presence: { message: I18n.t('errors.validations.presence') },
            uniqueness: { scope: :account_id }

  before_validation do
    self.name = name.gsub(/[[:cntrl:]]/, '').strip.downcase if attribute_present?('name')
  end

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
      name: name,
      icon: icon,
      icon_color: icon_color
    }
  end

  private

  def create_default_funnel
    Kanban::CreateFunnelForTeamService.new(team: self).perform
  rescue StandardError => e
    Rails.logger.error "Error creating default funnel for team #{id}: #{e.message}"
  end

  def sync_internal_team_channel
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

  def capture_filtered_unread_count_member_ids
    @filtered_unread_count_member_ids = team_members.pluck(:user_id)
  end

  def invalidate_filtered_unread_counts_after_destroy
    invalidator = ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account)
    invalidator.conversation_changed!
    invalidator.users_visibility_changed!(user_ids: @filtered_unread_count_member_ids)
  end
end

Team.include_mod_with('Audit::Team')
