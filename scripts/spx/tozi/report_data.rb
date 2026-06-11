# -*- coding: utf-8 -*-
# Coleta dados reais dos disparos (campanhas 1=lancamento, 2=venda) + custo Meta.
# Saida: /tmp/report_data.json
require 'json'
require 'net/http'
require 'time'

BUTTONS = ['Tenho interesse', 'Quero saber mais', 'Quero, mas outro horário',
           'Sim, pode falar', 'Agendar horário', 'Quero saber', 'Me chama depois'].freeze
NAMES = { 125 => 'Guilherme', 126 => 'Kettlen', 127 => 'Lucas', 128 => 'Marcus',
          131 => 'Bruno', 63 => 'Adrian', 72 => 'Gelson' }.freeze

result = { campaigns: {} }

{ 1 => 'Lançamento (proprietários de locação)', 2 => 'Venda (proprietários de venda)' }.each do |cid, label|
  convs = Conversation.where(inbox_id: 91, campaign_id: cid)
  conv_ids = convs.pluck(:id)
  msgs = Message.where(conversation_id: conv_ids, message_type: :outgoing)
                .where("additional_attributes->'template_params'->>'name' IS NOT NULL")
  by_status = msgs.reorder(nil).group(:status).count

  codes = Hash.new(0)
  msgs.where(status: :failed).find_each { |m| codes[m.external_error.to_s[/\d{6}/] || 'outro'] += 1 }

  replied = Message.where(conversation_id: conv_ids, message_type: :incoming).distinct.count(:conversation_id)

  btn = Hash.new(0)
  Message.where(conversation_id: conv_ids, message_type: :incoming).find_each do |m|
    t = m.content.to_s.strip
    btn[t] += 1 if BUTTONS.include?(t)
  end

  by_broker = convs.reorder(nil).group(:assignee_id).count.transform_keys { |k| NAMES[k] || "##{k}" }
  by_tmpl = convs.reorder(nil).group(Arel.sql("additional_attributes->>'template'")).count

  replied_ids = Message.where(conversation_id: conv_ids, message_type: :incoming).reorder(nil).distinct.pluck(:conversation_id)
  rep_by_tmpl = Conversation.where(id: replied_ids).reorder(nil).group(Arel.sql("additional_attributes->>'template'")).count

  result[:campaigns][cid] = {
    label: label, total: convs.count, status: by_status, fail_codes: codes,
    replied: replied, buttons: btn, by_broker: by_broker, by_template: by_tmpl,
    replied_by_template: rep_by_tmpl
  }
end

# Custo real (Meta pricing_analytics) — range cobrindo os dois disparos
pc = Inbox.find(91).channel.provider_config
waba = pc['business_account_id']; tok = pc['api_key']
s = Time.parse('2026-06-01 00:00:00 -0400').to_i
e = Time.parse('2026-06-05 23:59:59 -0400').to_i
url = "https://graph.facebook.com/v22.0/#{waba}?fields=pricing_analytics.start(#{s}).end(#{e})" \
      ".granularity(DAILY).dimensions([\"PRICING_CATEGORY\"])&access_token=#{tok}"
pts = (JSON.parse(Net::HTTP.get(URI(url))).dig('pricing_analytics', 'data', 0, 'data_points') || [])
mkt = pts.select { |p| p['pricing_category'] == 'MARKETING' }
result[:cost] = {
  marketing_msgs: mkt.sum { |p| p['volume'].to_i },
  marketing_usd: mkt.sum { |p| p['cost'].to_f }.round(4),
  service_msgs: pts.select { |p| p['pricing_category'] == 'SERVICE' }.sum { |p| p['volume'].to_i }
}

File.write('/tmp/report_data.json', JSON.generate(result))
puts JSON.pretty_generate(result)
