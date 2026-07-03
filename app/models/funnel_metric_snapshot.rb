# frozen_string_literal: true

# == Schema Information
#
# Table name: funnel_metric_snapshots
#
#  id          :bigint           not null, primary key
#  captured_on :date             not null
#  metrics     :jsonb            not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  funnel_id   :bigint           not null
#
# Kanban v2 (Fase 6): a daily snapshot of a funnel's metrics, for baselines.
class FunnelMetricSnapshot < ApplicationRecord
  belongs_to :funnel

  validates :captured_on, presence: true, uniqueness: { scope: :funnel_id }

  scope :recent_first, -> { order(captured_on: :desc) }
end
