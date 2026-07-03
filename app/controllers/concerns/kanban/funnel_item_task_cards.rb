# frozen_string_literal: true

# Kanban: criação/edição de cartões de TAREFA/LEMBRETE — funnel_items sem
# conversa vinculada (título/descrição/responsável próprios).
module Kanban::FunnelItemTaskCards
  extend ActiveSupport::Concern

  private

  # É um cartão de tarefa quando não veio conversa e veio um título.
  def task_card_params?
    raw_conversation_id.blank? && task_title.present?
  end

  def raw_conversation_id
    params[:conversation_id] || params.dig(:funnel_item, :conversation_id)
  end

  def task_title
    (params[:title] || params.dig(:funnel_item, :title)).to_s.strip
  end

  def create_task_card
    funnel.funnel_items.create!(
      funnel_stage: funnel_stage,
      title: task_title,
      description: params[:description] || params.dig(:funnel_item, :description),
      assignee_id: normalize_assignee(params[:assignee_id] || params.dig(:funnel_item, :assignee_id)),
      moved_by: Current.user,
      moved_at: Time.current
    )
  end

  # Atualiza campos do cartão de tarefa (mover de etapa e/ou editar conteúdo).
  def task_update_attributes
    fields = params.fetch(:funnel_item, params).permit(:funnel_stage_id, :title, :description, :assignee_id)
    attrs = { moved_by: Current.user }
    attrs[:funnel_stage_id] = fields[:funnel_stage_id] if fields[:funnel_stage_id].present?
    attrs[:title] = fields[:title].to_s.strip if fields[:title].present?
    attrs[:description] = fields[:description] if fields.key?(:description)
    attrs[:assignee_id] = normalize_assignee(fields[:assignee_id]) if fields.key?(:assignee_id)
    attrs
  end

  # Só aceita um responsável que seja usuário desta conta (senão limpa).
  def normalize_assignee(id)
    return nil if id.blank?

    Current.account.users.exists?(id: id) ? id : nil
  end

  # Cartões de tarefa (conversation_id nil): filtrados por stage quando aplicável
  # e ordenados por moved_at desc. Não sofrem dedup (cada um é único). Carregados
  # à parte porque não passam pelos joins de conversation da listagem.
  def merge_task_items(items)
    tasks = policy_scope(funnel.funnel_items).tasks.includes(:funnel_stage, :assignee)
    tasks = tasks.by_stage(params[:stage_id]) if params[:stage_id].present?
    tasks = tasks.to_a.sort_by { |i| i.moved_at || i.created_at }.reverse
    items + tasks
  end
end
