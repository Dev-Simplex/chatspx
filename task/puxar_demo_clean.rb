# Remove o cenário de teste criado por task/puxar_demo_seed.rb.
# Rodar: RAILS_ENV=production bundle exec rails runner task/puxar_demo_clean.rb

SEED_TAG = 'puxar_demo'.freeze
acc = Account.find(1)

convs = acc.conversations.where("additional_attributes ->> 'seed' = ?", SEED_TAG)
conv_ids = convs.pluck(:id)

# 1) pedidos de takeover das conversas do seed (FK → conversation)
req_n = ConversationTakeoverRequest.where(conversation_id: conv_ids).delete_all

# 2) conversas (destroy cuida de mensagens/contact_inboxes dependentes)
conv_n = 0
convs.find_each do |c|
  c.destroy!
  conv_n += 1
end

# 3) contatos do seed (destroy cuida de contact_inboxes remanescentes)
contacts = acc.contacts.where("additional_attributes ->> 'seed' = ?", SEED_TAG)
ct_n = 0
contacts.find_each do |c|
  c.destroy!
  ct_n += 1
end

puts "Removido: #{req_n} pedidos, #{conv_n} conversas, #{ct_n} contatos (seed=#{SEED_TAG})."
