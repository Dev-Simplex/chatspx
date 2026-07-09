# == Schema Information
#
# Table name: canned_responses
#
#  id            :integer          not null, primary key
#  content       :text
#  short_code    :string
#  visibility    :integer          default("everyone"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :integer          not null
#  created_by_id :bigint
#  team_id       :bigint
#

class CannedResponse < ApplicationRecord
  # _prefix evita CannedResponse.team (colide com belongs_to :team) e
  # public/private (colidem com a visibilidade de métodos Ruby). Gera:
  # visibility_everyone?, CannedResponse.visibility_team, visibility_personal?, etc.
  enum visibility: { everyone: 0, personal: 1, team: 2 }, _prefix: :visibility

  validates :content, presence: true
  validates :short_code, presence: true
  validates :account, presence: true
  validates :short_code, uniqueness: { scope: :account_id }
  validates :team_id, presence: true, if: :visibility_team?
  validate  :team_belongs_to_account, if: :visibility_team?
  validates :team_id, absence: true, unless: :visibility_team? # limpa team_id se não for de-time

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :team, optional: true
  has_many_attached :attachments

  # Catálogo visível a um usuário — espelha Label.with_visibility. Usar SÓ no
  # controller#index (que também alimenta o compositor). Recebe a relação BASE já
  # filtrada por busca, para compor com ela.
  def self.with_visibility(user, base = nil)
    account = Current.account
    base ||= account.canned_responses
    return base if account_admin?(user, account)

    team_ids = user.teams.where(account_id: account.id).select(:id)
    base.where(visibility: :everyone)
        .or(base.where(visibility: :personal, created_by_id: user.id))
        .or(base.where(visibility: :team, team_id: team_ids))
  end

  def self.account_admin?(user, account)
    account.account_users.find_by(user_id: user.id)&.administrator? || false
  end

  scope :order_by_search, lambda { |search|
    short_code_starts_with = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 1', "#{search}%"])
    short_code_like = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 0.5', "%#{search}%"])
    content_like = sanitize_sql_array(['WHEN content ILIKE ? THEN 0.2', "%#{search}%"])

    order_clause = "CASE #{short_code_starts_with} #{short_code_like} #{content_like} ELSE 0 END"

    order(Arel.sql(order_clause) => :desc)
  }

  private

  def team_belongs_to_account
    return if team&.account_id == account_id

    errors.add(:team, 'must belong to the same account')
  end
end
