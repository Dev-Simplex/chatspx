# FASE 0 — diagnóstico do sino. SOMENTE LEITURA: não escreve, não apaga, não altera nada.
#
# Roda em QUALQUER servidor (inclusive produção, que ainda NÃO tem o código novo):
# é autocontido de propósito, não usa Conversations::VisibilityService.
#
# Uso:
#   RAILS_ENV=production RAILS_LOG_LEVEL=error bundle exec rails runner task/sino_fase0_diagnostico.rb -- --email=SEU@EMAIL --account=1
$stdout.sync = true

require 'optparse'
options = {}
OptionParser.new do |opts|
  opts.on('--email=EMAIL', String) { |v| options[:email] = v }
  opts.on('--account=ID', Integer) { |v| options[:account] = v }
end.parse!(ARGV)
abort('ERRO: use --email=SEU@EMAIL --account=ID') if options[:email].blank? || options[:account].blank?

user = User.from_email(options[:email]) or abort("ERRO: usuário #{options[:email]} não existe")
account = Account.find(options[:account])
account_user = AccountUser.find_by(account_id: account.id, user_id: user.id)
my_team_ids = user.teams.where(account_id: account.id).pluck(:id)

puts "Usuário: #{user.name} <#{user.email}> (##{user.id})"
puts "Conta:   ##{account.id} #{account.name}"
puts "Papel:   #{account_user&.role}   <<< se for 'administrator', admin vê tudo por design (P9)"
puts "Times:   #{user.teams.where(account_id: account.id).pluck(:name).inspect}"
puts "Inboxes: #{user.inboxes.where(account_id: account.id).count}"
puts

scope = Notification.where(user_id: user.id, account_id: account.id)
puts "=== O QUE ESTÁ NO SINO (#{scope.count} no total, #{scope.where(read_at: nil).count} não lidas) ==="
scope.group(:notification_type).count.sort_by { |_, v| -v }.each do |type, count|
  nao_lidas = scope.where(notification_type: type, read_at: nil).count
  puts "  #{type.to_s.ljust(40)} #{count.to_s.rjust(4)}  (#{nao_lidas} não lidas)"
end
puts

# Das notificações de conversa: quantas são de conversa cujo time NÃO é meu?
puts '=== RECORTE POR TIME (a queixa: "conversa de outro time") ==='
conversation_ids = scope.where(primary_actor_type: 'Conversation').pluck(:primary_actor_id).uniq
conversations = Conversation.where(id: conversation_ids)
sem_time = conversations.where(team_id: nil).count
meu_time = my_team_ids.any? ? conversations.where(team_id: my_team_ids).count : 0
outro_time = conversations.where.not(team_id: nil).where.not(team_id: my_team_ids.presence || [-1]).count
puts "  conversas que geram sino: #{conversations.count}"
puts "  ... sem time:             #{sem_time}"
puts "  ... do MEU time:          #{meu_time}"
puts "  ... de OUTRO time:        #{outro_time}   <<< é isso que te incomoda"
puts

puts '=== POR QUE EU RECEBO? (amostra de até 15 de OUTRO time) ==='
puts '   participante = fui assignee um dia (ou fui @mencionado) e a participação NUNCA sai.'
amostra = conversations.where.not(team_id: nil).where.not(team_id: my_team_ids.presence || [-1]).limit(15)
amostra.each do |conversation|
  participante = ConversationParticipant.exists?(conversation_id: conversation.id, user_id: user.id)
  tipos = scope.where(primary_actor_type: 'Conversation', primary_actor_id: conversation.id)
               .distinct.pluck(:notification_type).join(',')
  puts "  conv ##{conversation.display_id.to_s.ljust(6)} time=#{conversation.team&.name.to_s.ljust(14)} " \
       "assignee=#{conversation.assignee&.name.to_s[0, 16].to_s.ljust(16)} " \
       "sou_participante=#{participante.to_s.ljust(5)} tipos=#{tipos}"
end
puts

puts '=== VEREDITO ==='
tipo5 = scope.where(notification_type: 'participating_conversation_new_message').count
tipo1 = scope.where(notification_type: 'conversation_creation').count
tipo9 = scope.where(notification_type: 'conversation_orphaned').count
participante_de = ConversationParticipant.where(user_id: user.id, account_id: account.id).count
puts "  participating_conversation_new_message (tipo 5): #{tipo5}"
puts "  conversation_creation (tipo 1):                  #{tipo1}"
puts "  conversation_orphaned (tipo 9):                   #{tipo9}"
puts "  sou participante de #{participante_de} conversas   <<< a fonte do ruído: participação é eterna"
puts
if account_user&.role == 'administrator'
  puts '  >>> VOCÊ É ADMIN. O fix atual do sino ISENTA admin (admin vê tudo, P9), então ele'
  puts '      NÃO muda o seu sino. Se o tipo 5 domina acima, o seu problema é RUÍDO de'
  puts '      participação eterna, não vazamento de visibilidade -> é decisão de produto.'
else
  puts '  >>> Você é agente: se o tipo 5 domina, o fix (Fase 2) resolve o seu caso.'
end
