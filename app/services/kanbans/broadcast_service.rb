# frozen_string_literal: true

# Publica eventos de Kanban via ActionCable após commit (KANBAN-P1-13).
#
# IMPORTANTE: chamar SEMPRE após a transação fechar — nunca dentro.
# Caso contrário o job pode rodar antes do commit e ler estado obsoleto.
class Kanbans::BroadcastService
  attr_reader :kanban

  SEQ_TTL = 7.days.to_i

  def initialize(kanban:)
    @kanban = kanban
  end

  def publish_item_created(item)
    publish('kanban_item.created', { item: serialize_item(item) })
  end

  def publish_item_updated(item)
    publish('kanban_item.updated', { item: serialize_item(item) })
  end

  def publish_item_moved(item, from_stage_id: nil)
    publish('kanban_item.moved', {
              item: serialize_item(item),
              from_stage_id: from_stage_id
            })
  end

  def publish_item_deleted(item_id)
    publish('kanban_item.deleted', { id: item_id })
  end

  def publish_stage_created(stage)
    publish('kanban_stage.created', { stage: serialize_stage(stage) })
  end

  def publish_stage_updated(stage)
    publish('kanban_stage.updated', { stage: serialize_stage(stage) })
  end

  def publish_stage_reordered(stage_ids)
    publish('kanban_stage.reordered', { kanban_id: kanban.id, stage_ids: stage_ids })
  end

  def publish_stage_deleted(stage_id)
    publish('kanban_stage.deleted', { id: stage_id })
  end

  def publish_kanban_updated
    publish('kanban.updated', { kanban: serialize_kanban(kanban) })
  end

  class << self
    def current_seq(kanban_id)
      Redis::Alfred.get(seq_key(kanban_id)).to_i
    end

    def next_seq(kanban_id)
      seq = Redis::Alfred.incr(seq_key(kanban_id))
      Redis::Alfred.expire(seq_key(kanban_id), SEQ_TTL)
      seq.to_i
    rescue StandardError
      Time.current.to_i # fallback se Redis indisponível
    end

    def seq_key(kanban_id)
      "kanban:seq:#{kanban_id}"
    end
  end

  private

  def publish(event, data)
    seq = self.class.next_seq(kanban.id)
    payload = {
      event: event,
      data: data,
      seq: seq,
      ts: Time.current.to_f
    }
    KanbanBroadcastJob.perform_later(stream_name, payload)
  end

  def stream_name
    "account_#{kanban.account_id}_kanban_#{kanban.id}"
  end

  def serialize_item(item)
    return nil if item.blank?

    item.as_json(
      only: [:id, :kanban_id, :kanban_stage_id, :conversation_id, :position, :moved_at,
             :last_stage_change_at, :metadata]
    )
  end

  def serialize_stage(stage)
    return nil if stage.blank?

    stage.as_json(
      only: [:id, :kanban_id, :name, :color, :position, :automation_type, :stage_kind, :metadata]
    )
  end

  def serialize_kanban(record)
    record.as_json(only: [:id, :name, :color, :team_id, :inbox_ids, :position])
  end
end
