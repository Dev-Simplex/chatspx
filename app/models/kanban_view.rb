# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_views
#
#  id          :bigint           not null, primary key
#  kanban_id   :bigint           not null
#  user_id     :bigint
#  name        :string           not null
#  is_shared   :boolean          default(false), not null
#  filters     :jsonb            default({}), not null
#  sort        :jsonb            default({"by"=>"last_activity_at","dir"=>"desc"}), not null
#  settings    :jsonb            default({}), not null
#  position    :integer          default(0), not null
#
# KANBAN-P2-04: views salvas pelo usuario (filtros + sort + settings).
# MVP: somente pessoais. Compartilhadas em P3+.
class KanbanView < ApplicationRecord
  MAX_PER_KANBAN = 50

  belongs_to :kanban
  belongs_to :user, optional: true

  validates :name, presence: true, length: { maximum: 80 }
  validate :respect_max_per_kanban

  scope :ordered, -> { order(:position, :created_at) }
  scope :personal_for, ->(user) { where(user_id: user&.id, is_shared: false) }

  private

  def respect_max_per_kanban
    return if user_id.blank?
    return if persisted?

    count = self.class.where(kanban_id: kanban_id, user_id: user_id).count
    errors.add(:base, "limit_reached:#{MAX_PER_KANBAN}") if count >= MAX_PER_KANBAN
  end
end
