# Seed de QA VISUAL do sino, na conta 1 do staging. Monta o par de contraste que prova a regra
# "só o último atribuído" e imprime os links para abrir no navegador.
#
#   A) conversa ATRIBUÍDA ao admin         -> mensagem nova => sino do admin TOCA (tipo 3)
#   B) conversa atribuída ao AGENTE DE      -> mensagem nova => sino do admin NÃO toca
#      TESTE, admin só PARTICIPANTE                             (é o print do bug: "Você está participando")
#                                                               e o sino do AGENTE toca
#
# O agente é criado por este script (senha conhecida, ver AGENTE_SENHA) de propósito: o cenário
# original era com uma agente REAL (Misya Correa) e resetar a senha dela para o dono poder logar a
# trancaria fora do staging. A mecânica é a mesma — o que importa é ser "atribuída a outra pessoa".
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
AGENTE_EMAIL = "#{TAG}_agente@example.com".freeze
AGENTE_SENHA = 'Test@12345678'.freeze
LIMPAR = ARGV.include?('--limpar')

account = Account.find(1)
inbox = Inbox.find(2)              # WhatsApp Vendas (Channel::Api)
admin = User.find(1)               # dev@simplexsolucoes.com.br — o dono

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

def user_fk_columns
  sql = <<-SQL.squish
    SELECT tc.table_name, kcu.column_name, c.is_nullable
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    JOIN information_schema.columns c ON c.table_name = tc.table_name AND c.column_name = kcu.column_name
    WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'users' AND ccu.column_name = 'id'
  SQL
  ActiveRecord::Base.connection.execute(sql).map { |row| [row['table_name'], row['column_name'], row['is_nullable'] == 'YES'] }
end

def limpar_conversas!(account, tag) # rubocop:disable Metrics/AbcSize
  conn = ActiveRecord::Base.connection
  ids = Conversation.where(account_id: account.id).where("additional_attributes->>'seed' = ?", tag).pluck(:id)
  return puts('   nenhuma conversa do seed.') if ids.empty?

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

def limpar_agente!(email)
  conn = ActiveRecord::Base.connection
  user_ids = User.where(email: email).pluck(:id)
  return puts('   nenhum agente do seed.') if user_ids.empty?

  list = user_ids.join(',')
  # join tables sem FK declarada
  TeamMember.where(user_id: user_ids).delete_all
  InboxMember.where(user_id: user_ids).delete_all
  ConversationParticipant.where(user_id: user_ids).delete_all
  NotificationSetting.where(user_id: user_ids).delete_all
  Notification.where(user_id: user_ids).delete_all
  AccountUser.where(user_id: user_ids).delete_all

  # FK NOT NULL -> apagar a linha. FK NULLABLE -> NULIFICAR, jamais apagar: conversations.assignee_id
  # é nullable, e um DELETE genérico levaria conversa REAL do staging junto.
  user_fk_columns.each do |table, column, nullable|
    conn.execute(
      nullable ? "UPDATE #{table} SET #{column} = NULL WHERE #{column} IN (#{list})" : "DELETE FROM #{table} WHERE #{column} IN (#{list})"
    )
  end
  User.where(id: user_ids).delete_all
  puts "   removido o agente de teste (#{email})."
end

def limpar!(account, tag, agente_email)
  limpar_conversas!(account, tag)
  limpar_agente!(agente_email)
end

if LIMPAR
  puts '== limpando o cenário de QA visual =='
  limpar!(account, TAG, AGENTE_EMAIL)
  puts 'pronto.'
  exit
end

puts '== limpando resíduo de execução anterior =='
limpar!(account, TAG, AGENTE_EMAIL)

puts
puts '== agente de teste (assignee da conversa B) =='
agente = User.create!(name: 'Agente Sino (teste)', email: AGENTE_EMAIL, password: AGENTE_SENHA, confirmed_at: Time.current)
AccountUser.create!(account: account, user: agente, role: :agent)
InboxMember.create!(inbox: inbox, user: agente)
puts "   ##{agente.id} #{agente.name} <#{agente.email}> | membro do inbox '#{inbox.name}'"

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

puts '== B) conversa atribuída ao agente, admin só participante (o print do bug) =='
conv_b = criar_conversa(account, inbox, 'Cliente Teste — SINO NAO TOCA (de outra pessoa)', TAG)
conv_b.update!(assignee: agente)
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
def notif_de(user, message)
  Notification.find_by(user_id: user.id, secondary_actor_type: 'Message', secondary_actor_id: message.id)
end

notif_a = nil
notif_b = nil
notif_b_agente = nil
fila_respondeu = false

# ⚠️ `uncached` NÃO É OPCIONAL. No `rails runner` o query cache do ActiveRecord vem LIGADO
# (verificado: `connection.query_cache_enabled == true`), e ele cacheia o MISS: a 1a consulta
# devolve nil, esse nil fica preso na conexão e toda consulta idêntica seguinte devolve nil PARA
# SEMPRE — mesmo depois de o worker ter criado a linha. Sem isto, o polling nunca enxerga a
# notificação e o relatório acusa "FALHOU" com o produto funcionando. Custou 3 execuções.
Notification.uncached do
  # Espera os DOIS sinais POSITIVOS (A->admin e B->agente). Quando ambos chegam, a fila
  # comprovadamente processou as duas mensagens — só aí a AUSÊNCIA na B (admin) quer dizer algo.
  # Ausência não se espera: sem os positivos, eu estaria medindo a lentidão da fila, não a regra.
  print '   aguardando o worker processar'
  esperou = 0
  while esperou < 180
    fila_respondeu = notif_de(admin, msg_a) && notif_de(agente, msg_b)
    break if fila_respondeu

    print '.'
    sleep 2
    esperou += 2
  end
  puts
  puts "   (fila respondeu em ~#{esperou}s)"

  notif_a = notif_de(admin, msg_a)
  notif_b = notif_de(admin, msg_b)
  notif_b_agente = notif_de(agente, msg_b)
end

unless fila_respondeu
  puts '   ATENCAO: os sinais positivos nao chegaram em 180s -> fila parada/lenta, ' \
       'o resultado abaixo NAO significa nada.'
end

puts
puts '== RESULTADO =='
resultados = {
  'A) sino do ADMIN, conversa atribuida a ELE      ' => [!notif_a.nil?, true],
  'B) sino do ADMIN, conversa atribuida a OUTRO    ' => [!notif_b.nil?, false],
  'B) sino do AGENTE, que E o assignee             ' => [!notif_b_agente.nil?, true]
}
ok = true
resultados.each do |label, (actual, expected)|
  pass = actual == expected
  ok &&= pass
  puts "   #{pass ? 'PASS' : 'FALHOU'} | #{label} -> tocou=#{actual} (esperado #{expected})"
end
puts
puts(ok ? '>>> COMPORTAMENTO CORRETO' : '>>> INESPERADO - revisar')

puts
puts '== LINKS PARA TESTE =='
puts "   Sino (Notificacoes): #{BASE_URL}/app/accounts/#{account.id}/notifications"
puts "   A) SINO TOCA   -> #{BASE_URL}/app/accounts/#{account.id}/conversations/#{conv_a.display_id}"
puts "   B) NAO TOCA    -> #{BASE_URL}/app/accounts/#{account.id}/conversations/#{conv_b.display_id}"
puts
puts '== LOGINS =='
puts "   dono/admin: #{admin.email}  (sua senha de sempre)"
puts "   agente....: #{AGENTE_EMAIL} / #{AGENTE_SENHA}"
puts '   Para remover o cenario: RAILS_ENV=production bundle exec rails runner task/sino_teste_visual.rb -- --limpar'
