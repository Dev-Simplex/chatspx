# frozen_string_literal: true

# == Schema Information
#
# Table name: funnels
#
#  id         :bigint           not null, primary key
#  color      :string
#  name       :string           not null
#  position   :integer          default(0)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  team_id    :bigint
#
# Indexes
#
#  index_funnels_on_account_id  (account_id)
#  index_funnels_on_team_id     (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (team_id => teams.id)
#
class Funnel < ApplicationRecord
  belongs_to :account
  has_many :funnel_stages, dependent: :destroy
  has_many :funnel_items, dependent: :destroy

  validates :name, presence: true
  validates :name, length: { minimum: 1 }, allow_blank: false
  validates :account_id, presence: true

  # jsonb já serializa automaticamente, não precisa de serialize
  # Mas precisamos garantir que seja sempre um array
  before_save :normalize_inbox_ids

  scope :ordered, -> { order(:position, :created_at) }
  scope :for_inbox, ->(inbox_id) { where("inbox_ids = '[]' OR inbox_ids @> ?", [inbox_id].to_json) }

  def stages_ordered
    funnel_stages.ordered
  end

  # Verificar se uma inbox está permitida neste funil
  def allows_inbox?(inbox_id)
    return true if inbox_ids.blank? || inbox_ids.empty?
    inbox_ids.include?(inbox_id.to_i)
  end

  # Obter inboxes permitidas (ou todas se não houver filtro)
  def allowed_inboxes
    all_inboxes = Inbox.where(account_id: account_id)
    return all_inboxes if inbox_ids.blank? || inbox_ids.empty?
    all_inboxes.where(id: inbox_ids)
  end

  private

  def normalize_inbox_ids
    self.inbox_ids = [] if inbox_ids.nil?
    self.inbox_ids = inbox_ids.compact.map(&:to_i) if inbox_ids.is_a?(Array)
  end
end

