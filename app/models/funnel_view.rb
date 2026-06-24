# frozen_string_literal: true

# == Schema Information
#
# Table name: funnel_views
#
#  id         :bigint           not null, primary key
#  filters    :jsonb            not null
#  is_shared  :boolean          default(FALSE), not null
#  name       :string           not null
#  position   :integer          default(0)
#  view_mode  :string           default("kanban"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  funnel_id  :bigint           not null
#  user_id    :bigint
#
# Kanban v2 (Fase 3): a saved board recorte (filters + view mode) per funnel.
class FunnelView < ApplicationRecord
  VIEW_MODES = %w[kanban list calendar].freeze

  belongs_to :account
  belongs_to :funnel
  belongs_to :user, optional: true

  validates :name, presence: true
  validates :view_mode, inclusion: { in: VIEW_MODES }

  scope :ordered, -> { order(:position, :created_at) }

  # Views the user may see: their own private ones plus the account's shared ones.
  scope :visible_to, ->(user) { where(is_shared: true).or(where(user_id: user&.id)) }
end
