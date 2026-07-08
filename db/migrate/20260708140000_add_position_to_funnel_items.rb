# frozen_string_literal: true

# P1 do plano task/kanban-db-restructure.md — ordenação persistida de cartões.
#
# funnel_items não tinha coluna de ordem: a reordenação manual dentro da coluna era
# só client-side e não sobrevivia a reload. Adiciona `position` (decimal para
# fractional indexing — mesma escolha do desenho morto kanban_items: permite inserir
# um cartão entre dois vizinhos sem renumerar a coluna inteira).
#
# Backfill: numera cada stage por recência DESC (last_activity_at da conversa, com
# fallback moved_at/created_at para cartões-tarefa), de modo que position ASC == a
# ordem que o board já exibe hoje. Assim a virada para ordenação por position é
# INVISÍVEL até o primeiro reorder manual.
class AddPositionToFunnelItems < ActiveRecord::Migration[7.1]
  def up
    add_column :funnel_items, :position, :decimal, precision: 20, scale: 10, default: 0, null: false
    add_index :funnel_items, %i[funnel_stage_id position], name: 'index_funnel_items_on_stage_and_position'

    execute(<<~SQL.squish)
      UPDATE funnel_items fi
      SET position = sub.rn
      FROM (
        SELECT fi2.id,
               ROW_NUMBER() OVER (
                 PARTITION BY fi2.funnel_stage_id
                 ORDER BY COALESCE(c.last_activity_at, fi2.moved_at, fi2.created_at) DESC, fi2.id DESC
               ) AS rn
        FROM funnel_items fi2
        LEFT JOIN conversations c ON c.id = fi2.conversation_id
      ) sub
      WHERE fi.id = sub.id
    SQL
  end

  def down
    remove_index :funnel_items, name: 'index_funnel_items_on_stage_and_position', if_exists: true
    remove_column :funnel_items, :position
  end
end
