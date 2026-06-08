# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_items
#
#  id                   :bigint           not null, primary key
#  conversation_id      :bigint           not null
#  kanban_id            :bigint           not null
#  kanban_stage_id      :bigint           not null
#  moved_by_id          :bigint
#  last_stage_change_at :datetime
#  position             :decimal
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Index: (conversation_id, kanban_id) UNIQUE  -> idx_kanban_items_unique
#
class KanbanItem < ApplicationRecord
  belongs_to :conversation
  belongs_to :kanban
  belongs_to :kanban_stage
  belongs_to :moved_by, class_name: 'User', optional: true

  validates :conversation_id, presence: true
  validates :kanban_id, presence: true
  validates :kanban_stage_id, presence: true
  validates :conversation_id, uniqueness: { scope: :kanban_id, message: 'already in this kanban' } # rubocop:disable Rails/I18nLocaleTexts

  before_save :stamp_last_stage_change, if: :will_save_change_to_kanban_stage_id?
  attr_accessor :previous_kanban_stage_id

  before_update :capture_previous_stage, if: :will_save_change_to_kanban_stage_id?

  # P1-13: broadcast real-time após commit. Usa o flag previous_kanban_stage_id
  # pra distinguir created/updated/moved.
  after_commit :broadcast_after_create, on: :create
  after_commit :broadcast_after_update, on: :update
  after_commit :broadcast_after_destroy, on: :destroy

  scope :by_kanban, ->(kanban_id) { where(kanban_id: kanban_id) }
  scope :by_stage, ->(stage_id) { where(kanban_stage_id: stage_id) }

  # Backward-compat: codigo antigo (specs/jbuilders) le `moved_at`. Mantido como alias
  # para a nova coluna `last_stage_change_at`. Remover em KANBAN-P0-08 apos migracao.
  def moved_at
    last_stage_change_at
  end

  def moved_at=(value)
    self.last_stage_change_at = value
  end

  private

  def stamp_last_stage_change
    self.last_stage_change_at = Time.current
  end

  def capture_previous_stage
    self.previous_kanban_stage_id = kanban_stage_id_was
  end

  def broadcast_after_create
    Kanbans::BroadcastService.new(kanban: kanban).publish_item_created(self)
  rescue StandardError => e
    Rails.logger.error("[KanbanBroadcast] item.create #{id}: #{e.message}")
  end

  def broadcast_after_update
    svc = Kanbans::BroadcastService.new(kanban: kanban)
    if previous_kanban_stage_id.present? && previous_kanban_stage_id != kanban_stage_id
      svc.publish_item_moved(self, from_stage_id: previous_kanban_stage_id)
    else
      svc.publish_item_updated(self)
    end
  rescue StandardError => e
    Rails.logger.error("[KanbanBroadcast] item.update #{id}: #{e.message}")
  end

  def broadcast_after_destroy
    return if kanban.blank?

    Kanbans::BroadcastService.new(kanban: kanban).publish_item_deleted(id)
  rescue StandardError => e
    Rails.logger.error("[KanbanBroadcast] item.destroy #{id}: #{e.message}")
  end
end
