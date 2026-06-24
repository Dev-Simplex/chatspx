# frozen_string_literal: true

# == Schema Information
#
# Table name: funnel_custom_fields
#
#  id           :bigint           not null, primary key
#  field_type   :string           not null
#  key          :string           not null
#  label        :string           not null
#  options      :jsonb            not null
#  position     :integer          default(0)
#  show_on_card :boolean          default(FALSE), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  funnel_id    :bigint           not null
#
# Kanban v2 (Fase 2): definition of a custom field for a funnel. Values live in
# conversations.custom_attributes under `funnel_<funnel_id>_<key>`.
class FunnelCustomField < ApplicationRecord
  # Types the front-end can render AND edit in the MVP. Richer types
  # (files, progress, tags, hour) are deferred to later phases.
  FIELD_TYPES = %w[text long_text number date dropdown checkbox rating phone email link].freeze

  belongs_to :funnel

  validates :key, presence: true,
                  format: { with: /\A[a-z][a-z0-9_]*\z/ },
                  uniqueness: { scope: :funnel_id }
  validates :label, presence: true
  validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }

  scope :ordered, -> { order(:position, :created_at) }
  scope :on_card, -> { where(show_on_card: true) }
  scope :numeric, -> { where(field_type: %w[number rating]) }

  # Fully-qualified key used inside conversations.custom_attributes.
  def attribute_key
    "funnel_#{funnel_id}_#{key}"
  end
end
