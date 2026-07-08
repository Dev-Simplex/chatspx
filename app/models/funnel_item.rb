# frozen_string_literal: true

# == Schema Information
#
# Table name: funnel_items
#
#  id              :bigint           not null, primary key
#  moved_at        :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  conversation_id :bigint           not null
#  funnel_id       :bigint           not null
#  funnel_stage_id :bigint           not null
#  moved_by_id     :bigint
#
# Index: (conversation_id, funnel_id) UNIQUE
#
class FunnelItem < ApplicationRecord
  # conversation é opcional: um cartão pode ser uma TAREFA/LEMBRETE avulso
  # (sem conversa), com título/descrição/responsável próprios.
  belongs_to :conversation, optional: true
  belongs_to :funnel
  belongs_to :funnel_stage
  belongs_to :moved_by, class_name: 'User', optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  has_many :funnel_item_notes, dependent: :destroy

  validates :funnel_id, presence: true
  validates :funnel_stage_id, presence: true
  # allow_nil: múltiplos cartões de tarefa (conversation_id nil) coexistem.
  validates :conversation_id, uniqueness: { scope: :funnel_id, allow_nil: true, message: 'already in this funnel' } # rubocop:disable Rails/I18nLocaleTexts
  validate :conversation_or_title

  before_save :set_moved_at, if: :will_save_change_to_funnel_stage_id?

  scope :by_funnel, ->(funnel_id) { where(funnel_id: funnel_id) }
  scope :by_stage, ->(stage_id) { where(funnel_stage_id: stage_id) }
  scope :tasks, -> { where(conversation_id: nil) }

  # Cartão de tarefa = sem conversa vinculada.
  def task?
    conversation_id.blank?
  end

  # Minimal payload broadcast on a real-time move (Kanban v2 / Fase 4). The
  # receiving client relocates the item it already holds, so only ids + the
  # new stage + moved_at (for conflict resolution) are needed.
  def push_event_data
    {
      id: id,
      funnel_id: funnel_id,
      funnel_stage_id: funnel_stage_id,
      conversation_id: conversation_id,
      moved_at: moved_at,
      moved_by_id: moved_by_id,
      position: position
    }
  end

  private

  def set_moved_at
    self.moved_at = Time.current
  end

  # Um cartão é uma conversa OU uma tarefa (precisa de título). Nunca vazio.
  def conversation_or_title
    return if conversation_id.present? || title.present?

    errors.add(:base, 'a card must have a conversation or a title')
  end
end
