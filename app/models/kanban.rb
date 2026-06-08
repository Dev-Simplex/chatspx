# frozen_string_literal: true

# == Schema Information
#
# Table name: kanbans
#
#  id         :bigint           not null, primary key
#  color      :string
#  name       :string           not null
#  position   :integer          default(0)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  team_id    :bigint
#  inbox_ids  :jsonb            default([]), not null
#
class Kanban < ApplicationRecord
  belongs_to :account
  belongs_to :team, optional: true
  has_many :kanban_stages, dependent: :destroy
  has_many :kanban_items, dependent: :destroy
  has_many :kanban_views, dependent: :destroy
  has_many :kanban_automations, dependent: :destroy
  belongs_to :template, class_name: 'KanbanTemplate', optional: true

  validates :name, presence: true
  validates :name, length: { minimum: 1 }, allow_blank: false
  validates :account_id, presence: true

  before_save :normalize_inbox_ids

  scope :ordered, -> { order(:position, :created_at) }
  scope :for_inbox, ->(inbox_id) { where("inbox_ids = '[]' OR inbox_ids @> ?", [inbox_id].to_json) }

  def stages_ordered
    kanban_stages.ordered
  end

  def allows_inbox?(inbox_id)
    return true if inbox_ids.blank? || inbox_ids.empty?

    inbox_ids.include?(inbox_id.to_i)
  end

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
