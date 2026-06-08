# frozen_string_literal: true

# Corrige seeds dos kanban_templates que tinham 2 stages finais com automation_type=resolved
# (uma won, outra loss) — viola validates :automation_type uniqueness scope kanban_id.
# Removemos automation_type das stages loss. Stage won mantém ambos.
class FixKanbanTemplatesAutomationTypeCollision < ActiveRecord::Migration[7.0]
  def up
    templates = connection.exec_query('SELECT id, slug, stages_config FROM kanban_templates')

    templates.each do |row|
      stages = JSON.parse(row['stages_config'])
      changed = false

      stages.each do |stage|
        if stage['automation_type'] == 'resolved' && stage['won_loss_type'] == 'loss'
          stage.delete('automation_type')
          changed = true
        end
      end

      next unless changed

      connection.exec_update(
        'UPDATE kanban_templates SET stages_config = $1::jsonb, updated_at = NOW() WHERE id = $2',
        'FixAutomationType',
        [stages.to_json, row['id']]
      )
    end
  end

  def down
    # Reverte: re-adicionar automation_type=resolved nas stages loss
    templates = connection.exec_query('SELECT id, stages_config FROM kanban_templates')

    templates.each do |row|
      stages = JSON.parse(row['stages_config'])
      changed = false

      stages.each do |stage|
        if stage['won_loss_type'] == 'loss' && stage['automation_type'].nil?
          stage['automation_type'] = 'resolved'
          changed = true
        end
      end

      next unless changed

      connection.exec_update(
        'UPDATE kanban_templates SET stages_config = $1::jsonb, updated_at = NOW() WHERE id = $2',
        'RevertFixAutomationType',
        [stages.to_json, row['id']]
      )
    end
  end
end
