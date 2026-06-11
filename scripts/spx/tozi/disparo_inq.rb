# -*- coding: utf-8 -*-
# Disparo INQUILINOS — 3 templates (lancamento/invest com imagem, cliente texto),
# 3 corretores (Bruno/Kettlen/Lucas), CAP 1200, decorrelacionado, dedup live + fake, 5s.
require 'csv'
require 'set'

CSV_PATH = '/home/chatwoot/tozi_inquilinos_limpa.csv'
INBOX_ID = 91
BROKERS = [131, 126, 127].freeze              # Bruno, Kettlen, Lucas
TEMPLATES = %w[tozi_inq_lancamento tozi_inq_invest tozi_inq_cliente].freeze
STEP = 5
LIMIT = (ENV['LIMIT'] || '1200').to_i
DRY = ENV['DRY'] == '1'
NAMES = { 131 => 'Bruno', 126 => 'Kettlen', 127 => 'Lucas' }.freeze

def canonical(raw)
  d = raw.to_s.gsub(/\D/, '')
  d = d[2..] if d.start_with?('55') && d.length >= 12
  return nil unless d.length.between?(10, 11)

  d[0, 2] + d[-8, 8]
end

def fake?(e164)
  e164.to_s.gsub(/\D/, '') =~ /(\d)\1{6,}/ ? true : false
end

cid = Campaign.find_by(title: 'Disparo Venda Tozi')&.id
puts "campaign_id=#{cid.inspect} | CAP=#{LIMIT} | templates=#{TEMPLATES.size} | corretores=#{BROKERS.map { |b| NAMES[b] }.join(', ')}"

sent = Set.new
Conversation.where(inbox_id: INBOX_ID)
            .where("additional_attributes->>'source' = ?", 'disparo_lancamento')
            .includes(:contact).find_each { |c| x = canonical(c.contact&.phone_number); sent << x if x }
puts "ja-enviados (dedup): #{sent.size}"

leads = []
seen = Set.new
skip = Hash.new(0)
CSV.read(CSV_PATH, headers: true).each do |row|
  e164 = row['telefone_e164'].to_s.strip
  nome = row['nome'].to_s.strip
  c = canonical(e164)
  if c.nil? then skip[:no_canon] += 1; next end
  if fake?(e164) then skip[:fake] += 1; next end
  if sent.include?(c) then skip[:ja_enviado] += 1; next end
  if seen.include?(c) then skip[:dup] += 1; next end

  seen << c
  leads << { nome: nome, telefone: e164 }
end
disponiveis = leads.size
leads = leads.first(LIMIT) if LIMIT.positive?
puts "disponiveis: #{disponiveis} | vao receber (cap): #{leads.size} | skip: #{skip.inspect}"

xtab = Hash.new(0)
leads.each_with_index do |lead, j|
  assignee = BROKERS[j % BROKERS.size]
  template = TEMPLATES[(j + j / BROKERS.size) % TEMPLATES.size]
  xtab[[assignee, template]] += 1
  next if DRY

  Spx::Tozi::DisparoLeadJob.set(wait: (STEP * j).seconds).perform_later(
    nome: lead[:nome], telefone: lead[:telefone], assignee_id: assignee,
    template: template, campaign_id: cid
  )
end

mins = (STEP * [leads.size - 1, 0].max / 60.0).round
puts((DRY ? '== DRY-RUN ==' : '== ENFILEIRADO ==') + " #{leads.size} · 1/#{STEP}s · ~#{mins}min")
puts '== por template =='
TEMPLATES.each { |t| puts "  #{t.ljust(22)} #{xtab.select { |k, _| k[1] == t }.values.sum}" }
puts '== por corretor =='
BROKERS.each { |b| puts "  #{NAMES[b].ljust(8)} #{xtab.select { |k, _| k[0] == b }.values.sum}" }
