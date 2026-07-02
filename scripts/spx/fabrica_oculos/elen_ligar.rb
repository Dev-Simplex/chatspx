# Liga a Elen nativa na inbox 2 (WhatsApp "Fabrica") e testa o caminho AUTOMATICO completo.
# 1) CaptainInbox(2,1) = elegibilidade (gate real do assign_ai_agent). 2) AutomationRule conversation_created -> assign_ai_agent.
# 3) Cria conversa NOVA sem atribuir na mao -> espera o pipeline async -> verifica resposta da Elen.
# Uso: RAILS_ENV=production bundle exec rails runner Temp/elen_ligar.rb

account   = Account.find(1)
assistant = Captain::Assistant.find(1)
INBOX_ID  = 2

ci = CaptainInbox.find_or_create_by!(inbox_id: INBOX_ID, captain_assistant_id: assistant.id)
puts "CaptainInbox: inbox #{ci.inbox_id} -> assistant #{ci.captain_assistant_id} (#{assistant.name})"

rule = AutomationRule.find_or_initialize_by(account_id: account.id, name: 'Elen - atribuir IA em conversa nova (WhatsApp)')
rule.description = 'Atribui a Elen (IA) a toda conversa nova na inbox WhatsApp Fabrica (inbox 2).'
rule.event_name  = 'conversation_created'
rule.active      = true
rule.conditions  = [
  { 'attribute_key' => 'inbox_id', 'filter_operator' => 'equal_to', 'values' => [INBOX_ID], 'query_operator' => nil, 'custom_attribute_type' => '' }
]
rule.actions = [
  { 'action_name' => 'assign_ai_agent', 'action_params' => [assistant.id] }
]
rule.save!
puts "AutomationRule ##{rule.id} ativa=#{rule.active} ev=#{rule.event_name} cond=#{rule.conditions.inspect} act=#{rule.actions.inspect}"

# ---- TESTE AUTOMATICO ----
phone = '+5566900000002'
ci2 = ContactInbox.joins(:contact).where(inbox_id: INBOX_ID, contacts: { phone_number: phone }).first
ci2 ||= ContactInboxWithContactBuilder.new(
  source_id: phone, inbox: Inbox.find(INBOX_ID),
  contact_attributes: { name: 'Teste Auto Elen', phone_number: phone }
).perform

conv = Conversation.create!(
  account_id: account.id, inbox_id: INBOX_ID,
  contact_id: ci2.contact_id, contact_inbox_id: ci2.id, status: :open
)
puts "conv #{conv.display_id} criada SEM atribuicao manual (assignee_bot=#{conv.assignee_agent_bot_id.inspect})"

conv.messages.create!(
  account_id: account.id, inbox_id: INBOX_ID, message_type: :incoming,
  content: 'Boa noite! Queria saber dos óculos de grau. Sou de Cuiabá.', sender: ci2.contact
)
puts 'incoming criado. aguardando pipeline async (regra -> assign -> debounce -> resposta)...'
sleep 50

conv.reload
puts "apos espera: assignee_agent_bot_id=#{conv.assignee_agent_bot_id.inspect} status=#{conv.status}"
outs = conv.messages.where(message_type: :outgoing).order(:id)
puts "=== RESPOSTA AUTOMATICA DA ELEN (#{outs.count} bolha(s)) ==="
outs.each_with_index { |m, i| puts "  [#{i + 1}] (#{m.sender_type}##{m.sender_id}) #{m.content}" }
puts "=== fim (conv #{conv.display_id} visivel na UI) ==="
