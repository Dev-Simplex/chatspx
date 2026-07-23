# == Schema Information
#
# Table name: labels
#
#  id              :bigint           not null, primary key
#  color           :string           default("#1f93ff"), not null
#  description     :text
#  show_on_sidebar :boolean
#  title           :string
#  visibility      :integer          default("everyone"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint
#  created_by_id   :bigint
#  team_id         :bigint
#
# Indexes
#
#  index_labels_on_account_and_visibility  (account_id,visibility)
#  index_labels_on_account_id              (account_id)
#  index_labels_on_created_by_id           (created_by_id)
#  index_labels_on_team_id                 (team_id)
#  index_labels_on_title_and_account_id    (title,account_id) UNIQUE
#
class Label < ApplicationRecord
  include RegexHelper
  include AccountCacheRevalidator

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :team, optional: true

  # _prefix evita colisão de Label.public/Label.private com a visibilidade de métodos
  # Ruby, e de Label.team com a associação belongs_to :team. Gera: visibility_everyone?,
  # Label.visibility_team, etc.
  enum visibility: { everyone: 0, personal: 1, team: 2 }, _prefix: :visibility

  validates :title,
            presence: { message: I18n.t('errors.validations.presence') },
            format: { with: UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE_DOT },
            uniqueness: { scope: :account_id }
  validates :team_id, presence: true, if: :visibility_team?
  validate  :team_belongs_to_account, if: :visibility_team?
  validates :team_id, absence: true, unless: :visibility_team? # limpa team_id se não for de-time

  after_update_commit :update_associated_models
  default_scope { order(:title) }

  before_validation do
    self.title = title.downcase if attribute_present?('title')
  end

  def conversations
    account.conversations.tagged_with(title)
  end

  def messages
    account.messages.where(conversation_id: conversations.pluck(:id))
  end

  def reporting_events
    account.reporting_events.where(conversation_id: conversations.pluck(:id))
  end

  # Catálogo visível a um usuário (o coração da feature) — espelha Macro.with_visibility.
  # ATENÇÃO: usar SÓ no labels_controller#index. Não aplicar globalmente.
  def self.with_visibility(user)
    account = Current.account
    base = account.labels                         # respeita o scoping por conta da associação
    return base if account_admin?(user, account)  # admin vê tudo

    team_ids = user.teams.where(account_id: account.id).select(:id)
    base.where(visibility: :everyone)
        .or(base.where(visibility: :personal, created_by_id: user.id))
        .or(base.where(visibility: :team, team_id: team_ids))
  end

  def self.account_admin?(user, account)
    account.account_users.find_by(user_id: user.id)&.administrator? || false
  end

  private

  def team_belongs_to_account
    return if team&.account_id == account_id

    errors.add(:team, 'must belong to the same account')
  end

  def update_associated_models
    return unless title_previously_changed?

    Labels::UpdateJob.perform_later(title, title_previously_was, account_id)
  end
end
