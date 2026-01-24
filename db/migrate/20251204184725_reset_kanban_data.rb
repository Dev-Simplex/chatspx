# frozen_string_literal: true

class ResetKanbanData < ActiveRecord::Migration[7.1]
  def up
    # Verificar se as tabelas existem antes de tentar deletar
    if table_exists?(:funnel_items)
      execute "DELETE FROM funnel_items;"
    end
    
    if table_exists?(:funnel_stages)
      execute "DELETE FROM funnel_stages;"
    end
    
    if table_exists?(:funnels)
      execute "DELETE FROM funnels;"
    end
    
    # Resetar sequências se necessário
    if table_exists?(:funnels)
      begin
        execute "SELECT setval(pg_get_serial_sequence('funnels', 'id'), 1, false);"
      rescue StandardError
        # Ignorar se a sequência não existir
      end
    end
    
    if table_exists?(:funnel_stages)
      begin
        execute "SELECT setval(pg_get_serial_sequence('funnel_stages', 'id'), 1, false);"
      rescue StandardError
        # Ignorar se a sequência não existir
      end
    end
    
    if table_exists?(:funnel_items)
      begin
        execute "SELECT setval(pg_get_serial_sequence('funnel_items', 'id'), 1, false);"
      rescue StandardError
        # Ignorar se a sequência não existir
      end
    end
  end

  def down
    # Não há como reverter a exclusão de dados
    raise ActiveRecord::IrreversibleMigration
  end
end
