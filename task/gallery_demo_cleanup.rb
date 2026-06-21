# frozen_string_literal: true

# Limpeza do seed de teste da GALERIA.
# Apaga conversas e contatos marcados com additional_attributes['seed']='gallery_demo'
# (anexos Active Storage saem em cascata via destroy).
account = Account.order(:id).first
TAG = 'gallery_demo'
SEED_SQL = "additional_attributes->>'seed' = ?"

convs = account.conversations.where(SEED_SQL, TAG)
puts "Conversas gallery_demo a apagar: #{convs.count}"

if ENV['DRY'] == '1'
  puts '(DRY run — nada apagado)'
  exit 0
end

convs.find_each(&:destroy)
account.contacts.where(SEED_SQL, TAG).find_each(&:destroy)

puts '== Depois =='
puts "Conversas gallery_demo: #{account.conversations.where(SEED_SQL, TAG).count}"
puts "Contatos  gallery_demo: #{account.contacts.where(SEED_SQL, TAG).count}"
