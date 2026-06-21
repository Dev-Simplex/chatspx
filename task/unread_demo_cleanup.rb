# frozen_string_literal: true

# Limpeza do seed de teste da view "Nao Lidas".
# Apaga conversas e contatos marcados com additional_attributes['seed']='unread_demo'.
account = Account.order(:id).first
TAG = 'unread_demo'
SEED_SQL = "additional_attributes->>'seed' = ?"

convs    = account.conversations.where(SEED_SQL, TAG)
contacts = account.contacts.where(SEED_SQL, TAG)

puts '== Antes =='
puts "Conversas unread_demo: #{convs.count}"
puts "Contatos  unread_demo: #{contacts.count}"

dry = ENV['DRY'] == '1'
if dry
  puts '(DRY run — nada apagado)'
  exit 0
end

convs.find_each { |c| c.destroy }
# contatos restantes com o marcador (alguns podem ter sido removidos em cascata)
account.contacts.where(SEED_SQL, TAG).find_each { |ct| ct.destroy }

puts '== Depois =='
puts "Conversas unread_demo: #{account.conversations.where(SEED_SQL, TAG).count}"
puts "Contatos  unread_demo: #{account.contacts.where(SEED_SQL, TAG).count}"
puts "Conversas reais restantes na conta: #{account.conversations.count}"
