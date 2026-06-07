# -*- coding: utf-8 -*-
# Cria os 2 templates QUALIFICADOS (curiosidade ancorada no beneficio) p/ A/B test.
# MARKETING/pt_BR, {{1}}=nome {{2}}=corretor. Botoes iguais nos 2 (isola a copy no teste).
require 'net/http'
require 'json'

pc = Inbox.find(91).channel.provider_config || {}
waba = pc['business_account_id']
token = pc['api_key']
abort 'WABA/token ausente' if waba.to_s.empty? || token.to_s.empty?

templates = [
  { name: 'tozi_venda_oportunidade',
    body: 'Oi {{1}}, aqui é {{2}} da Tozi. Separei uma oportunidade boa pra você antes de abrir ao público — um imóvel que tende a valorizar rápido e que ainda dá pra alugar. Quer que eu te conte como funciona?' },
  { name: 'tozi_venda_lembrei',
    body: 'Oi {{1}}, aqui é {{2}} da Tozi. Apareceu uma oportunidade que combina com quem já é cliente da casa e lembrei de você — algo que valoriza e gera renda. Vale 2 minutos seu pra eu explicar?' },
]

uri = URI("https://graph.facebook.com/v22.0/#{waba}/message_templates")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

templates.each do |t|
  payload = {
    name: t[:name], language: 'pt_BR', category: 'MARKETING',
    components: [
      { type: 'BODY', text: t[:body], example: { body_text: [%w[Maria Lucas]] } },
      { type: 'BUTTONS', buttons: [
        { type: 'QUICK_REPLY', text: 'Quero saber' },
        { type: 'QUICK_REPLY', text: 'Me chama depois' },
      ] },
    ],
  }
  req = Net::HTTP::Post.new(uri)
  req['Authorization'] = "Bearer #{token}"
  req['Content-Type'] = 'application/json; charset=utf-8'
  req.body = JSON.generate(payload)
  res = http.request(req)
  puts "#{t[:name]} -> HTTP #{res.code}: #{res.body}"
end
