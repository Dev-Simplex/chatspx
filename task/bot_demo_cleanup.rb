# frozen_string_literal: true
# rubocop:disable all

# Remove tudo que o task/bot_demo_seed.rb criou, e so isso: conversas marcadas com
# additional_attributes['seed']='bot_demo', seus contatos, mensagens e eventos.
# Tambem desativa o bot de demonstracao na caixa WhatsApp Suporte (a de Vendas ja
# tinha bot antes deste seed — essa fica como estava).
# Uso: RAILS_ENV=production bundle exec rails runner task/bot_demo_cleanup.rb

SEED_TAG = 'bot_demo'
account = Account.find(1)

conversas = account.conversations.where("additional_attributes->>'seed' = ?", SEED_TAG)
ids = conversas.pluck(:id)
puts "== Limpeza do seed '#{SEED_TAG}' na conta ##{account.id}: #{ids.size} conversas =="

if ids.empty?
  puts 'Nada marcado. Nada a fazer.'
else
  eventos = ReportingEvent.where(conversation_id: ids).delete_all
  mensagens = Message.where(conversation_id: ids).delete_all
  puts "  eventos removidos: #{eventos} | mensagens removidas: #{mensagens}"

  contatos = conversas.pluck(:contact_id).uniq
  conversas.find_each(&:destroy!)
  puts "  conversas removidas: #{ids.size}"

  # so apaga contato que nao sobrou em nenhuma outra conversa
  sobraram = Contact.where(id: contatos).where.not(id: Conversation.where(contact_id: contatos).select(:contact_id))
  n = sobraram.count
  sobraram.find_each(&:destroy!)
  puts "  contatos removidos: #{n}"
end

suporte = account.inboxes.find_by(name: 'WhatsApp Suporte')
if suporte
  removidos = AgentBotInbox.where(inbox_id: suporte.id).destroy_all.size
  puts "  bot desativado em #{suporte.name}: #{removidos} vinculo(s)"
end

puts '== Limpeza concluida =='
