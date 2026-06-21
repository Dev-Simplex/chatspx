# frozen_string_literal: true

# Remove os dados de teste do card de contato compartilhado (seed='shared_contact_demo').
# DRY=1 apenas conta, sem apagar.
account = Account.order(:id).first
TAG = 'shared_contact_demo'
SEED_SQL = "additional_attributes->>'seed' = ?"
dry = ENV['DRY'] == '1'

convs = account.conversations.where(SEED_SQL, TAG)
contacts = account.contacts.where(SEED_SQL, TAG)
msg_scope = Message.where(conversation_id: convs.select(:id))
msg_count = msg_scope.count
att_count = Attachment.where(message_id: msg_scope.select(:id)).count

puts "Conversas: #{convs.count} | mensagens: #{msg_count} | anexos: #{att_count} | contatos: #{contacts.count}"

if dry
  puts 'DRY=1 -> nada apagado.'
  exit 0
end

convs.destroy_all
contacts.destroy_all
puts 'Removido.'
