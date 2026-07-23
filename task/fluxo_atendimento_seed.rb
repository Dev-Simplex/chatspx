# Monta um fluxo REALISTA de atendimento na caixa 5 (Isolamento Agente/teste)
# para exercitar a feature "Puxar Atendimento" do ponto de vista do AGENTE B.
#
# Antes existia só a conv 226 (dona do próprio B), então o B não tinha nada a
# pedir — dava pra testar só o lado de quem aprova.
#
# Cenário resultante, visto pelo AGENTE B:
#   conv 226  Cliente Isolamento  dono=B   -> "Abrir"      (e é aqui que ele APROVA/NEGA)
#   Cliente Beta                  dono=A   -> "Solicitar"
#   Cliente Gama                  dono=C   -> "Solicitar"
#   Cliente Delta                 sem dono -> "Assumir"
#
# CUIDADO (por isso o script força e confere o dono no fim): a caixa 5 tem
# enable_auto_assignment LIGADO — conversa criada sem dono é auto-atribuída pelo
# round-robin. Definimos o assignee DEPOIS de criar e validamos.
#
# Rodar:  RAILS_ENV=production bundle exec rails runner task/fluxo_atendimento_seed.rb
# Limpar: RAILS_ENV=production bundle exec rails runner task/fluxo_atendimento_cleanup.rb
SEED = 'fluxo_atendimento_demo'.freeze

account = Account.find(1)
inbox = Inbox.find(5)
team_suporte = Team.find_by(account_id: 1, name: 'suporte')
agente_a = User.find(10)
agente_c = User.find(12)

# [nome, telefone, dono (nil = fila), primeira mensagem do cliente]
CENARIO = [
  ['Cliente Beta (teste)', '+5592979000101', agente_a, 'Oi, preciso de ajuda com meu pedido.'],
  ['Cliente Gama (teste)', '+5592979000102', agente_c, 'Bom dia! Meu boleto não chegou.'],
  ['Cliente Delta (teste)', '+5592979000103', nil, 'Alguém pode me atender?']
].freeze

CENARIO.each do |nome, telefone, dono, texto|
  contato = account.contacts.find_or_create_by!(phone_number: telefone) do |c|
    c.name = nome
    c.additional_attributes = { 'seed' => SEED }
  end
  contato.update!(name: nome, additional_attributes: (contato.additional_attributes || {}).merge('seed' => SEED))

  contact_inbox = ContactInbox.find_or_create_by!(contact: contato, inbox: inbox) do |ci|
    ci.source_id = "#{SEED}-#{telefone}"
  end

  conversa = account.conversations.find_by(contact_inbox_id: contact_inbox.id, status: %w[open pending snoozed])
  conversa ||= account.conversations.create!(
    contact: contato, contact_inbox: contact_inbox, inbox: inbox,
    additional_attributes: { 'seed' => SEED }
  )

  # mensagem do cliente p/ a conversa parecer real na tela
  if conversa.messages.where(message_type: :incoming).none?
    # sender é polimórfico (sender_type/sender_id); numa incoming, é o contato.
    conversa.messages.create!(account: account, inbox: inbox, sender: contato,
                              message_type: :incoming, content: texto)
  end

  # dono FORÇADO depois da criação (o round-robin da caixa atribui sozinho)
  conversa.reload
  conversa.update!(team: team_suporte, assignee_id: dono&.id, status: :open)
  conversa.reload
  esperado = dono&.name || 'SEM DONO'
  obtido = conversa.assignee&.name || 'SEM DONO'
  marca = obtido == esperado ? 'ok' : "ATENCAO (esperado #{esperado})"
  puts "  conv=#{conversa.display_id} #{nome.ljust(24)} dono=#{obtido.ljust(16)} #{marca}"
end

# a 226 continua com o B: é onde ele APROVA/NEGA os pedidos que receber
conv226 = Conversation.find_by(display_id: 226, account_id: 1)
conv226&.update!(assignee_id: 11)
puts "  conv=226 Cliente Isolamento     dono=#{conv226&.assignee&.name} (o B aprova/nega aqui)"

ConversationTakeoverRequest.where(account_id: 1).delete_all
puts ''
puts "pedidos pendentes zerados. Flag do modo pedido: #{account.reload.takeover_request_gate_enabled?}"
