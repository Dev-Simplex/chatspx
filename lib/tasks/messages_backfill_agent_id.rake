# frozen_string_literal: true

# rake messages:backfill_agent_id                # roda em todas as contas
# rake messages:backfill_agent_id[6]             # roda apenas na account 6
#
# Carimba messages.agent_id = sender_id nas mensagens OUTGOING enviadas por User
# (agentes), preenchendo o historico anterior ao deploy do isolamento por agente.
# Idempotente: so toca em linhas com agent_id NULL -> pode rodar varias vezes.
# Diferente do team_id, agent_id NAO e re-sincronizado (sem job): e fixado no envio.
#
# IMPORTANTE: rodar ANTES de ligar o toggle agent_message_isolation num inbox; senao
# as mensagens antigas ficam publicas (agent_id NULL) ate o backfill terminar (fail-open).
namespace :messages do
  desc 'Backfill messages.agent_id a partir do sender_id (outgoing de User)'
  task :backfill_agent_id, %i[account_id] => :environment do |_t, args|
    account_id = args[:account_id]&.to_i

    scope = Message.where(sender_type: 'User', message_type: :outgoing, agent_id: nil)
    scope = scope.where(account_id: account_id) if account_id

    total = scope.count
    puts "[messages:backfill_agent_id] Mensagens a preencher: #{total} (account_id=#{account_id || 'ALL'})"
    next if total.zero?

    updated = 0
    scope.in_batches(of: 10_000) do |batch|
      updated += batch.update_all('agent_id = sender_id') # rubocop:disable Rails/SkipsModelValidations
      puts "[messages:backfill_agent_id] #{updated}/#{total} atualizadas..."
    end

    puts "[messages:backfill_agent_id] Concluido. #{updated} mensagens carimbadas."
  end
end
