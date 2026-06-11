# -*- coding: utf-8 -*-
# Cria o template curto de abertura (MARKETING/pt_BR) na WABA da inbox 91.
# {{1}}=nome do lead, {{2}}=corretor. 2 botoes quick-reply.
require 'net/http'
require 'json'

pc = Inbox.find(91).channel.provider_config || {}
waba = pc['business_account_id']
token = pc['api_key']
abort 'WABA/token ausente' if waba.to_s.empty? || token.to_s.empty?

payload = {
  name: 'tozi_venda_abertura',
  language: 'pt_BR',
  category: 'MARKETING',
  components: [
    { type: 'BODY',
      text: 'Oi {{1}}, tudo bem? Aqui é {{2}}, da Tozi Imóveis. Tá podendo falar agora?',
      example: { body_text: [%w[Maria Lucas]] } },
    { type: 'BUTTONS', buttons: [
      { type: 'QUICK_REPLY', text: 'Sim, pode falar' },
      { type: 'QUICK_REPLY', text: 'Agendar horário' },
    ] },
  ],
}

uri = URI("https://graph.facebook.com/v22.0/#{waba}/message_templates")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
req = Net::HTTP::Post.new(uri)
req['Authorization'] = "Bearer #{token}"
req['Content-Type'] = 'application/json; charset=utf-8'
req.body = JSON.generate(payload)
res = http.request(req)
puts "tozi_venda_abertura -> HTTP #{res.code}"
puts "  #{res.body}"
