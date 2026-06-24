# frozen_string_literal: true

# == Schema Information
#
# Table name: funnel_stages
#
#  id              :bigint           not null, primary key
#  automation_type :string
#  color           :string
#  name            :string           not null
#  position        :integer          default(0)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  funnel_id       :bigint           not null
#
class FunnelStage < ApplicationRecord
  belongs_to :funnel
  has_many :funnel_items, dependent: :destroy

  # Kanban v2 (Fase 1): per-stage config persisted in the `settings` jsonb.
  #   wip_limit        -> integer cap of cards shown in the column (nil = no limit)
  #   sla_hours        -> hours-in-stage budget; drives conditional card coloring
  #   color_rules      -> reserved for richer conditional coloring rules
  #   stage_permissions-> reserved for Fase 4 per-stage permissions
  store_accessor :settings, :wip_limit, :sla_hours, :color_rules, :stage_permissions

  validates :name, presence: true
  validates :name, length: { minimum: 1 }, allow_blank: false
  validates :funnel_id, presence: true
  validates :automation_type, uniqueness: { scope: :funnel_id, allow_nil: true }, if: :automation_type?

  scope :ordered, -> { order(:position, :created_at) }
  scope :with_automation, ->(automation_type) { where(automation_type: automation_type) }
  scope :with_open_automation, -> { with_automation('open') }
  scope :with_resolved_automation, -> { with_automation('resolved') }
end
