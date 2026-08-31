# frozen_string_literal: true
# rubocop:disable all

# Dados de DEMONSTRACAO para a tela Relatorios > Bot, com o recorte por caixa.
# Duas caixas com bot ativo e desempenhos DIFERENTES, para o filtro mostrar servico:
#   WhatsApp Vendas  -> resolve muito, transfere pouco
#   WhatsApp Suporte -> resolve pouco, transfere muito
#
# Idempotente: marca conversas com additional_attributes['seed']='bot_demo'.
# Limpeza:  RAILS_ENV=production bundle exec rails runner task/bot_demo_cleanup.rb
# Uso:      RAILS_ENV=production bundle exec rails runner task/bot_demo_seed.rb

SEED_TAG = 'bot_demo'
account = Account.find(1)
puts "== Seed do relatorio de Bot na conta ##{account.id} #{account.name} =="

ja = account.conversations.where("additional_attributes->>'seed' = ?", SEED_TAG).count
if ja.positive?
  puts "Ja semeado (#{ja} conversas marcadas). Rode o cleanup antes de semear de novo."
  exit 0
end

# ---------- as duas caixas ----------
vendas  = account.inboxes.find_by(name: 'WhatsApp Vendas')
suporte = account.inboxes.find_by(name: 'WhatsApp Suporte')
abort 'Caixas de demo nao encontradas (WhatsApp Vendas / WhatsApp Suporte).' if vendas.nil? || suporte.nil?

# Só mexo em caixa de canal API com webhook vazio — nao quero disparar nada pra fora.
[vendas, suporte].each do |i|
  abort "Caixa ##{i.id} nao e Channel::Api — abortando por seguranca." unless i.channel_type == 'Channel::Api'
  abort "Caixa ##{i.id} tem webhook_url configurado — abortando." if i.channel.webhook_url.present?
end

bot = account.agent_bots.find_by(name: 'Demo Bot') ||
      account.agent_bots.create!(name: 'Demo Bot', bot_type: 'webhook', outgoing_url: 'https://example.com/bot')
[vendas, suporte].each do |inbox|
  AgentBotInbox.find_or_create_by!(inbox: inbox, agent_bot: bot, account_id: account.id) { |abi| abi.status = :active }
end
puts "Bot ativo em: #{vendas.reload.active_bot?} (Vendas) e #{suporte.reload.active_bot?} (Suporte)"

# O fork exige time atribuido para resolver conversa — pego um time por caixa.
time_vendas  = account.teams.find_by(name: 'Vendas')  || account.teams.first
time_suporte = account.teams.find_by(name: 'Suporte') || account.teams.first
abort 'A conta nao tem nenhum time — crie um antes de semear.' if time_vendas.nil?

# ---------- o cenario ----------
# [caixa, time, total de conversas, resolvidas pelo bot, transferidas]
CENARIO = [
  [vendas,  time_vendas,  42, 30, 6],
  [suporte, time_suporte, 26, 11, 9]
].freeze

DESDE = 29.days.ago
ATE   = 1.hour.ago
def instante(a, b) = Time.zone.at(rand(a.to_i..b.to_i))

FALAS = [
  'Ola! Sou o assistente virtual. Como posso ajudar?',
  'Encontrei estes imoveis dentro do que voce procura.',
  'Posso agendar uma visita para voce?',
  'Certo! Vou transferir voce para um corretor.',
  'Perfeito, agendamento confirmado. Ate breve!'
].freeze

def evento(account:, conv:, nome:, valor:, quando:)
  ReportingEvent.create!(
    account_id: account.id, conversation_id: conv.id, inbox_id: conv.inbox_id, user_id: nil,
    name: nome, value: valor, value_in_business_hours: (valor * 0.8).round,
    event_start_time: quando, event_end_time: quando + valor, created_at: quando, updated_at: quando
  )
end

total_conversas = 0
total_mensagens = 0

CENARIO.each do |inbox, time, quantas, resolvidas, transferidas|
  puts "-- #{inbox.name}: #{quantas} conversas (#{resolvidas} resolvidas pelo bot, #{transferidas} transferidas)"
  desfecho = (['resolvida'] * resolvidas) + (['transferida'] * transferidas)
  desfecho += ['nenhum'] * (quantas - desfecho.size)
  desfecho.shuffle!

  quantas.times do |i|
    t = instante(DESDE, ATE)
    contato = account.contacts.create!(
      name: "Cliente Bot #{inbox.id}-#{i + 1}",
      phone_number: "+5565#{format('%09d', rand(100_000_000..999_999_999))}",
      additional_attributes: { 'seed' => SEED_TAG }
    )
    ci = ContactInbox.create!(contact: contato, inbox: inbox, source_id: SecureRandom.uuid)
    conv = account.conversations.create!(
      inbox: inbox, contact: contato, contact_inbox: ci, team: time, status: :resolved,
      additional_attributes: { 'seed' => SEED_TAG }, created_at: t, updated_at: t
    )
    conv.update_columns(created_at: t, updated_at: t)

    # mensagens do bot — insert_all para nao acordar webhook, cable e notificacao
    linhas = rand(2..4).times.map do |k|
      { account_id: account.id, inbox_id: inbox.id, conversation_id: conv.id,
        message_type: 1, content: FALAS[k % FALAS.size], content_type: 0,
        created_at: t + (k * 40) + 10, updated_at: t + (k * 40) + 10 }
    end
    Message.insert_all(linhas)
    total_mensagens += linhas.size

    case desfecho[i]
    when 'resolvida'
      evento(account: account, conv: conv, nome: 'conversation_bot_resolved', valor: rand(40..900), quando: t + rand(60..1200))
    when 'transferida'
      evento(account: account, conv: conv, nome: 'conversation_bot_handoff', valor: rand(30..600), quando: t + rand(60..900))
    end

    total_conversas += 1
  end
end

puts "== Pronto: #{total_conversas} conversas e #{total_mensagens} mensagens do bot =="
p1 = { since: 30.days.ago.to_i.to_s, until: Time.current.to_i.to_s }
geral = V2::Reports::BotMetricsBuilder.new(account, p1).metrics
puts format('  TODAS as caixas: conversas=%d resolucao=%d%% transferencia=%d%%',
            geral[:conversation_count], geral[:resolution_rate], geral[:handoff_rate])
[vendas, suporte].each do |i|
  m = V2::Reports::BotMetricsBuilder.new(account, p1.merge(inbox_id: i.id.to_s)).metrics
  puts format('  %-18s conversas=%d resolucao=%d%% transferencia=%d%%',
              i.name, m[:conversation_count], m[:resolution_rate], m[:handoff_rate])
end
