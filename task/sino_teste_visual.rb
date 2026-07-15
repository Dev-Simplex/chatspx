# Seed de QA VISUAL do sino, na conta 1 do staging. Monta o par de contraste que prova a regra
# "só o último atribuído" e imprime os links para abrir no navegador.
#
#   A) conversa ATRIBUÍDA ao admin        -> mensagem nova  => sino TOCA   (tipo 3)
#   B) conversa atribuída à Misya Correa,  -> mensagem nova  => sino NÃO toca
#      admin só PARTICIPANTE                                    (é o print do bug: "Você está participando")
#
# O caminho é o REAL: cria a mensagem e deixa o dispatcher/listener/Sidekiq rodarem. Não chama o
# service na mão — assim o teste valida a fiação inteira, não só a regra.
#
# Uso:  RAILS_ENV=production rails runner task/sino_teste_visual.rb            -> cria + relatório
#       RAILS_ENV=production rails runner task/sino_teste_visual.rb -- --limpar -> remove o cenário
#
# Nada é apagado sem --limpar. O --limpar só toca no que tem additional_attributes.seed = TAG.

$stdout.sync = true # senão uma exceção mata o processo antes do flush e o relatório some

TAG = 'sino_teste_visual'.freeze
BASE_URL = 'https://nicolas.chatspx.app'.freeze
LIMPAR = ARGV.include?('--limpar')

account = Account.find(1)
inbox = Inbox.find(2)              # WhatsApp Vendas (Channel::Api)
admin = User.find(1)               # dev@simplexsolucoes.com.br — o dono
outra_agente = User.find(4)        # Misya Correa — a agente do print do bug

# Apagar via SQL/catálogo do PG: has_many sem :dependent NULIFICA a FK, e conversation_id é NOT NULL.
def conversation_child_tables
  sql = <<-SQL.squish
    SELECT tc.table_name, kcu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'conversations' AND ccu.column_name = 'id'
  SQL
  ActiveRecord::Base.connection.execute(sql).map { |row| [row['table_name'], row['column_name']] }
end

def limpar!(account, tag) # rubocop:disable Metrics/AbcSize
  conn = ActiveRecord::Base.connection
  ids = Conversation.where(account_id: account.id).where("additional_attributes->>'seed' = ?", tag).pluck(:id)
  return puts('   nada para limpar.') if ids.empty?

  list = ids.join(',')
  message_ids = Message.where(conversation_id: ids).pluck(:id)
  Notification.where(secondary_actor_type: 'Message', secondary_actor_id: message_ids).delete_all if message_ids.any?
  Notification.where(primary_actor_type: 'Conversation', primary_actor_id: ids).delete_all
  conversation_child_tables.each { |table, column| conn.execute("DELETE FROM #{table} WHERE #{column} IN (#{list})") }

  contact_ids = Conversation.where(id: ids).pluck(:contact_id).compact.uniq
  contact_inbox_ids = Conversation.where(id: ids).pluck(:contact_inbox_id).compact.uniq
  Conversation.where(id: ids).delete_all
  ContactInbox.where(id: contact_inbox_ids).delete_all if contact_inbox_ids.any?
  Contact.where(id: contact_ids).delete_all if contact_ids.any?
  puts "   removidas #{ids.size} conversas do seed."
end

if LIMPAR
  puts '== limpando o cenário de QA visual =='
  limpar!(account, TAG)
  puts 'pronto.'
  exit
end

puts '== limpando resíduo de execução anterior =='
limpar!(account, TAG)

def criar_conversa(account, inbox, nome, tag)
  contact = Contact.create!(account: account, name: nome, phone_number: "+5599#{rand(10**8)}")
  contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                       additional_attributes: { 'seed' => tag })
end

puts
puts '== A) conversa ATRIBUÍDA ao admin =='
conv_a = criar_conversa(account, inbox, 'Cliente Teste — SINO TOCA (atribuida a voce)', TAG)
conv_a.update!(assignee: admin)
conv_a.reload
puts "   conv ##{conv_a.display_id} | assignee=#{conv_a.assignee&.name} | team=#{conv_a.team&.name.inspect}"

puts '== B) conversa atribuída à Misya, admin só participante (o print do bug) =='
conv_b = criar_conversa(account, inbox, 'Cliente Teste — SINO NAO TOCA (de outra pessoa)', TAG)
conv_b.update!(assignee: outra_agente)
conv_b.reload
# É o que o ParticipationListener faz a cada assignee_changed — e nunca desfaz.
ConversationParticipant.find_or_create_by!(conversation: conv_b, user: admin)
puts "   conv ##{conv_b.display_id} | assignee=#{conv_b.assignee&.name} | team=#{conv_b.team&.name.inspect}"
puts "   participantes: #{conv_b.conversation_participants.map { |p| p.user.name }.inspect}"

puts
puts '== mensagem nova do cliente nas duas (caminho REAL: listener + Sidekiq) =='
msg_a = Message.create!(account: account, inbox: inbox, conversation: conv_a, message_type: :incoming,
                        content: 'Oi! Esta conversa esta ATRIBUIDA a voce - o sino DEVE tocar.', sender: conv_a.contact)
msg_b = Message.create!(account: account, inbox: inbox, conversation: conv_b, message_type: :incoming,
                        content: 'Oi! Esta conversa e da Misya - voce so participa, o sino NAO deve tocar.',
                        sender: conv_b.contact)

# O NotificationListener está no dispatcher ASSÍNCRONO -> quem cria a notificação é o worker.
def notif_do_admin(admin, message)
  Notification.find_by(user_id: admin.id, secondary_actor_type: 'Message', secondary_actor_id: message.id)
end

# O worker leva bem mais que alguns segundos em fila movimentada — com janela curta o relatório
# acusava "INESPERADO" só por impaciência. Espera A chegar e dá uma folga pro job de B rodar; a
# AUSÊNCIA de notificação (B) não dá pra "esperar", só dá pra medir depois que a fila andou.
print '   aguardando o worker processar'
60.times do
  break if notif_do_admin(admin, msg_a)

  print '.'
  sleep 1
end
puts
sleep 3 # folga: se o job de A rodou, o de B (enfileirado junto) já rodou também

notif_a = notif_do_admin(admin, msg_a)
notif_b = notif_do_admin(admin, msg_b)

puts
puts '== RESULTADO (sino do admin) =='
puts "   A) atribuida a voce   -> notificou=#{!notif_a.nil?} #{notif_a ? "(tipo: #{notif_a.notification_type})" : ''} (esperado: SIM)"
puts "   B) atribuida a Misya  -> notificou=#{!notif_b.nil?} (esperado: NAO)"
ok = !notif_a.nil? && notif_b.nil?
puts
puts(ok ? '>>> COMPORTAMENTO CORRETO' : '>>> INESPERADO - revisar')

puts
puts '== LINKS PARA TESTE =='
puts "   Sino (Notificacoes): #{BASE_URL}/app/accounts/#{account.id}/notifications"
puts "   A) SINO TOCA   -> #{BASE_URL}/app/accounts/#{account.id}/conversations/#{conv_a.display_id}"
puts "   B) NAO TOCA    -> #{BASE_URL}/app/accounts/#{account.id}/conversations/#{conv_b.display_id}"
puts
puts "   Login: #{admin.email}"
puts '   Para remover o cenario: RAILS_ENV=production bundle exec rails runner task/sino_teste_visual.rb -- --limpar'
