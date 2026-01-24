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
# Indexes
#
#  index_funnel_stages_on_automation_type  (automation_type)
#  index_funnel_stages_on_funnel_id        (funnel_id)
#
# Foreign Keys
#
#  fk_rails_...  (funnel_id => funnels.id)
#
class FunnelStage < ApplicationRecord
  belongs_to :funnel
  has_many :funnel_items, dependent: :destroy

  validates :name, presence: true
  validates :name, length: { minimum: 1 }, allow_blank: false
  validates :funnel_id, presence: true
  validates :automation_type, uniqueness: { scope: :funnel_id, allow_nil: true }, if: :automation_type?

  scope :ordered, -> { order(:position, :created_at) }
  scope :with_automation, ->(automation_type) { where(automation_type: automation_type) }
  scope :with_open_automation, -> { with_automation('open') }
  scope :with_resolved_automation, -> { with_automation('resolved') }
end

