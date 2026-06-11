# -*- coding: utf-8 -*-
# Disparo VENDA — novo lote com template CURTO unico (tozi_venda_abertura),
# 4 corretores (Kettlen/Marcus/Lucas/Bruno), CAP 1000, dedup live + fake, 5s.
# LIMIT=1000 default. DRY=1 simula. Pausar: deletar DisparoLeadJob do ScheduledSet.
require 'csv'
require 'set'

CSV_PATH = '/home/chatwoot/tozi_venda_limpa.csv'
INBOX_ID = 91
BROKERS = [126, 128, 127, 131].freeze        # Kettlen, Marcus, Lucas, Bruno
TEMPLATE = 'tozi_venda_abertura'.freeze
STEP = 5
LIMIT = (ENV['LIMIT'] || '1000').to_i
DRY = ENV['DRY'] == '1'
NAMES = { 126 => 'Kettlen', 128 => 'Marcus', 127 => 'Lucas', 131 => 'Bruno' }.freeze

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
puts "campaign_id=#{cid.inspect} | CAP=#{LIMIT} | template=#{TEMPLATE} | corretores=#{BROKERS.map { |b| NAMES[b] }.join(', ')}"

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

per = Hash.new(0)
leads.each_with_index do |lead, j|
  assignee = BROKERS[j % BROKERS.size]
  per[assignee] += 1
  next if DRY

  Spx::Tozi::DisparoLeadJob.set(wait: (STEP * j).seconds).perform_later(
    nome: lead[:nome], telefone: lead[:telefone], assignee_id: assignee,
    template: TEMPLATE, campaign_id: cid
  )
end

mins = (STEP * [leads.size - 1, 0].max / 60.0).round
puts((DRY ? '== DRY-RUN ==' : '== ENFILEIRADO ==') +
     " #{leads.size} leads · 1 a cada #{STEP}s · ultimo ~#{mins}min (#{(mins / 60.0).round(1)}h)")
BROKERS.each { |b| puts "  #{NAMES[b].ljust(8)} #{per[b]}" }
