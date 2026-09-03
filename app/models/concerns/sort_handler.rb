module SortHandler
  extend ActiveSupport::Concern

  # O desempate por `id` nao e cosmetico: a paginacao por cursor do ConversationFinder
  # compara a tupla (last_activity_at, id), entao o ORDER BY precisa ter a mesma ordem
  # total. Sem ele, conversas com o mesmo horario sao puladas ou repetidas entre paginas.
  # O indice idx_conv_list_keyset ja termina em (last_activity_at DESC, id DESC).

  class_methods do
    def sort_on_last_activity_at(sort_direction = :desc)
      order(last_activity_at: sort_direction, id: sort_direction)
    end

    def sort_on_created_at(sort_direction = :asc)
      order(created_at: sort_direction, id: sort_direction)
    end

    def sort_on_priority(sort_direction = :desc)
      order(generate_sql_query("priority #{sort_direction.to_s.upcase} NULLS LAST, last_activity_at DESC, #{table_name}.id DESC"))
    end

    def sort_on_priority_created_at(sort_direction = :desc)
      order(generate_sql_query("priority #{sort_direction.to_s.upcase} NULLS LAST, created_at ASC, #{table_name}.id ASC"))
    end

    def sort_on_waiting_since(sort_direction = :asc)
      order(generate_sql_query("waiting_since #{sort_direction.to_s.upcase} NULLS LAST, created_at ASC, #{table_name}.id ASC"))
    end

    def last_messaged_conversations
      Message.except(:order).select(
        'DISTINCT ON (conversation_id) conversation_id, id, created_at, message_type'
      ).order('conversation_id, created_at DESC')
    end

    def sort_on_last_user_message_at
      order('grouped_conversations.message_type', 'grouped_conversations.created_at ASC')
    end

    private

    def generate_sql_query(query)
      Arel::Nodes::SqlLiteral.new(sanitize_sql_for_order(query))
    end
  end
end
