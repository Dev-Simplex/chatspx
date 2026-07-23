# Cenário de teste da feature "Puxar Atendimento" (takeover_request_gate).
# Monta, da ótica do AGENTE A (iso.agente.a@simplexteste.local / Teste@123456),
# um caso para cada superfície: Solicitar (compose + dropdown da conversa + aba
# "Em atendimento" + página de contato), Assumir, Abrir, Bloqueado e Pedido
# pendente (com banner do lado do dono).
#
# Rodar:  RAILS_ENV=production bundle exec rails runner task/puxar_demo_seed.rb
# Limpar: RAILS_ENV=production bundle exec rails runner task/puxar_demo_clean.rb
#
# Tudo é marcado com additional_attributes['seed'] = 'puxar_demo' e é idempotente.

SEED_TAG = 'puxar_demo'.freeze

acc     = Account.find(1)
inbox   = acc.inboxes.find(5)                        # "Isolamento Agente (teste)" — A/B/C/D membros
suporte = acc.teams.find_by!(name: 'suporte')        # A/B/C
vendas  = acc.teams.find_by!(name: 'vendas')         # D

agent_a = User.find(10) # requisitante (logue como ele)
agent_b = User.find(11) # colega do time suporte
agent_c = User.find(12) # colega do time suporte
agent_d = User.find(13) # de outro time (vendas)

def upsert_contact!(acc, name, phone)
  # Busca pela tag+nome (estável): o Chatwoot normaliza o telefone (9º dígito BR),
  # então procurar pelo phone cru quebra a idempotência na re-execução.
  c = acc.contacts.where("additional_attributes ->> 'seed' = ?", 'puxar_demo').find_by(name: name)
  c ||= acc.contacts.new
  c.name = name
  c.phone_number = phone if c.phone_number.blank? # não re-normaliza um já salvo
  c.additional_attributes = (c.additional_attributes || {}).merge('seed' => 'puxar_demo')
  c.save!
  c
end

def upsert_conversation!(acc, inbox, contact, assignee:, team:, minutes_ago:, body:)
  ci = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) do |x|
    x.source_id = "puxar-demo-#{contact.id}"
  end
  conv = Conversation.find_or_initialize_by(account: acc, inbox: inbox, contact_inbox: ci)
  novo = conv.new_record?
  conv.contact  = contact
  conv.assignee = assignee
  conv.team     = team
  conv.status   = :open
  conv.additional_attributes = (conv.additional_attributes || {}).merge('seed' => 'puxar_demo')
  conv.save!

  if novo && body
    msg = conv.messages.create!(
      account: acc, inbox: inbox, message_type: :incoming, content: body, sender: contact
    )
    msg.update_columns(created_at: minutes_ago.minutes.ago, updated_at: minutes_ago.minutes.ago)
  end
  # "aberto há X" na aba lê created_at; a ordenação lê last_activity_at.
  t = minutes_ago.minutes.ago
  conv.update_columns(created_at: t, last_activity_at: t)
  conv
end

ActiveRecord::Base.transaction do
  # 1) Dono = colega B (mesmo time) → A pode SOLICITAR
  c1 = upsert_contact!(acc, 'Puxar Demo — Bruno (dono B)', '+556690000001')
  upsert_conversation!(acc, inbox, c1, assignee: agent_b, team: suporte, minutes_ago: 35,
                                       body: 'Oi, meu pedido ainda não chegou, podem verificar?')

  # 2) Dono = colega C (mesmo time) → A pode SOLICITAR (2º caso)
  c2 = upsert_contact!(acc, 'Puxar Demo — Carla (dono C)', '+556690000002')
  upsert_conversation!(acc, inbox, c2, assignee: agent_c, team: suporte, minutes_ago: 90,
                                       body: 'Preciso trocar o endereço de entrega.')

  # 3) Sem dono (fila) → A pode ASSUMIR / enviar normal
  c3 = upsert_contact!(acc, 'Puxar Demo — Diana (sem dono)', '+556690000003')
  upsert_conversation!(acc, inbox, c3, assignee: nil, team: nil, minutes_ago: 15,
                                       body: 'Bom dia! Alguém pode me ajudar com a segunda via do boleto?')

  # 4) Dono = eu (A) → A ABRE / envia normal
  c4 = upsert_contact!(acc, 'Puxar Demo — Eduardo (meu)', '+556690000004')
  upsert_conversation!(acc, inbox, c4, assignee: agent_a, team: nil, minutes_ago: 200,
                                       body: 'Obrigado pelo atendimento de ontem!')

  # 5) Dono = D, time vendas → A NÃO participa de vendas → BLOQUEADO
  c5 = upsert_contact!(acc, 'Puxar Demo — Fabio (outro time)', '+556690000005')
  upsert_conversation!(acc, inbox, c5, assignee: agent_d, team: vendas, minutes_ago: 300,
                                       body: 'Quero um orçamento para compra em grande volume.')

  # 6) Dono = B + pedido PENDENTE de A → A vê "Pedido enviado · Cancelar"; B vê o banner
  c6 = upsert_contact!(acc, 'Puxar Demo — Gustavo (pedido pendente)', '+556690000006')
  conv6 = upsert_conversation!(acc, inbox, c6, assignee: agent_b, team: suporte, minutes_ago: 60,
                                               body: 'Já falei com outro atendente antes, podem retomar?')
  ConversationTakeoverRequest.find_or_create_by!(conversation: conv6, requester: agent_a, status: :pending) do |r|
    r.account  = acc
    r.owner_id = agent_b.id # snapshot do dono no momento do pedido
    r.reason   = 'O cliente pediu para continuar comigo.'
  end
end

puts '=== SEED puxar_demo aplicado ==='
Conversation.uncached do
  acc.conversations
     .where("additional_attributes ->> 'seed' = ?", SEED_TAG)
     .order(:id).each do |cv|
    dono = cv.assignee&.name || '(sem dono)'
    time = cv.team&.name || '(sem time)'
    puts "conv ##{cv.display_id}  #{cv.contact.name}  dono=#{dono}  time=#{time}  status=#{cv.status}"
  end
end
pend = ConversationTakeoverRequest.pending.joins(:conversation)
                                  .where(conversations: { account_id: 1 })
                                  .where("conversations.additional_attributes ->> 'seed' = ?", SEED_TAG)
puts "pedidos pendentes (seed): #{pend.count}"
puts 'Logue como iso.agente.a@simplexteste.local / Teste@123456 e teste as superfícies.'
