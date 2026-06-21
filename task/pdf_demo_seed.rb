# frozen_string_literal: true
# rubocop:disable all

# Seed de DEMONSTRACAO para os relatorios PDF brandeados (homolog, conta Simplex Dev).
# Idempotente: marca conversas com additional_attributes['seed']='pdf_demo' e pula se ja semeado.
# Uso: RAILS_ENV=production bundle exec rails runner task/pdf_demo_seed.rb

account = Account.order(:id).first
puts "== Seed PDF demo na conta ##{account.id} #{account.name} =="

SEED_TAG = 'pdf_demo'
already = account.conversations.where("additional_attributes->>'seed' = ?", SEED_TAG).count
if already >= 100
  puts "Ja semeado (#{already} conversas marcadas). Nada a fazer."
  exit 0
end

RANGE_START = Time.zone.local(2026, 1, 2)
RANGE_END   = Time.zone.local(2026, 6, 8)
def rand_time(a, b) = Time.zone.at(rand(a.to_i..b.to_i))

AGENT_NAMES = ['Ana Paula de Oliveira', 'Emily Santos', 'Misya Correa', 'Cibely Oliveira',
               'Natalia Silva', 'Victoria Fabonatto', 'Gelson de Paula', 'Cibele Heloisa']
TEAM_NAMES  = ['Vendas', 'Suporte', 'Pos-venda']
INBOX_NAMES = ['WhatsApp Vendas', 'WhatsApp Suporte', 'Site / Widget']
LABEL_DEFS  = [['financeiro', '#e54666'], ['agendamento', '#2dc46f'], ['duvida', '#ffc53d'], ['reclamacao', '#6e56cf']]

# ---------- Agentes ----------
agents = AGENT_NAMES.each_with_index.map do |name, i|
  email = "demo.agent#{i + 1}@simplexdemo.local"
  user = User.find_by(email: email) || User.create!(
    name: name, email: email, password: 'Demo123!@#Seed', confirmed_at: Time.current
  )
  account.account_users.find_or_create_by!(user: user) { |au| au.role = :agent }
  user
end
puts "Agentes: #{agents.size}"

# ---------- Inboxes ----------
inboxes = INBOX_NAMES.map do |name|
  inbox = account.inboxes.find_by(name: name)
  unless inbox
    channel = Channel::Api.create!(account: account, webhook_url: '')
    inbox = account.inboxes.create!(name: name, channel: channel, enable_auto_assignment: false)
  end
  agents.each { |u| inbox.inbox_members.find_or_create_by!(user: u) }
  inbox
end
puts "Inboxes: #{account.inboxes.count}"

# ---------- Bot (p/ relatorio Bot) ----------
bot_inbox = inboxes.first
begin
  bot = account.agent_bots.find_by(name: 'Demo Bot') || account.agent_bots.create!(name: 'Demo Bot', bot_type: 'webhook', outgoing_url: 'https://example.com/bot')
  AgentBotInbox.find_or_create_by!(inbox: bot_inbox, agent_bot: bot, account_id: account.id) { |abi| abi.status = :active }
  puts "Bot ativo na inbox ##{bot_inbox.id} (active_bot?=#{bot_inbox.reload.active_bot?})"
rescue StandardError => e
  puts "Bot setup falhou (segue sem): #{e.message}"
end

# ---------- Teams ----------
teams = TEAM_NAMES.map do |name|
  team = account.teams.find_by(name: name) || account.teams.create!(name: name)
  agents.first(4).each { |u| team.team_members.find_or_create_by!(user: u) }
  team
end
puts "Teams: #{account.teams.count}"

# ---------- Labels ----------
LABEL_DEFS.each { |title, color| account.labels.find_or_create_by!(title: title) { |l| l.color = color } }
label_titles = account.labels.pluck(:title)
puts "Labels: #{label_titles.size}"

# ---------- Helpers de evento ----------
def add_event(account:, conv:, name:, user_id:, value:, at:)
  ReportingEvent.create!(
    account_id: account.id, conversation_id: conv.id, inbox_id: conv.inbox_id, user_id: user_id,
    name: name, value: value, value_in_business_hours: (value * 0.7).round,
    event_start_time: at, event_end_time: at + value, created_at: at, updated_at: at
  )
end

# ---------- Conversas + eventos ----------
N_CONV = 140
created = 0
contacts_pool = []
N_CONV.times do |i|
  inbox = inboxes.sample
  agent = agents.sample
  team = teams.sample
  t = rand_time(RANGE_START, RANGE_END)
  resolved = rand < 0.72

  contact = account.contacts.create!(name: "Cliente Demo #{i + 1}", phone_number: "+5566#{format('%09d', rand(1_000_000_00))}")
  contacts_pool << contact
  ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  conv = account.conversations.create!(
    inbox: inbox, contact: contact, contact_inbox: ci, assignee: agent, team: team,
    status: resolved ? :resolved : :open,
    additional_attributes: { 'seed' => 'pdf_demo' }, created_at: t, updated_at: t
  )
  conv.update_columns(created_at: t, updated_at: t)
  conv.update!(label_list: label_titles.sample(rand(1..2))) if label_titles.any?

  # eventos de tempo (segundos)
  add_event(account: account, conv: conv, name: 'first_response', user_id: agent.id, value: rand(20..900), at: t + 60) if rand < 0.9
  add_event(account: account, conv: conv, name: 'first_response_after_assignment', user_id: agent.id, value: rand(15..700), at: t + 90) if rand < 0.7
  rand(1..3).times { |k| add_event(account: account, conv: conv, name: 'reply_time', user_id: agent.id, value: rand(60..2400), at: t + 120 + (k * 60)) }
  add_event(account: account, conv: conv, name: 'conversation_resolved', user_id: agent.id, value: rand(600..120_000), at: t + rand(600..80_000)) if resolved

  # bot: parte das conversas da bot_inbox geram handoff/resolved
  if inbox.id == bot_inbox.id
    if rand < 0.5
      add_event(account: account, conv: conv, name: 'conversation_bot_resolved', user_id: nil, value: rand(30..600), at: t + 30)
    elsif rand < 0.6
      add_event(account: account, conv: conv, name: 'conversation_bot_handoff', user_id: nil, value: rand(30..600), at: t + 30)
    end
    # mensagens do bot (p/ message_count)
    rand(1..4).times { conv.messages.create!(account: account, inbox: inbox, message_type: :outgoing, content: 'Mensagem automatica do bot', created_at: t + rand(10..200)) }
  end

  created += 1
end
puts "Conversas criadas: #{created}"

# ---------- NPS ----------
nps_made = 0
account.conversations.where("additional_attributes->>'seed' = ?", SEED_TAG).includes(:assignee, :contact, :inbox).limit(110).each_with_index do |conv, i|
  next if conv.nps_responses.exists?

  status = i < 78 ? :responded : (i < 95 ? :sent : (i.even? ? :expired : :dismissed))
  score = nil
  answered = nil
  if status == :responded
    score = [10, 10, 10, 9, 10, 8, 10, 9, 7, 3, 0, 10, 6][i % 13]
    answered = conv.created_at + 1.day
  end
  NpsResponse.create!(
    account: account, conversation: conv, contact: conv.contact, inbox: conv.inbox,
    assigned_agent: conv.assignee, status: status, score: score,
    sent_at: conv.created_at + 2.hours, answered_at: answered, created_at: conv.created_at
  )
  nps_made += 1
end
puts "NPS criados: #{nps_made}"

# ---------- CSAT ----------
csat_made = 0
account.conversations.where("additional_attributes->>'seed' = ?", SEED_TAG).where(status: :resolved).includes(:assignee, :contact, :inbox).limit(75).each_with_index do |conv, i|
  next if account.csat_survey_responses.exists?(conversation_id: conv.id)

  msg = conv.messages.create!(account: account, inbox: conv.inbox, message_type: :outgoing,
                              content: 'Como voce avalia nosso atendimento?', content_type: 'input_csat', created_at: conv.created_at + 1.hour)
  rating = [5, 5, 4, 5, 3, 5, 4, 2, 5, 1][i % 10]
  fb = ['Excelente atendimento!', 'Muito atencioso', '', 'Resolveu rapido', 'Poderia melhorar', ''][i % 6]
  CsatSurveyResponse.create!(
    account: account, conversation: conv, contact: conv.contact, message: msg,
    assigned_agent: conv.assignee, rating: rating, feedback_message: fb.presence, created_at: conv.created_at + 2.hours
  )
  csat_made += 1
end
puts "CSAT criados: #{csat_made}"

# ---------- SLA (enterprise) ----------
if ChatwootApp.enterprise? && defined?(AppliedSla)
  begin
    policies = ['SLA Padrao', 'SLA Premium', 'SLA VIP'].map do |name|
      account.sla_policies.find_by(name: name) || account.sla_policies.create!(
        name: name, first_response_time_threshold: 3600, next_response_time_threshold: 7200, resolution_time_threshold: 86_400
      )
    end
    sla_made = 0
    account.conversations.where("additional_attributes->>'seed' = ?", SEED_TAG).limit(70).each_with_index do |conv, i|
      next if AppliedSla.exists?(conversation_id: conv.id)

      status = i < 42 ? :hit : (i < 58 ? :missed : :active_with_misses)
      AppliedSla.create!(account: account, conversation: conv, sla_policy: policies.sample,
                         sla_status: status, created_at: conv.created_at)
      sla_made += 1
    end
    puts "SLA policies: #{account.sla_policies.count} | applied_slas criados: #{sla_made}"
  rescue StandardError => e
    puts "SLA seed falhou (segue): #{e.class} #{e.message}"
  end
else
  puts 'SLA: nao-enterprise, pulado.'
end

puts '== Seed concluido =='
puts "reporting_events: #{account.reporting_events.count} | nps: #{account.nps_responses.count} | csat: #{account.csat_survey_responses.count}"
