# Limpeza das notificações de sino que hoje violam a regra da LISTA de conversas.
#
# Os fixes fazem a notificação NASCER correta, mas não apagam o que já está no sino. Sem esta
# limpeza o dono abre o sino no dia seguinte e o bug "continua".
#
# USO (dry-run é o default — NUNCA apaga sem --apply):
#   RAILS_ENV=production bundle exec rails runner task/notificacoes_vazadas_cleanup.rb -- --account=1
#   RAILS_ENV=production bundle exec rails runner task/notificacoes_vazadas_cleanup.rb -- --account=1 --apply
#
# ⚠️ ESCOPO DE TIPOS — ler antes de mexer. São DUAS regras diferentes.
#
# (A) APOSENTADO — apaga TODAS, sem avaliar visibilidade:
#
#   participating_conversation_new_message (5) -> notify_participating_users (84% do volume)
#     O caminho que criava este tipo foi REMOVIDO: agora só o assignee é notificado sobre mensagem
#     nova. Nenhuma tipo-5 remanescente é legítima — inclusive as do admin, que passavam em
#     visible_to? (ele enxerga tudo) e por isso a limpeza antiga achava 0 vazadas justamente no
#     usuário que reclamou. O tipo continua no enum (bits FlagShihTzu), só não nasce mais.
#
# (B) GOVERNADOS PELO TIME — apaga só as que reprovam em visible_to?:
#
#   conversation_creation (1)  -> notify_inbox_members
#   sla_missed_* (6,7,8)       -> ramo de participantes do SlaEvent (único que ainda itera a
#                                 participação eterna; o guard de visibilidade dele fica)
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

# (A) tipo aposentado: toda notificação remanescente é lixo, independente de quem seja o dono.
RETIRED_TYPES = %w[
  participating_conversation_new_message
].freeze

# (B) tipos cuja audiência segue governada pelo time: só apaga quem reprova em visible_to?.
GOVERNED_TYPES = %w[
  conversation_creation
  sla_missed_first_response
  sla_missed_next_response
  sla_missed_resolution
].freeze

account = Account.find(options[:account])
base = Notification.where(account_id: account.id, primary_actor_type: 'Conversation')
retired_scope = base.where(notification_type: RETIRED_TYPES)
governed_scope = base.where(notification_type: GOVERNED_TYPES)

puts "Conta ##{account.id} (#{account.name})"
puts "Modo: #{options[:apply] ? '*** APPLY (destrutivo) ***' : 'dry-run (nada será apagado)'}"
puts
puts "(A) Tipos APOSENTADOS (apaga todas): #{RETIRED_TYPES.join(', ')}"
puts "    Encontradas: #{retired_scope.count}"
puts "(B) Tipos governados pelo time (apaga só as invisíveis): #{GOVERNED_TYPES.join(', ')}"
puts "    Candidatas a avaliar: #{governed_scope.count}"
puts

visibility_cache = {}
doomed = retired_scope.to_a

governed_scope.includes(:user, :primary_actor).find_each do |notification|
  conversation = notification.primary_actor
  user = notification.user
  next if conversation.blank? || user.blank?

  service = (visibility_cache[conversation.id] ||= Conversations::VisibilityService.new(conversation: conversation))
  doomed << notification unless service.visible_to?(user)
end

puts "A APAGAR: #{doomed.size}"
puts

if doomed.any?
  puts 'Por tipo:'
  doomed.group_by(&:notification_type).sort_by { |_, v| -v.size }.each do |type, list|
    motivo = RETIRED_TYPES.include?(type) ? 'tipo aposentado' : 'reprova em visible_to?'
    puts "  #{type}: #{list.size}  (#{motivo})"
  end
  puts
  puts 'Por usuário:'
  doomed.group_by(&:user_id).sort_by { |_, v| -v.size }.each do |user_id, list|
    puts "  user ##{user_id} (#{list.first.user&.name}): #{list.size}"
  end
  puts
  puts 'Exemplos (até 10):'
  doomed.first(10).each do |n|
    conversation = n.primary_actor
    puts "  notif ##{n.id} | #{n.notification_type} | user ##{n.user_id} | conv ##{conversation&.display_id} " \
         "| conv.team=#{conversation&.team_id.inspect} | user.teams=#{n.user&.teams&.where(account_id: account.id)&.pluck(:id).inspect}"
  end
  puts
end

if options[:apply]
  if doomed.empty?
    puts 'Nada a apagar.'
  else
    puts "Apagando #{doomed.size} notificações em lotes..."
    # destroy (não delete_all): dispara dispatch_destroy_event, e o unread_count do sino se corrige
    # sozinho via ActionCableListener.
    doomed.each_slice(200) do |batch|
      batch.each(&:destroy)
      print '.'
    end
    puts
    puts 'Pronto.'
  end
else
  puts 'DRY-RUN: nada foi apagado. Revise os números acima com o dono antes de rodar com --apply.'
end
