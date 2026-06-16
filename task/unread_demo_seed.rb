# frozen_string_literal: true

# Seed de teste para a view "Nao Lidas". Conversas com mensagens incoming reais.
# Idempotente: marca conversas com additional_attributes['seed']='unread_demo'.
account = Account.order(:id).first
TAG = 'unread_demo'
SEED_SQL = "additional_attributes->>'seed' = ?"

already = account.conversations.where(SEED_SQL, TAG).count
if already >= 10
  puts "Ja semeado (#{already} conversas unread_demo). Nada a fazer. Para re-semear, limpe antes."
  exit 0
end

admin   = account.account_users.where(role: :administrator).first.user
agents  = User.where("email LIKE 'demo.agent%@simplexdemo.local'").order(:id).to_a
inboxes = account.inboxes.where(name: ['WhatsApp Vendas', 'WhatsApp Suporte', 'Site / Widget']).order(:id).to_a
inboxes = account.inboxes.order(:id).to_a if inboxes.empty?

now = Time.current
FIRST_NAMES = %w[Joao Maria Pedro Ana Lucas Carla Bruno Fernanda Rafael Juliana Marcos Patricia Diego Camila Thiago]
MSGS = [
  ['Oi, boa tarde! Gostaria de saber o status do meu pedido.', 'Ja faz 3 dias e nao recebi atualizacao.'],
  ['Ola, voces tem disponibilidade para essa semana?'],
  ['Bom dia! O produto chegou com defeito, como faco a troca?', 'Segue a foto em anexo.', 'Aguardo retorno, por favor.'],
  ['Quero cancelar minha assinatura.'],
  ['Pode me passar um orcamento?', 'Preciso para uns 50 itens.'],
  ['Nao consegui finalizar o pagamento no site.'],
  ['Obrigado pelo atendimento anterior! So uma duvida rapida...'],
  ['Voces atendem na regiao de Manaus?']
]

# spec: [quantidade, assignee_proc, lida?(true=controle negativo)]
def make_conv(account:, inbox:, contact_name:, phone:, assignee:, msgs:, base_time:, read:, tag:)
  contact = account.contacts.create!(name: contact_name, phone_number: phone,
                                     additional_attributes: { 'seed' => tag })
  ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  conv = account.conversations.create!(
    inbox: inbox, contact: contact, contact_inbox: ci, assignee: assignee,
    status: :open, additional_attributes: { 'seed' => tag },
    created_at: base_time, updated_at: base_time
  )
  msgs.each_with_index do |body, idx|
    conv.messages.create!(account: account, inbox: inbox,
                          message_type: :incoming, content: body, sender: contact,
                          created_at: base_time + (idx * 90))
  end
  last_at = base_time + (msgs.size * 90)
  if read
    # controle negativo: marcado como visto DEPOIS da ultima incoming -> NAO deve aparecer em "Nao Lidas"
    conv.update_columns(agent_last_seen_at: last_at + 60, updated_at: last_at)
  else
    # nao-lida: garante agent_last_seen_at NULL independinte de callbacks
    conv.update_columns(agent_last_seen_at: nil, updated_at: last_at)
  end
  conv
end

created = { unassigned: 0, other_agent: 0, mine: 0, read_control: 0 }
seq = 0
pick_inbox = ->(i) { inboxes[i % inboxes.size] }
pick_msgs  = ->(i) { MSGS[i % MSGS.size] }
pick_name  = ->(i) { "#{FIRST_NAMES[i % FIRST_NAMES.size]} (teste nao-lida)" }
phone_for  = ->(i) { "+5592#{format('%09d', 700_000_000 + i)}" }

# A) 5 nao atribuidas, nao-lidas (CASO CRITICO: admin sem time precisa ver)
5.times do
  make_conv(account: account, inbox: pick_inbox.call(seq), contact_name: pick_name.call(seq),
            phone: phone_for.call(seq), assignee: nil, msgs: pick_msgs.call(seq),
            base_time: now - (seq + 1).hours, read: false, tag: TAG)
  created[:unassigned] += 1
  seq += 1
end

# B) 5 atribuidas a OUTROS agentes, nao-lidas
5.times do |k|
  ag = agents[k % agents.size] || admin
  make_conv(account: account, inbox: pick_inbox.call(seq), contact_name: pick_name.call(seq),
            phone: phone_for.call(seq), assignee: ag, msgs: pick_msgs.call(seq),
            base_time: now - (seq + 1).hours, read: false, tag: TAG)
  created[:other_agent] += 1
  seq += 1
end

# C) 3 atribuidas ao ADMIN (aba "Minhas"), nao-lidas
3.times do
  make_conv(account: account, inbox: pick_inbox.call(seq), contact_name: pick_name.call(seq),
            phone: phone_for.call(seq), assignee: admin, msgs: pick_msgs.call(seq),
            base_time: now - (seq + 1).hours, read: false, tag: TAG)
  created[:mine] += 1
  seq += 1
end

# D) 2 LIDAS (controle negativo) - nao devem aparecer em "Nao Lidas"
2.times do
  make_conv(account: account, inbox: pick_inbox.call(seq), contact_name: "#{pick_name.call(seq)} [LIDA]",
            phone: phone_for.call(seq), assignee: admin, msgs: pick_msgs.call(seq),
            base_time: now - (seq + 1).hours, read: true, tag: TAG)
  created[:read_control] += 1
  seq += 1
end

puts '== Seed unread concluido =='
puts created.inspect
total = account.conversations.where(SEED_SQL, TAG).count
unread = account.conversations.where(SEED_SQL, TAG).unread.count
puts "Conversas unread_demo: #{total} | dessas, em scope .unread: #{unread} (esperado #{total - created[:read_control]})"
