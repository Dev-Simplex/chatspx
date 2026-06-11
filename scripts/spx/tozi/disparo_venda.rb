# -*- coding: utf-8 -*-
# Disparo VENDA Tozi — decorrelacionado, dedup live, filtro de fake, 5s, SEM cap.
# DRY=1 -> so simula (nao enfileira, nao cria campanha). DRY=0 -> enfileira de verdade.
# Pausar: deletar os DisparoLeadJob do Sidekiq::ScheduledSet.
require 'csv'
require 'set'

CSV_PATH = '/home/chatwoot/tozi_venda_limpa.csv'
INBOX_ID = 91
ACCOUNT_ID = 6
BROKERS = [126, 131, 127, 128].freeze            # Kettlen, Bruno, Lucas, Marcus
TEMPLATES = %w[tozi_venda_prioridade tozi_venda_investidor tozi_venda_condicoes].freeze
STEP = 5
DRY = ENV['DRY'] == '1'
NAMES = { 126 => 'Kettlen', 131 => 'Bruno', 127 => 'Lucas', 128 => 'Marcus' }.freeze

def canonical(raw)
  d = raw.to_s.gsub(/\D/, '')
  d = d[2..] if d.start_with?('55') && d.length >= 12
  return nil unless d.length.between?(10, 11)

  d[0, 2] + d[-8, 8]
end

def fake?(e164)
  e164.to_s.gsub(/\D/, '') =~ /(\d)\1{6,}/ ? true : false
end

# campanha ancora #2 (separa stats) — so cria no disparo real
cid = nil
unless DRY
  c = Campaign.find_by(title: 'Disparo Venda Tozi')
  unless c
    c = Campaign.new(account_id: ACCOUNT_ID, inbox_id: INBOX_ID, title: 'Disparo Venda Tozi',
                     message: 'Disparo proprietarios venda - junho', campaign_type: :one_off,
                     campaign_status: :completed)
    begin
      c.save!(validate: false)
    rescue StandardError => e
      puts "campanha falhou (#{e.message}) -> segue sem campaign_id"
      c = nil
    end
  end
  cid = c&.id
end
puts "campaign_id=#{cid.inspect}"

# dedup: ja enviados (source=disparo_lancamento)
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
  if seen.include?(c) then skip[:dup_interno] += 1; next end

  seen << c
  leads << { nome: nome, telefone: e164 }
end
puts "elegiveis: #{leads.size} | skip: #{skip.inspect}"

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
puts((DRY ? '== DRY-RUN (nada enfileirado) ==' : '== ENFILEIRADO DE VERDADE ==') +
     " #{leads.size} leads · 1 a cada #{STEP}s · ultimo ~#{mins}min (#{(mins / 60.0).round(1)}h)")
puts '== cruzamento corretor x template =='
xtab.sort_by { |k, _| [BROKERS.index(k[0]), k[1]] }.each do |(aid, tmpl), n|
  puts "  #{NAMES[aid].ljust(8)} #{tmpl.ljust(24)} #{n}"
end
puts "== por corretor =="
BROKERS.each { |b| puts "  #{NAMES[b].ljust(8)} #{xtab.select { |k, _| k[0] == b }.values.sum}" }
