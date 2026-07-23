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

  # Topo da coluna: menor position - 1 (fractional indexing). Coloca um card
  # recém-colocado no topo com um valor ÚNICO, sem renumerar a coluna inteira nem
  # cair no default 0 (que colidiria entre vários cards novos). 1 se vazia.
  # A primeira reordenação manual renumera a coluna para 1..n (ReorderService).
  #
  # ⚠️ O front PREVÊ esta regra ao arrastar entre etapas (`topPositionForStage`
  # em store/modules/kanban/actions.js) para o card não pular duas vezes. Ele não
  # copia a conta — depende só de "cartão que chega vai para o TOPO". Se esta
  # regra mudar (ex.: passar a mandar para o fim), atualize lá: o spec de JS não
  # toca o backend e a regressão passaria calada.
  def self.top_position_for(funnel_stage_id, excluding_id: nil)
    scope = where(funnel_stage_id: funnel_stage_id)
    scope = scope.where.not(id: excluding_id) if excluding_id
    min = scope.minimum(:position)
    min.nil? ? 1 : min - 1
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
      # to_f: position é decimal (BigDecimal). O broadcast vira args de Sidekiq
      # (ActionCableBroadcastJob), que sob strict_args rejeita BigDecimal — Float
      # é tipo JSON nativo e tem precisão de sobra p/ ordenar no client.
      position: position&.to_f
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
