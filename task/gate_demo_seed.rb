# frozen_string_literal: true

# Seed para testar "Atribuição obrigatória" (resolve_assignment_gate).
# Cria conversas ABERTAS com estados de atribuição variados, p/ exercitar cada
# variante do modal "Atribuir a você e encerrar?".
# Idempotente: marca tudo com additional_attributes['seed']='gate_demo'.
#
# Uso:  RAILS_ENV=production bundle exec rails runner task/gate_demo_seed.rb
#       TESTER_EMAIL=outro@dominio bundle exec rails runner task/gate_demo_seed.rb
account = Account.order(:id).first
TAG = 'gate_demo'
SEED_SQL = "additional_attributes->>'seed' = ?"

tester_email = ENV.fetch('TESTER_EMAIL', 'dev@simplexsolucoes.com.br')
tester = account.users.find_by('email ILIKE ?', tester_email) || account.administrators.first
raise 'Tester não encontrado' unless tester

inbox = account.inboxes.find_by(name: 'WhatsApp Suporte') || account.inboxes.order(:id).first
team_v = account.teams.find_by(name: 'vendas') || account.teams.order(:id).first
team_s = account.teams.find_by(name: 'suporte') || team_v

agents = account.users.where("email LIKE 'demo.agent%@simplexdemo.local'").order(:id).to_a
colega1 = agents[0]
colega2 = agents[1] || agents[0]

# O assignee precisa pertencer ao time da conversa, senão o model limpa o assignee.
[[tester, team_v], [colega1, team_v], [colega2, team_s]].each do |u, t|
  TeamMember.find_or_create_by!(user: u, team: t) if u && t
end

already = account.conversations.where(SEED_SQL, TAG).count
if already.positive?
  puts "Já existem #{already} conversas gate_demo. Para re-semear, rode task/gate_demo_cleanup.rb antes."
  exit 0
end

idx = 0
make = lambda do |name, assignee, team, msgs|
  idx += 1
  contact = account.contacts.create!(name: name, phone_number: "+55927910000#{format('%02d', idx)}",
                                     additional_attributes: { 'seed' => TAG })
  ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  conv = account.conversations.create!(inbox: inbox, contact: contact, contact_inbox: ci,
                                       assignee: assignee, team: team, status: :open,
                                       additional_attributes: { 'seed' => TAG })
  # Garante "sem dono" mesmo se auto-assign do time tentar atribuir.
  conv.update_column(:assignee_id, nil) if assignee.nil? && conv.assignee_id.present?
  msgs.each do |body|
    conv.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: body, sender: contact)
  end
  conv.reload
  puts "  ##{conv.display_id}  #{name}  | dono=#{conv.assignee&.name || '—'} | time=#{conv.team&.name || '—'}"
  conv
end

puts "Tester (logue como este p/ testar): #{tester.name} <#{tester.email}>"
puts "Inbox: #{inbox.name}"
make.call('[GATE] Minha — encerra direto', tester, team_v, ['Oi! Pode encerrar quando resolver, por favor.'])
make.call('[GATE] De colega (Ana) — assumir', colega1, team_v, ['Bom dia, aguardo retorno sobre meu pedido.'])
make.call('[GATE] Sem dono (com time)', nil, team_v, ['Olá, ninguém me respondeu ainda.'])
make.call('[GATE] Sem dono e SEM time', nil, nil, ['Preciso de ajuda, alguém pode assumir?'])
make.call('[GATE] De colega (Emily) — assumir', colega2, team_s, ['Quero falar sobre a fatura deste mês.'])

puts '== Pronto =='
puts "Conversas gate_demo: #{account.conversations.where(SEED_SQL, TAG).count}"
