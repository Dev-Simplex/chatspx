# frozen_string_literal: true

# Limpeza do seed de teste do gate de encerramento.
# Apaga conversas e contatos marcados com additional_attributes['seed']='gate_demo'.
#   RAILS_ENV=production bundle exec rails runner task/gate_demo_cleanup.rb
#   DRY=1 ... (apenas lista, não apaga)
account = Account.order(:id).first
TAG = 'gate_demo'
SEED_SQL = "additional_attributes->>'seed' = ?"

convs = account.conversations.where(SEED_SQL, TAG)
puts "Conversas gate_demo a apagar: #{convs.count}"

if ENV['DRY'] == '1'
  puts '(DRY run — nada apagado)'
  exit 0
end

convs.find_each(&:destroy)
account.contacts.where(SEED_SQL, TAG).find_each(&:destroy)

puts '== Depois =='
puts "Conversas gate_demo: #{account.conversations.where(SEED_SQL, TAG).count}"
puts "Contatos  gate_demo: #{account.contacts.where(SEED_SQL, TAG).count}"
