# frozen_string_literal: true

# Rede de seguranca do isolamento de mensagem por time.
#
# Quando a conversa muda de time, o Conversations::UpdateMessagesTeamIdJob deveria reetiquetar as
# mensagens (o `messages` filtra por team_id quando o inbox tem team_message_isolation, ver
# conversation.rb:147). Em 16/07/2026 encontramos conversas em producao (AGN) em que a mensagem
# ficou com o team ANTERIOR e sumiu para o time novo — inclusive o pedido original do cliente.
# O job funciona quando roda (perform_now realinhou 23/23 na conv 449) e e enfileirado tanto dentro
# quanto fora de transacao (ambos testados); o motivo de nao ter rodado NAQUELAS transicoes NAO foi
# fechado. Enquanto a causa nao e conhecida, esta task garante que o SINTOMA nao chega no cliente:
# nao depende de entender o mecanismo, so de comparar estado.
#
# Idempotente e barata: um SELECT indexado acha as divergentes (zero em regime normal) e so entao
# roda o job. Segura para cron.
#
#   bundle exec rails messages:reconcile_team_id              # corrige
#   DRY_RUN=true bundle exec rails messages:reconcile_team_id # so relata

# So interessa onde o isolamento de fato esconde: sem ele o `messages` devolve tudo e um team_id
# divergente e inofensivo (a 8.229 tem ~8k assim, sem impacto algum).
def reconcile_divergent_conversations
  inbox_ids = Inbox.where(team_message_isolation: true).pluck(:id)
  return [] if inbox_ids.empty?

  ActiveRecord::Base.connection.select_all(
    ActiveRecord::Base.sanitize_sql_array(
      [
        'SELECT DISTINCT c.id, c.display_id, c.account_id FROM conversations c ' \
        'JOIN messages m ON m.conversation_id = c.id ' \
        'WHERE c.inbox_id IN (?) AND c.team_id IS NOT NULL ' \
        'AND m.team_id IS NOT NULL AND m.team_id <> c.team_id ORDER BY c.id',
        inbox_ids
      ]
    )
  ).to_a
end

def reconcile_conversation(row, dry_run)
  conversation = Conversation.find_by(id: row['id'])
  return false if conversation.blank?

  hidden = conversation.all_messages.count - conversation.messages.count
  puts "  acct=#{row['account_id']} conv=#{row['display_id']} escondidas=#{hidden}"
  return false if dry_run

  Conversations::UpdateMessagesTeamIdJob.perform_now(conversation.id)
  true
end

namespace :messages do
  desc 'Realinha o team_id das mensagens ao team da conversa (so onde o isolamento por time esconde)'
  task reconcile_team_id: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', false))
    rows = reconcile_divergent_conversations

    if rows.empty?
      puts '[reconcile_team_id] nada divergente'
    else
      puts "[reconcile_team_id] #{rows.size} conversa(s) divergente(s)#{dry_run ? ' (DRY_RUN)' : ''}"
      fixed = rows.count { |row| reconcile_conversation(row, dry_run) }
      puts "[reconcile_team_id] #{dry_run ? 'nada alterado (DRY_RUN)' : "#{fixed} conversa(s) realinhada(s)"}"
    end
  end
end
