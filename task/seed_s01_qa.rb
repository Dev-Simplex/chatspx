# Cenário de QA da S-01 — staging nicolas (conta 1).
# Cria uma caixa API SEM webhook (nada sai de verdade) com "uma conversa por
# contato" ligada, que é a regra que faz o ConversationBuilder reusar conversa.
#   RAILS_ENV=production bundle exec rails runner task/seed_s01_qa.rb
account = Account.find(1)
inbox = account.inboxes.find_by(name: 'QA S-01 (reuso)')
unless inbox
  channel = Channel::Api.create!(account: account, identifier: "qa-s01-#{SecureRandom.hex(4)}", webhook_url: nil)
  inbox = Inbox.create!(account: account, channel: channel, name: 'QA S-01 (reuso)', lock_to_single_conversation: true)
end
# 10 = Agente Teste A, 11 = Agente Teste B, 12 = Agente Teste C (todos no time 3/suporte)
[10, 11, 12].each { |uid| InboxMember.find_or_create_by!(inbox: inbox, user_id: uid) }

cenarios = [
  ['S01 Outro Time', '+5566900000101', { team_id: 2, assignee_id: nil, status: :open }],
  ['S01 Resolvida',  '+5566900000102', { team_id: 2, assignee_id: nil, status: :resolved }],
  ['S01 Orfa',       '+5566900000103', { team_id: nil, assignee_id: nil, status: :open }]
]

cenarios.each do |name, phone, attrs|
  contact = account.contacts.find_by(phone_number: phone) || account.contacts.create!(name: name, phone_number: phone)
  ci = ContactInbox.find_by(contact: contact, inbox: inbox) ||
       ContactInbox.create!(contact: contact, inbox: inbox, source_id: phone)
  conv = Conversation.where(inbox_id: inbox.id, contact_id: contact.id).first ||
         Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
  conv.update_columns(attrs.merge(updated_at: Time.current))
  conv.reload
  puts "#{name} | #{phone} | conversa ##{conv.display_id} | time=#{conv.team_id.inspect} | dono=#{conv.assignee_id.inspect} | #{conv.status}"
end

puts "caixa: #{inbox.name} (id #{inbox.id})"

# Reversão (apaga só o que este script criou):
#   inbox = Account.find(1).inboxes.find_by(name: 'QA S-01 (reuso)')
#   Contact.where(phone_number: %w[+5566900000101 +5566900000102 +5566900000103]).destroy_all
#   inbox&.destroy
