# Limpeza das notificações de sino que hoje violam a regra de visibilidade da LISTA.
#
# O fix (Conversations::VisibilityService + guards de audiência) faz a notificação NASCER correta,
# mas não apaga o que já está no sino. Sem esta limpeza o dono abre o sino no dia seguinte e o bug
# "continua".
#
# USO (dry-run é o default — NUNCA apaga sem --apply):
#   RAILS_ENV=production bundle exec rails runner task/notificacoes_vazadas_cleanup.rb -- --account=1
#   RAILS_ENV=production bundle exec rails runner task/notificacoes_vazadas_cleanup.rb -- --account=1 --apply
#
# ⚠️ ESCOPO DE TIPOS — ler antes de mexer.
# Aplicar visible_to? em TODA notificação de conversa apagaria coisa legítima. Só entram aqui os
# tipos cuja audiência os guards deste fix passaram a governar:
#
#   conversation_creation (1)                  -> notify_inbox_members
#   participating_conversation_new_message (5) -> notify_participating_users  (84% do volume)
#   sla_missed_* (6,7,8)                       -> ramo de participantes do SlaEvent
#
# FICAM DE FORA, de propósito:
#   conversation_mention (4)      -> menção cross-team é DELIBERADA (consentimento explícito).
#                                    O mencionado reprova em visible_to? por definição.
#   conversation_unassignment(10) -> existe justamente para avisar quem PERDEU a conversa; o
#                                    destinatário reprova em visible_to? por definição.
#   conversation_assignment (2) /
#   assigned_conversation_new_message (3) -> histórico de quando a pessoa ERA o assignee. Revogar
#                                    notificação que nasceu válida e depois ficou obsoleta é outro
#                                    assunto (handler team_changed), deliberadamente adiado.
#   conversation_orphaned (9)     -> alerta de admin, by design.

require 'optparse'

options = { apply: false }
OptionParser.new do |opts|
  opts.on('--account=ACCOUNT_ID', Integer, 'Account id (obrigatório)') { |v| options[:account] = v }
  opts.on('--apply', 'Apaga de verdade. Sem esta flag, só imprime o relatório.') { options[:apply] = true }
end.parse!(ARGV)

abort('ERRO: informe --account=ID') if options[:account].blank?

GOVERNED_TYPES = %w[
  conversation_creation
  participating_conversation_new_message
  sla_missed_first_response
  sla_missed_next_response
  sla_missed_resolution
].freeze

account = Account.find(options[:account])
scope = Notification.where(account_id: account.id, primary_actor_type: 'Conversation', notification_type: GOVERNED_TYPES)

puts "Conta ##{account.id} (#{account.name})"
puts "Modo: #{options[:apply] ? '*** APPLY (destrutivo) ***' : 'dry-run (nada será apagado)'}"
puts "Tipos governados: #{GOVERNED_TYPES.join(', ')}"
puts "Candidatas a avaliar: #{scope.count}"
puts

visibility_cache = {}
leaked = []

scope.includes(:user, :primary_actor).find_each do |notification|
  conversation = notification.primary_actor
  user = notification.user
  next if conversation.blank? || user.blank?

  service = (visibility_cache[conversation.id] ||= Conversations::VisibilityService.new(conversation: conversation))
  leaked << notification unless service.visible_to?(user)
end

puts "VAZADAS (violam a regra da lista hoje): #{leaked.size}"
puts

if leaked.any?
  puts 'Por tipo:'
  leaked.group_by(&:notification_type).sort_by { |_, v| -v.size }.each { |type, list| puts "  #{type}: #{list.size}" }
  puts
  puts 'Por usuário:'
  leaked.group_by(&:user_id).sort_by { |_, v| -v.size }.each do |user_id, list|
    puts "  user ##{user_id} (#{list.first.user.name}): #{list.size}"
  end
  puts
  puts 'Exemplos (até 10):'
  leaked.first(10).each do |n|
    conversation = n.primary_actor
    puts "  notif ##{n.id} | #{n.notification_type} | user ##{n.user_id} | conv ##{conversation.display_id} " \
         "| conv.team=#{conversation.team_id.inspect} | user.teams=#{n.user.teams.where(account_id: account.id).pluck(:id).inspect}"
  end
  puts
end

if options[:apply]
  if leaked.empty?
    puts 'Nada a apagar.'
  else
    puts "Apagando #{leaked.size} notificações em lotes..."
    # destroy (não delete_all): dispara dispatch_destroy_event, e o unread_count do sino se corrige
    # sozinho via ActionCableListener.
    leaked.each_slice(200) do |batch|
      batch.each(&:destroy)
      print '.'
    end
    puts
    puts 'Pronto.'
  end
else
  puts 'DRY-RUN: nada foi apagado. Revise os números acima com o dono antes de rodar com --apply.'
end
