# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_stages
#
#  id              :bigint           not null, primary key
#  automation_type :string
#  color           :string
#  name            :string           not null
#  position        :integer          default(0)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  kanban_id       :bigint           not null
#
class KanbanStage < ApplicationRecord
  belongs_to :kanban
  has_many :kanban_items, dependent: :destroy

  validates :name, presence: true
  validates :name, length: { minimum: 1 }, allow_blank: false
  validates :kanban_id, presence: true
  validates :automation_type, uniqueness: { scope: :kanban_id, allow_nil: true }, if: :automation_type?

  scope :ordered, -> { order(:position, :created_at) }
  scope :with_automation, ->(automation_type) { where(automation_type: automation_type) }
  scope :with_open_automation, -> { with_automation('open') }
  scope :with_resolved_automation, -> { with_automation('resolved') }
end
