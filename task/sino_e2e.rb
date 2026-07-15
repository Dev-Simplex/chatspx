# E2E do sino, na conta 1 do staging.
# Regra vigente: mensagem nova notifica SÓ o assignee (o último atribuído). Prova que:
#   1. o ex-assignee de outro time NÃO recebe sino de mensagem nova
#   2. o assignee atual recebe                                        (não regrediu)
#   3. o participante SEM time NÃO recebe                             (D1)
#   4. o admin participante NÃO recebe                                (D1/D4 — a queixa do dono)
#   5. conversa SEM assignee não notifica ninguém                     (D2)
#   6. @menção AINDA notifica                                         (D3 — não pode ter morrido junto)
#   7. o script de limpeza ACHA a tipo-5 legada, inclusive a do admin (F2)
#
# Uso:  rails runner sino_e2e.rb            -> seed + asserts + limpa tudo
#       rails runner sino_e2e.rb -- --keep  -> deixa o cenário de pé para QA visual

$stdout.sync = true # senão uma exceção mata o processo antes do flush e o relatório some

KEEP = ARGV.include?('--keep')
TAG = 'sino_e2e'.freeze

account = Account.find(1)
inbox = Inbox.find(2)          # WhatsApp Vendas (Channel::Api)
team_vendas = Team.find(2)
team_suporte = Team.find(3)

# Apagar via SQL direto, não pela associação: has_many sem :dependent faz delete_all NULIFICAR a FK,
# e conversation_id é NOT NULL. Os filhos vêm do catálogo do PG (12 tabelas apontam pra conversations,
# incluindo funnel_items/nps_responses/conversation_assignment_histories) — não adianta chutar.
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

def cleanup!(account, tag) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
  conn = ActiveRecord::Base.connection
  conversation_ids = Conversation.where(account_id: account.id)
                                 .where("additional_attributes->>'seed' = ?", tag).pluck(:id)

  if conversation_ids.any?
    list = conversation_ids.join(',')
    message_ids = Message.where(conversation_id: conversation_ids).pluck(:id)
    Notification.where(secondary_actor_type: 'Message', secondary_actor_id: message_ids).delete_all if message_ids.any?
    Notification.where(primary_actor_type: 'Conversation', primary_actor_id: conversation_ids).delete_all
    conversation_child_tables.each { |table, column| conn.execute("DELETE FROM #{table} WHERE #{column} IN (#{list})") }

    contact_ids = Conversation.where(id: conversation_ids).pluck(:contact_id).compact.uniq
    contact_inbox_ids = Conversation.where(id: conversation_ids).pluck(:contact_inbox_id).compact.uniq
    Conversation.where(id: conversation_ids).delete_all
    ContactInbox.where(id: contact_inbox_ids).delete_all if contact_inbox_ids.any?
    Contact.where(id: contact_ids).delete_all if contact_ids.any?
  end

  user_ids = User.where('email LIKE ?', "#{tag}%").pluck(:id)
  return if user_ids.empty?

  list = user_ids.join(',')
  # join tables sem FK declarada
  TeamMember.where(user_id: user_ids).delete_all
  InboxMember.where(user_id: user_ids).delete_all
  ConversationParticipant.where(user_id: user_ids).delete_all
  NotificationSetting.where(user_id: user_ids).delete_all
  AccountUser.where(user_id: user_ids).delete_all

  # FK NOT NULL -> apagar a linha. FK NULLABLE -> NULIFICAR, jamais apagar:
  # conversations.assignee_id é nullable, um DELETE genérico levaria conversa REAL do staging junto.
  user_fk_columns.each do |table, column, nullable|
    conn.execute(
      nullable ? "UPDATE #{table} SET #{column} = NULL WHERE #{column} IN (#{list})" : "DELETE FROM #{table} WHERE #{column} IN (#{list})"
    )
  end
  User.where(id: user_ids).delete_all
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

puts '== limpando resíduo de execução anterior =='
cleanup!(account, TAG)

# --- agentes dedicados, com EXATAMENTE 1 time cada (determinístico: sync_team_from_assignee
# zera o time quando o agente tem 2+ times que não batem) ---
def make_agent(account, tag, suffix, team, inbox)
  user = User.create!(name: "Sino #{suffix} (teste)", email: "#{tag}_#{suffix.downcase}@example.com",
                      password: 'Test@12345678', confirmed_at: Time.current)
  AccountUser.create!(account: account, user: user, role: :agent)
  TeamMember.create!(team: team, user: user) if team
  InboxMember.create!(inbox: inbox, user: user)
  user
end

agent_vendas  = make_agent(account, TAG, 'Vendas', team_vendas, inbox)
agent_suporte = make_agent(account, TAG, 'Suporte', team_suporte, inbox)
agent_sem_time = make_agent(account, TAG, 'SemTime', nil, inbox)
admin = User.find(1)

contact = Contact.create!(account: account, name: 'Cliente Sino E2E', phone_number: "+5599#{rand(10**8)}")
contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conversation = Conversation.create!(account: account, inbox: inbox, contact: contact,
                                    contact_inbox: contact_inbox, additional_attributes: { 'seed' => TAG })

puts
puts '== cenário: atribui ao agente de VENDAS =='
conversation.update!(assignee: agent_vendas)
conversation.reload
puts "   assignee=#{conversation.assignee.name} | team=#{conversation.team&.name}"
# é o que o ParticipationListener faz a cada assignee_changed (e nunca desfaz)
ConversationParticipant.find_or_create_by!(conversation: conversation, user: agent_vendas)

puts '== reatribui ao agente de SUPORTE (o AssignmentHandler move o time junto) =='
conversation.update!(assignee: agent_suporte)
conversation.reload
ConversationParticipant.find_or_create_by!(conversation: conversation, user: agent_suporte)
ConversationParticipant.find_or_create_by!(conversation: conversation, user: agent_sem_time)
ConversationParticipant.find_or_create_by!(conversation: conversation, user: admin)
puts "   assignee=#{conversation.assignee.name} | team=#{conversation.team&.name}"
puts "   participantes: #{conversation.conversation_participants.map { |p| p.user.name }.inspect}"
puts "   >> #{agent_vendas.name} continua participante de uma conversa que agora é do #{conversation.team&.name}"

puts
puts '== notificações tipo-5 legadas (como o código PRÉ-fix criava) =='
# A do admin é a que importa: ele PASSA em visible_to? (enxerga tudo), então a limpeza antiga,
# baseada só em visibilidade, achava 0 vazadas justamente no usuário que reclamou.
legacy = Notification.create!(account: account, user: agent_vendas, notification_type: 'participating_conversation_new_message',
                              primary_actor: conversation)
legacy_admin = Notification.create!(account: account, user: admin, notification_type: 'participating_conversation_new_message',
                                    primary_actor: conversation)
puts "   criadas notif ##{legacy.id} (#{agent_vendas.name}) e ##{legacy_admin.id} (#{admin.name})"

puts
puts '== mensagem nova do cliente -> caminho REAL de notificação =='
message = Message.create!(account: account, inbox: inbox, conversation: conversation,
                          message_type: :incoming, content: 'Oi, tudo bem?', sender: contact)
Messages::NewMessageNotificationService.new(message: message).perform

def notif_for?(user, message)
  Notification.exists?(user_id: user.id, secondary_actor_type: 'Message', secondary_actor_id: message.id)
end

# D2: conversa SEM assignee, com participantes -> ninguém pode ser notificado.
puts '== conversa SEM assignee -> mensagem nova =='
contact_orfa = Contact.create!(account: account, name: 'Cliente Sino E2E orfa', phone_number: "+5599#{rand(10**8)}")
contact_inbox_orfa = ContactInbox.create!(contact: contact_orfa, inbox: inbox, source_id: SecureRandom.uuid)
conversation_orfa = Conversation.create!(account: account, inbox: inbox, contact: contact_orfa,
                                         contact_inbox: contact_inbox_orfa, additional_attributes: { 'seed' => TAG })
conversation_orfa.update!(assignee: nil)
ConversationParticipant.find_or_create_by!(conversation: conversation_orfa, user: agent_suporte)
ConversationParticipant.find_or_create_by!(conversation: conversation_orfa, user: admin)
message_orfa = Message.create!(account: account, inbox: inbox, conversation: conversation_orfa,
                               message_type: :incoming, content: 'Alguem me ajuda?', sender: contact_orfa)
Messages::NewMessageNotificationService.new(message: message_orfa).perform
ninguem_notificado = Notification.where(secondary_actor_type: 'Message', secondary_actor_id: message_orfa.id).none?
puts "   assignee=#{conversation_orfa.reload.assignee.inspect} | notificados=#{Notification.where(
  secondary_actor_type: 'Message', secondary_actor_id: message_orfa.id
).count}"

# D3: a @menção é outro caminho (MentionService, tipo 4) e NÃO pode ter morrido junto.
puts '== @menção ao ex-assignee de outro time =='
mention_message = Message.create!(account: account, inbox: inbox, conversation: conversation,
                                  message_type: :outgoing, private: true, sender: admin,
                                  content: "cc [@Sino Vendas](mention://user/#{agent_vendas.id}/Sino%20Vendas) da uma olhada")
Messages::MentionService.new(message: mention_message).perform
mencionado_notificado = Notification.exists?(user_id: agent_vendas.id, notification_type: 'conversation_mention',
                                             secondary_actor_type: 'Message', secondary_actor_id: mention_message.id)
puts "   #{agent_vendas.name} (time #{team_vendas.name}, conversa do #{conversation.reload.team&.name}) " \
     "recebeu menção=#{mencionado_notificado}"

results = {
  '1. ex-assignee de OUTRO time NAO recebe' => [notif_for?(agent_vendas, message), false],
  '2. assignee atual recebe' => [notif_for?(agent_suporte, message), true],
  '3. participante SEM time NAO recebe (D1)' => [notif_for?(agent_sem_time, message), false],
  '4. admin participante NAO recebe (D1/D4)' => [notif_for?(admin, message), false],
  '5. conversa SEM assignee nao notifica ninguem (D2)' => [ninguem_notificado, true],
  '6. @mencao AINDA notifica cross-team (D3)' => [mencionado_notificado, true]
}

puts
puts '== RESULTADO =='
ok = true
results.each do |label, (actual, expected)|
  pass = actual == expected
  ok &&= pass
  puts "   #{pass ? 'PASS' : 'FALHOU'} | #{label} -> recebeu=#{actual} (esperado #{expected})"
end

puts
puts '== F2: a limpeza acha as tipo-5 legadas? =='
# O tipo 5 está APOSENTADO: o critério agora é o TIPO, não a visibilidade. É o que faz a limpeza
# pegar também a do admin — que passa em visible_to? e por isso escapava da regra antiga.
svc = Conversations::VisibilityService.new(conversation: conversation.reload)
retired = %w[participating_conversation_new_message]
pega_agente = retired.include?(legacy.notification_type)
pega_admin = retired.include?(legacy_admin.notification_type)
puts "   notif ##{legacy.id} (#{agent_vendas.name}): visible_to?=#{svc.visible_to?(agent_vendas)} -> " \
     "sera apagada=#{pega_agente} (tipo aposentado)"
puts "   notif ##{legacy_admin.id} (#{admin.name}): visible_to?=#{svc.visible_to?(admin)} -> " \
     "sera apagada=#{pega_admin} (tipo aposentado; a regra antiga NAO pegava esta)"
ok &&= pega_agente && pega_admin

puts
puts(ok ? '>>> E2E ALL GREEN' : '>>> E2E COM FALHA')
puts

if KEEP
  puts "cenário mantido de pé para QA visual (conversa ##{conversation.display_id}, inbox '#{inbox.name}')."
  puts "logins: #{agent_vendas.email} / #{agent_suporte.email} — senha Test@12345678"
  puts 'para remover depois: rails runner sino_e2e.rb  (ele limpa no início)'
else
  cleanup!(account, TAG)
  puts 'cenário removido (nada ficou na conta 1).'
end
