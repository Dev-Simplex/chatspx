# frozen_string_literal: true

# rake messages:resync_team_id                # roda em todas as contas
# rake messages:resync_team_id[6]             # roda apenas na account 6
# rake messages:resync_team_id[6,inline]      # executa inline (sincrono) — util pra batch pequeno
#
# Encontra conversas onde o team_id da mensagem nao bate com o team_id da conversa
# e enfileira UpdateMessagesTeamIdJob (com a versao idempotente que le team_id atual).
# Sem o job idempotente da Task D, multiplas execucoes podiam dar resultado inconsistente.
namespace :messages do
  desc 'Resync team_id de mensagens para o team_id atual da conversa'
  task :resync_team_id, %i[account_id mode] => :environment do |_t, args|
    account_id = args[:account_id]&.to_i
    mode = args[:mode] || 'async'

    sql = <<~SQL.squish
      SELECT DISTINCT c.id AS conv_id, c.account_id, c.display_id
      FROM conversations c
      JOIN messages m ON m.conversation_id = c.id
      WHERE m.team_id IS DISTINCT FROM c.team_id
      #{account_id ? 'AND c.account_id = :acc_id' : ''}
      ORDER BY c.id
    SQL

    rows = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, { acc_id: account_id }])
    ).rows

    total = rows.size
    puts "[messages:resync_team_id] Conversas com team_id mismatch: #{total} (mode=#{mode}, account_id=#{account_id || 'ALL'})"
    next if total.zero?

    rows.each_with_index do |(conv_id, acc_id, display_id), idx|
      if mode == 'inline'
        Conversations::UpdateMessagesTeamIdJob.new.perform(conv_id)
      else
        Conversations::UpdateMessagesTeamIdJob.perform_later(conv_id)
      end
      puts "[#{idx + 1}/#{total}] account=#{acc_id} conv=#{conv_id} display=#{display_id} #{mode == 'inline' ? '[OK]' : '[enfileirado]'}"
    end

    puts "[messages:resync_team_id] Concluido. #{total} conversas processadas."
  end
end
