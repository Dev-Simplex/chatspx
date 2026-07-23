# Seed de QA VISUAL do sino, na conta 1 do staging. Monta o trio de contraste que prova a regra
# "só o último atribuído" e imprime os links/logins para abrir no navegador.
#
#   A) atribuída ao DONO (admin real)      -> sino do DONO toca          (ele confere com o login dele)
#   B) atribuída ao AGENTE; dono e admin   -> sino do AGENTE toca,
#      de teste são só PARTICIPANTES          e o de NINGUÉM mais        (é o print do bug reportado)
#   C) atribuída ao ADMIN DE TESTE         -> sino do ADMIN DE TESTE toca
#
# Por que existe um "admin de teste": o dono quer VER a prova, mas ninguém tem a senha dele e a
# agente do print original (Misya Correa) é uma pessoa REAL — resetar a senha dela a trancaria fora
# do staging. O admin de teste tem o MESMO papel (administrator) e a regra não abre exceção para
# admin (D4), então ele reproduz o caso do dono e dá para logar e fotografar.
#
# O par que fecha a prova é B x C no MESMO login (admin de teste): o sino mostra C e NÃO mostra B.
# Bell vazio não provaria nada (poderia ser usuário sem acesso); "mostra uma e não mostra a outra" prova.
#
# O caminho é o REAL: cria a mensagem e deixa o dispatcher/listener/Sidekiq rodarem. Não chama o
# service na mão — assim o teste valida a fiação inteira, não só a regra.
#
# Uso:  RAILS_ENV=production rails runner task/sino_teste_visual.rb            -> cria + relatório
#       RAILS_ENV=production rails runner task/sino_teste_visual.rb -- --limpar -> remove o cenário
#
# Nada é apagado sem --limpar, que só toca no que tem additional_attributes.seed = TAG e nos
# usuários com e-mail começando em TAG.

$stdout.sync = true # senão uma exceção mata o processo antes do flush e o relatório some

TAG = 'sino_teste_visual'.freeze
BASE_URL = 'https://nicolas.chatspx.app'.freeze
AGENTE_EMAIL = "#{TAG}_agente@example.com".freeze
ADMIN_EMAIL = "#{TAG}_admin@example.com".freeze
SENHA = 'Test@12345678'.freeze
LIMPAR = ARGV.include?('--limpar')

account = Account.find(1)
inbox = Inbox.find(2)              # WhatsApp Vendas (Channel::Api)
dono = User.find(1)                # dev@simplexsolucoes.com.br — o admin real

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

def limpar_usuarios!(tag)
  conn = ActiveRecord::Base.connection
  user_ids = User.where('email LIKE ?', "#{tag}%").pluck(:id)
  return puts('   nenhum usuário do seed.') if user_ids.empty?

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
  puts "   removidos #{user_ids.size} usuários de teste."
end

def limpar!(account, tag)
  limpar_conversas!(account, tag)
  limpar_usuarios!(tag)
end

if LIMPAR
  puts '== limpando o cenário de QA visual =='
  limpar!(account, TAG)
  puts 'pronto.'
  exit
end

puts '== limpando resíduo de execução anterior =='
limpar!(account, TAG)

def criar_usuario(account, inbox, nome:, email:, papel:)
  user = User.create!(name: nome, email: email, password: SENHA, confirmed_at: Time.current)
  AccountUser.create!(account: account, user: user, role: papel)
  InboxMember.create!(inbox: inbox, user: user)
  user
end

def criar_conversa(account, inbox, nome, tag)
  contact = Contact.create!(account: account, name: nome, phone_number: "+5599#{rand(10**8)}")
  contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                       additional_attributes: { 'seed' => tag })
end

puts
puts '== usuários de teste =='
agente = criar_usuario(account, inbox, nome: 'Agente Sino (teste)', email: AGENTE_EMAIL, papel: :agent)
admin_teste = criar_usuario(account, inbox, nome: 'Admin Sino (teste)', email: ADMIN_EMAIL, papel: :administrator)
puts "   ##{agente.id} #{agente.name} <#{agente.email}> (agent)"
puts "   ##{admin_teste.id} #{admin_teste.name} <#{admin_teste.email}> (administrator)"

puts
puts '== A) conversa ATRIBUÍDA ao dono (admin real) =='
conv_a = criar_conversa(account, inbox, 'A - SINO DO DONO TOCA (atribuida a voce)', TAG)
conv_a.update!(assignee: dono)
puts "   conv ##{conv_a.reload.display_id} | assignee=#{conv_a.assignee&.name}"

puts '== B) conversa atribuída ao AGENTE; dono e admin de teste só PARTICIPAM (o print do bug) =='
conv_b = criar_conversa(account, inbox, 'B - SINO NAO TOCA (de outra pessoa, voce so participa)', TAG)
conv_b.update!(assignee: agente)
conv_b.reload
# É o que o ParticipationListener faz a cada assignee_changed — e nunca desfaz.
ConversationParticipant.find_or_create_by!(conversation: conv_b, user: dono)
ConversationParticipant.find_or_create_by!(conversation: conv_b, user: admin_teste)
puts "   conv ##{conv_b.display_id} | assignee=#{conv_b.assignee&.name}"
puts "   participantes: #{conv_b.conversation_participants.map { |p| p.user.name }.inspect}"

puts '== C) conversa ATRIBUÍDA ao admin de teste (o contraste dele) =='
conv_c = criar_conversa(account, inbox, 'C - SINO DO ADMIN DE TESTE TOCA (atribuida a ele)', TAG)
conv_c.update!(assignee: admin_teste)
puts "   conv ##{conv_c.reload.display_id} | assignee=#{conv_c.assignee&.name}"

puts
puts '== mensagem nova do cliente nas três (caminho REAL: listener + Sidekiq) =='
msg_a = Message.create!(account: account, inbox: inbox, conversation: conv_a, message_type: :incoming,
                        content: 'Mensagem A: esta conversa e SUA (atribuida a voce) - o sino DEVE tocar.',
                        sender: conv_a.contact)
msg_b = Message.create!(account: account, inbox: inbox, conversation: conv_b, message_type: :incoming,
                        content: 'Mensagem B: esta conversa e do AGENTE - voce so participa, o sino NAO deve tocar.',
                        sender: conv_b.contact)
msg_c = Message.create!(account: account, inbox: inbox, conversation: conv_c, message_type: :incoming,
                        content: 'Mensagem C: esta conversa e do ADMIN DE TESTE - o sino DELE deve tocar.',
                        sender: conv_c.contact)

def notif_de(user, message)
  Notification.find_by(user_id: user.id, secondary_actor_type: 'Message', secondary_actor_id: message.id)
end

notifs = {}
fila_respondeu = false

# ⚠️ `uncached` NÃO É OPCIONAL. No `rails runner` o query cache do ActiveRecord vem LIGADO
# (verificado: `connection.query_cache_enabled == true`), e ele cacheia o MISS: a 1a consulta
# devolve nil, esse nil fica preso na conexão e toda consulta idêntica seguinte devolve nil PARA
# SEMPRE — mesmo depois de o worker ter criado a linha. Sem isto, o polling nunca enxerga a
# notificação e o relatório acusa "FALHOU" com o produto funcionando. Custou 3 execuções.
Notification.uncached do
  # Espera os sinais POSITIVOS (A->dono, B->agente, C->admin de teste). Quando os três chegam, a fila
  # comprovadamente processou as três mensagens — só aí a AUSÊNCIA em B quer dizer algo. Ausência não
  # se espera: sem os positivos, eu estaria medindo a lentidão da fila, não a regra.
  print '   aguardando o worker processar'
  esperou = 0
  while esperou < 180
    fila_respondeu = notif_de(dono, msg_a) && notif_de(agente, msg_b) && notif_de(admin_teste, msg_c)
    break if fila_respondeu

    print '.'
    sleep 2
    esperou += 2
  end
  puts
  puts "   (fila respondeu em ~#{esperou}s)"

  notifs = {
    'A) sino do DONO, conversa atribuida a ELE      ' => [!notif_de(dono, msg_a).nil?, true],
    'B) sino do DONO, conversa de OUTRO (participa) ' => [!notif_de(dono, msg_b).nil?, false],
    'B) sino do ADMIN DE TESTE, conversa de OUTRO   ' => [!notif_de(admin_teste, msg_b).nil?, false],
    'B) sino do AGENTE, que E o assignee            ' => [!notif_de(agente, msg_b).nil?, true],
    'C) sino do ADMIN DE TESTE, atribuida a ELE     ' => [!notif_de(admin_teste, msg_c).nil?, true]
  }
end

unless fila_respondeu
  puts '   ATENCAO: os sinais positivos nao chegaram em 180s -> fila parada/lenta, ' \
       'o resultado abaixo NAO significa nada.'
end

puts
puts '== RESULTADO =='
ok = true
notifs.each do |label, (actual, expected)|
  pass = actual == expected
  ok &&= pass
  puts "   #{pass ? 'PASS' : 'FALHOU'} | #{label} -> tocou=#{actual} (esperado #{expected})"
end
puts
puts(ok ? '>>> COMPORTAMENTO CORRETO' : '>>> INESPERADO - revisar')

puts
puts '== LINKS =='
puts "   Sino: #{BASE_URL}/app/accounts/#{account.id}/notifications"
puts "   A) #{BASE_URL}/app/accounts/#{account.id}/conversations/#{conv_a.display_id}  (sua)"
puts "   B) #{BASE_URL}/app/accounts/#{account.id}/conversations/#{conv_b.display_id}  (do agente)"
puts "   C) #{BASE_URL}/app/accounts/#{account.id}/conversations/#{conv_c.display_id}  (do admin de teste)"
puts
puts '== LOGINS =='
puts "   dono.........: #{dono.email}  (sua senha de sempre)"
puts "   agente.......: #{AGENTE_EMAIL} / #{SENHA}"
puts "   admin teste..: #{ADMIN_EMAIL} / #{SENHA}"
puts
puts '   No login do ADMIN DE TESTE o sino mostra a C e NAO mostra a B -> e a prova (mesmo papel que voce).'
puts '   Para remover: RAILS_ENV=production bundle exec rails runner task/sino_teste_visual.rb -- --limpar'
