# Remove o cenário criado por task/fluxo_atendimento_seed.rb.
# NÃO toca na conv 226 nem no contato "Cliente Isolamento" (são anteriores ao seed).
#
# Rodar:      RAILS_ENV=production bundle exec rails runner task/fluxo_atendimento_cleanup.rb
# Só contar:  DRY=1 RAILS_ENV=production bundle exec rails runner task/fluxo_atendimento_cleanup.rb
SEED = 'fluxo_atendimento_demo'.freeze
DRY = ENV['DRY'].present?

contatos = Account.find(1).contacts.where("additional_attributes->>'seed' = ?", SEED)
conversas = Conversation.where(account_id: 1, contact_id: contatos.select(:id))

puts "contatos do seed: #{contatos.count} | conversas: #{conversas.count}"
contatos.each { |c| puts "  - #{c.name} (#{c.phone_number})" }

if DRY
  puts '(DRY=1 — nada foi apagado)'
else
  # pedidos primeiro: a FK de conversation é cascade, mas ser explícito evita
  # surpresa se um pedido apontar p/ conversa fora do seed.
  ConversationTakeoverRequest.where(conversation_id: conversas.select(:id)).delete_all
  conversas.destroy_all
  contatos.destroy_all
  puts 'removidos.'
end
