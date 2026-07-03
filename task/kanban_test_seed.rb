# frozen_string_literal: true

# Seed de teste para o Kanban: cria 6 cards (funnel_items) no funil "Geral" (#12).
# Cada card = uma conversa nova com contato + 1 mensagem incoming.
# Idempotente: marca com additional_attributes['seed']='kanban_test'.
# Para limpar: veja task/kanban_test_clean.rb
account = Account.order(:id).first
TAG = 'kanban_test'
SEED_SQL = "additional_attributes->>'seed' = ?"
FUNNEL_ID = 12

funnel = Funnel.find(FUNNEL_ID)
stages = funnel.stages_ordered.to_a
abort "Funil #{FUNNEL_ID} sem estagios" if stages.empty?

already = account.conversations.where(SEED_SQL, TAG).where(id: FunnelItem.where(funnel_id: FUNNEL_ID).select(:conversation_id)).count
if already >= 6
  puts "Ja semeado (#{already} cards kanban_test no funil ##{FUNNEL_ID}). Nada a fazer."
  exit 0
end

admin  = account.account_users.where(role: :administrator).first.user
inbox  = account.inboxes.find_by(name: 'WhatsApp Vendas') || account.inboxes.order(:id).first
now    = Time.current

# [nome, telefone, mensagem, indice_do_estagio]
CARDS = [
  ['Roberto Almeida (teste kanban)',  '+5566990000101', 'Ola, quero um orcamento para 200 sacas de soja.',                0],
  ['Mariana Costa (teste kanban)',    '+5566990000102', 'Bom dia! Preciso de uma simulacao de financiamento.',            2],
  ['Carlos Eduardo (teste kanban)',   '+5566990000103', 'Voces entregam em Sinop? Qual o prazo?',                          0],
  ['Fernanda Lima (teste kanban)',    '+5566990000104', 'Gostaria de fechar o pedido que conversamos ontem.',             0],
  ['Paulo Henrique (teste kanban)',   '+5566990000105', 'Pode refazer a simulacao com entrada de 30%?',                   2],
  ['Juliana Santos (teste kanban)',   '+5566990000106', 'Recebi tudo certinho, muito obrigada pelo atendimento!',         3]
].freeze

created = 0
CARDS.each_with_index do |(name, phone, msg, stage_idx), i|
  stage = stages[stage_idx] || stages.first
  contact = account.contacts.create!(name: name, phone_number: phone,
                                     additional_attributes: { 'seed' => TAG })
  ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  base = now - (i + 1).hours
  conv = account.conversations.create!(
    inbox: inbox, contact: contact, contact_inbox: ci, assignee: admin,
    status: :open, additional_attributes: { 'seed' => TAG },
    created_at: base, updated_at: base
  )
  conv.messages.create!(account: account, inbox: inbox, message_type: :incoming,
                        content: msg, sender: contact, created_at: base)
  FunnelItem.create!(conversation: conv, funnel: funnel, funnel_stage: stage,
                     moved_by: admin, moved_at: base)
  created += 1
  puts "Card #{created}: '#{name}' -> estagio '#{stage.name}' (conv ##{conv.id})"
end

puts "OK: #{created} cards criados no funil ##{FUNNEL_ID} '#{funnel.name}'."
