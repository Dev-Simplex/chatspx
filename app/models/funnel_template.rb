# frozen_string_literal: true

# == Schema Information
#
# Table name: funnel_templates
#
#  id          :bigint           not null, primary key
#  definition  :jsonb            not null
#  description :string
#  name        :string           not null
#  position    :integer          default(0)
#  slug        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Kanban v2 (Fase 8): a ready-made funnel blueprint (stages + custom fields).
class FunnelTemplate < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :ordered, -> { order(:position, :name) }

  def stages
    Array(definition['stages'])
  end

  def custom_fields
    Array(definition['custom_fields'])
  end
end
