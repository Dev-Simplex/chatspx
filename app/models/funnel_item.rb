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

  # Payload dos eventos de tempo real do board (Kanban tempo real / Fase 1).
  #
  # Antes só carregava ids + stage + moved_at, o que bastava para RELOCAR um card
  # que o receptor já tinha. Só que o receptor frequentemente NÃO tem o card
  # (paginação por cursor, coluna não carregada, filtro), e aí o evento era
  # descartado e só o F5 resolvia. Agora o payload traz o suficiente para o front
  # DESENHAR o card do zero.
  #
  # ⚠️ MANTENHA EM SINCRONIA com `app/views/api/v1/models/_funnel_item.json.jbuilder`
  # (o serializer do GET /funnel_items). São dois caminhos para o mesmo card no
  # mesmo store do front; campo que só existe num dos dois vira card "meio
  # desenhado" dependendo de como ele chegou na tela. O spec
  # `spec/models/funnel_item_push_event_data_spec.rb` trava os dois juntos.
  #
  # Diferença deliberada: `last_message` fica FORA. O listener é síncrono (roda
  # dentro do request do arraste) e a última mensagem exigiria mais uma query no
  # caminho quente. O card remoto recém-inserido nasce sem prévia de texto e
  # ganha uma no próximo `message.created` (já tratado por
  # `syncConversationFromRealtime`).
  #
  # `label_colors`: mapa `{ "titulo em minúsculas" => "#cor" }` montado UMA vez
  # pelo listener (com cache), para não fazer N+1 de Label aqui dentro.
  def push_event_data(label_colors: {})
    {
      id: id,
      funnel_id: funnel_id,
      funnel_stage_id: funnel_stage_id,
      conversation_id: conversation_id,
      # iso8601 em tudo que é tempo: o payload vira args de Sidekiq
      # (ActionCableBroadcastJob) e String é tipo JSON nativo, sem depender da
      # serialização de Time do ActiveJob.
      moved_at: moved_at&.iso8601,
      moved_by_id: moved_by_id,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601,
      # to_f: position é decimal (BigDecimal). O broadcast vira args de Sidekiq
      # (ActionCableBroadcastJob), que sob strict_args rejeita BigDecimal — Float
      # é tipo JSON nativo e tem precisão de sobra p/ ordenar no client.
      position: position&.to_f,
      is_task: task?,
      title: title,
      description: description,
      assignee_id: assignee_id,
      assignee: assignee_push_event_data,
      conversation: conversation_push_event_data(label_colors)
    }
  end

  private

  def assignee_push_event_data
    return if assignee.blank?

    { id: assignee.id, name: assignee.name, thumbnail: assignee.avatar_url }
  end

  def conversation_push_event_data(label_colors)
    return if conversation.blank?

    conversation_core_push_event_data.merge(
      custom_attributes: funnel_scoped_custom_attributes,
      labels: labels_push_event_data(label_colors),
      contact: contact_push_event_data
    )
  end

  def conversation_core_push_event_data
    conv = conversation
    {
      id: conv.id,
      display_id: conv.display_id,
      status: conv.status,
      priority: conv.priority,
      contact_id: conv.contact_id,
      inbox_id: conv.inbox_id,
      account_id: conv.account_id,
      assignee_id: conv.assignee_id,
      last_activity_at: conv.last_activity_at&.iso8601,
      waiting_since: conv.waiting_since&.iso8601
    }
  end

  def contact_push_event_data
    contact = conversation&.contact
    return if contact.blank?

    { id: contact.id, name: contact.name, phone_number: contact.phone_number, thumbnail: contact.avatar_url }
  end

  # Só os campos customizados DESTE funil (mesmo recorte do partial jbuilder).
  def funnel_scoped_custom_attributes
    (conversation.custom_attributes || {}).select { |key, _| key.to_s.start_with?("funnel_#{funnel_id}_") }
  end

  # Cor default #94a3b8 igual ao partial quando o título não está no mapa.
  def labels_push_event_data(label_colors)
    titles = conversation.cached_label_list_array
    return [] if titles.blank?

    lookup = label_colors || {}
    titles.map { |title| { title: title, color: lookup[title.to_s.downcase] || '#94a3b8' } }
  end

  def set_moved_at
    self.moved_at = Time.current
  end

  # Um cartão é uma conversa OU uma tarefa (precisa de título). Nunca vazio.
  def conversation_or_title
    return if conversation_id.present? || title.present?

    errors.add(:base, 'a card must have a conversation or a title')
  end
end
