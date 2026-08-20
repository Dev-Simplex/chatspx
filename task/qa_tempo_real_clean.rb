# frozen_string_literal: true

# Limpa o cenário de QA do Kanban em tempo real (task/qa_tempo_real_seed.rb).
#
# ⚠️ Apagar conversa de seed NÃO é só `destroy!`: há tabelas que referenciam
# `conversations` por FK sem `dependent:` no modelo (a primeira a barrar aqui foi
# `conversation_assignment_histories`). Em vez de listar essas tabelas na mão —
# a lista muda a cada feature — varremos o `information_schema` atrás de TODA FK
# que aponte para conversations/contacts e limpamos as linhas das nossas ids
# antes de destruir. Ver a memória "qa-seed-delete-fk-sweep".
#
# Uso:  RAILS_ENV=production bundle exec rails runner task/qa_tempo_real_clean.rb
#       RAILS_ENV=production bundle exec rails runner task/qa_tempo_real_clean.rb -- --dry-run
$stdout.sync = true

TAG = 'qa_tempo_real'
SEED_SQL = "additional_attributes->>'seed' = ?"
DRY = ARGV.include?('--dry-run')
TEAM_NAME = 'qa tempo real' # o modelo Team força minúsculas

account = Account.find(1)
team = account.teams.find_by(name: TEAM_NAME)
funnel = team && Funnel.find_by(team_id: team.id, account_id: account.id)
inbox = account.inboxes.find_by(name: 'QA Tempo Real')
conversas = account.conversations.where(SEED_SQL, TAG)
contatos = account.contacts.where(SEED_SQL, TAG)

puts "#{DRY ? '[dry-run] ' : ''}a remover:"
puts "  cartões do funil: #{funnel ? funnel.funnel_items.count : 0}"
puts "  conversas: #{conversas.count}"
puts "  contatos: #{contatos.count}"
puts "  inbox: #{inbox&.id.inspect}  funil: #{funnel&.id.inspect}  time: #{team&.id.inspect}"

# Tabelas que referenciam `alvo` por FK (exceto a própria).
def referencing_tables(alvo)
  ActiveRecord::Base.connection.exec_query(<<~SQL.squish, 'fk-sweep', [alvo]).to_a
    SELECT tc.table_name AS tabela, kcu.column_name AS coluna
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND ccu.table_name = $1
      AND tc.table_name <> $1
  SQL
end

# RECURSIVA de propósito: apagar as linhas que apontam para o alvo não basta se
# ELAS também forem alvo de FK (foi o que aconteceu com
# team → internal_channels → internal_channel_members). Desce até 4 níveis, o
# suficiente para qualquer cadeia daqui e ainda assim um limite.
def sweep!(alvo, ids, profundidade = 0)
  return if ids.blank? || profundidade > 3

  referencing_tables(alvo).each do |fk|
    tabela = fk['tabela']
    coluna = fk['coluna']
    lista = ids.join(',')

    filhos = begin
      ActiveRecord::Base.connection.select_values("SELECT id FROM #{tabela} WHERE #{coluna} IN (#{lista})")
    rescue ActiveRecord::StatementInvalid
      [] # tabela de junção, sem coluna id — nada a descer
    end
    sweep!(tabela, filhos, profundidade + 1) if filhos.any?

    quantidade = ActiveRecord::Base.connection.exec_delete("DELETE FROM #{tabela} WHERE #{coluna} IN (#{lista})", 'fk-sweep')
    puts "    #{'  ' * profundidade}#{tabela}.#{coluna}: #{quantidade} linhas" if quantidade.positive?
  end
end

if DRY
  puts "\n  tabelas que referenciam conversations: #{referencing_tables('conversations').pluck('tabela').uniq.sort.join(', ')}"
  exit 0
end

funnel&.funnel_items&.find_each(&:destroy!)
puts 'cartões removidos'

conversa_ids = conversas.pluck(:id)
puts '  varrendo FKs de conversations…'
sweep!('conversations', conversa_ids)
conversas.find_each(&:destroy!)
puts 'conversas removidas'

contato_ids = contatos.pluck(:id)
puts '  varrendo FKs de contacts…'
sweep!('contacts', contato_ids)
contatos.find_each(&:destroy!)
puts 'contatos removidos'

# `inbox.destroy!` passa por `dependent: :destroy` de Campaign, e o modelo Campaign
# está quebrado NESTE banco (enum sem coluna — resquício das migrations fantasma
# do staging). Então: tenta o caminho normal e, se ele explodir por causa disso,
# cai na varredura de FK + DELETE direto, que é seguro para dado de seed.
def destruir(registro, rotulo, tabela)
  return if registro.nil?

  registro.destroy!
  puts "#{rotulo} removid#{rotulo.start_with?('inbox') ? 'a' : 'o'}"
rescue StandardError => e
  puts "  #{rotulo}: destroy! falhou (#{e.class}) — caindo para varredura + DELETE"
  sweep!(tabela, [registro.id])
  ActiveRecord::Base.connection.exec_delete("DELETE FROM #{tabela} WHERE id = #{registro.id}", 'clean')
  puts "#{rotulo} removid#{rotulo.start_with?('inbox') ? 'a' : 'o'} (via SQL)"
end

destruir(inbox, 'inbox', 'inboxes')
# O funil sairia junto com o time (dependent: :destroy), mas vai antes para não
# ficar órfão caso o time barre em alguma FK inesperada.
destruir(funnel, 'funil', 'funnels')
destruir(team, 'time', 'teams')

puts "\nsobrou de #{TAG}: conversas=#{account.conversations.where(SEED_SQL, TAG).count} contatos=#{account.contacts.where(SEED_SQL, TAG).count}"
