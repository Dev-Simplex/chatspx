# frozen_string_literal: true

# Seed para testar o ISOLAMENTO DE MENSAGENS POR AGENTE (flag agent_message_isolation).
# Cria 4 agentes dedicados + 1 inbox com a flag LIGADA + 1 conversa com mensagens
# outgoing carimbadas a cada agente (agent_id) e mensagens publicas (agent_id NULL).
# Ao final, simula Current.user de cada agente/admin via MessageFinder e mostra o que
# cada um enxerga vs. o que fica mascarado (🔒).
#
# Idempotente: contatos/conversa marcados com seed='agent_iso_demo'; inbox/users por nome/email.
# Uso:  RAILS_ENV=production bundle exec rails runner task/agent_iso_demo_seed.rb
account = Account.order(:id).first
TAG = 'agent_iso_demo'
SEED_SQL = "additional_attributes->>'seed' = ?"
PASSWORD = 'Teste@123456'

puts "== Seed isolamento-agente na conta ##{account.id} #{account.name} =="

# ---------- 4 agentes de teste ----------
AGENTS = [
  { name: 'Agente Teste A', email: 'iso.agente.a@simplexteste.local' },
  { name: 'Agente Teste B', email: 'iso.agente.b@simplexteste.local' },
  { name: 'Agente Teste C', email: 'iso.agente.c@simplexteste.local' },
  { name: 'Agente Teste D', email: 'iso.agente.d@simplexteste.local' }
]
agents = AGENTS.map do |a|
  user = User.find_by(email: a[:email]) || User.create!(
    name: a[:name], email: a[:email], password: PASSWORD, confirmed_at: Time.current
  )
  account.account_users.find_or_create_by!(user: user) { |au| au.role = :agent }
  user
end
puts "Agentes (senha p/ login UI = #{PASSWORD}):"
agents.each { |u| puts "  ##{u.id} #{u.name} <#{u.email}>" }

# ---------- inbox com a flag LIGADA ----------
inbox = account.inboxes.find_by(name: 'Isolamento Agente (teste)')
unless inbox
  channel = Channel::Api.create!(account: account)
  inbox = account.inboxes.create!(name: 'Isolamento Agente (teste)', channel: channel)
end
inbox.update!(agent_message_isolation: true)
# da acesso dos 4 agentes ao inbox
agents.each { |u| InboxMember.find_or_create_by!(inbox: inbox, user: u) }
puts "Inbox: ##{inbox.id} #{inbox.name} | agent_message_isolation=#{inbox.agent_message_isolation}"

# ---------- conversa de teste (re-semeia limpa) ----------
account.conversations.where(SEED_SQL, TAG).find_each(&:destroy)
account.contacts.where(SEED_SQL, TAG).find_each(&:destroy)

contact = account.contacts.create!(name: 'Cliente Isolamento (teste)',
                                   phone_number: '+559279000099',
                                   additional_attributes: { 'seed' => TAG })
ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conv = account.conversations.create!(inbox: inbox, contact: contact, contact_inbox: ci,
                                     status: :open, additional_attributes: { 'seed' => TAG })

# ---------- mensagens ----------
# publica (incoming do cliente) -> agent_id NULL -> todos veem
conv.messages.create!(account: account, inbox: inbox, message_type: :incoming,
                      content: '[PUBLICA] Olá, preciso de ajuda com meu pedido.', sender: contact)
# 1 outgoing por agente -> agent_id carimbado = sender_id
agents.each_with_index do |u, i|
  conv.messages.create!(account: account, inbox: inbox, message_type: :outgoing,
                        content: "[DE #{u.name}] resposta privada do agente #{('A'.ord + i).chr}.",
                        sender: u)
end
# outra publica (incoming) no fim
conv.messages.create!(account: account, inbox: inbox, message_type: :incoming,
                      content: '[PUBLICA] Obrigado pelo retorno!', sender: contact)
conv.reload
puts "Conversa: ##{conv.display_id} (id #{conv.id}) com #{conv.messages.count} mensagens"

# ---------- VERIFICACAO: o que cada espectador enxerga ----------
puts "\n== Verificação via MessageFinder (flag ON) =="
viewers = [['ADMIN #1', account.administrators.first]] + agents.map { |u| [u.name, u] }
viewers.each do |label, user|
  Current.user = user
  msgs = MessageFinder.new(conv, {}).perform
  visiveis = msgs.map { |m| m.content.to_s[0, 30] }
  total = conv.messages.count
  ocultas = total - msgs.size
  puts "  #{label.ljust(16)} vê #{msgs.size}/#{total} (#{ocultas} 🔒): #{visiveis.join(' | ')}"
ensure
  Current.user = nil
end

puts "\n== Esperado =="
puts '  ADMIN vê 6/6 (0 🔒). Cada agente vê 3/6 (3 🔒): as 2 públicas + só a SUA outgoing.'
puts 'Limpar:  RAILS_ENV=production bundle exec rails runner task/agent_iso_demo_cleanup.rb'
