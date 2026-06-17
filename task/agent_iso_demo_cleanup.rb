# frozen_string_literal: true

# Limpeza do seed de teste do isolamento por agente (seed='agent_iso_demo').
# Remove a conversa/contato de teste, o inbox dedicado e os 4 agentes de teste.
# DRY=1 apenas conta, sem apagar.
account = Account.order(:id).first
TAG = 'agent_iso_demo'
SEED_SQL = "additional_attributes->>'seed' = ?"
dry = ENV['DRY'] == '1'

convs    = account.conversations.where(SEED_SQL, TAG)
contacts = account.contacts.where(SEED_SQL, TAG)
inbox    = account.inboxes.find_by(name: 'Isolamento Agente (teste)')
emails   = %w[iso.agente.a@simplexteste.local iso.agente.b@simplexteste.local
              iso.agente.c@simplexteste.local iso.agente.d@simplexteste.local]
users    = User.where(email: emails)

puts "Conversas: #{convs.count} | contatos: #{contacts.count} | inbox: #{inbox ? "##{inbox.id}" : '—'} | usuários: #{users.count}"

if dry
  puts 'DRY=1 -> nada apagado.'
  return
end

convs.find_each(&:destroy)
contacts.find_each(&:destroy)
inbox&.destroy
users.find_each(&:destroy)
puts 'Removido.'
