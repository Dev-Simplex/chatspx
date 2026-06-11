# -*- coding: utf-8 -*-
# Template de FOLLOW-UP (re-engajamento) MARKETING/pt_BR. 1 variavel ({{1}}=nome).
# Botoes: Tenho interesse / Me chama depois.
require 'net/http'
require 'json'

pc = Inbox.find(91).channel.provider_config || {}
waba = pc['business_account_id']
tok = pc['api_key']
abort 'WABA/token ausente' if waba.to_s.empty? || tok.to_s.empty?

body = 'Oi {{1}}, mandei uma mensagem essa semana e ainda não tive retorno seu. Tenho um lançamento de até 3 suítes saindo no fim do mês. Oportunidade boa pra moradia ou locação, tem interesse? Se sim, explico em 2 minutos.'

payload = {
  name: 'tozi_followup_lanc',
  language: 'pt_BR',
  category: 'MARKETING',
  components: [
    { type: 'BODY', text: body, example: { body_text: [['Maria']] } },
    { type: 'BUTTONS', buttons: [
      { type: 'QUICK_REPLY', text: 'Tenho interesse' },
      { type: 'QUICK_REPLY', text: 'Me chama depois' },
    ] },
  ],
}

uri = URI("https://graph.facebook.com/v22.0/#{waba}/message_templates")
http = Net::HTTP.new(uri.host, 443); http.use_ssl = true
req = Net::HTTP::Post.new(uri.request_uri)
req['Authorization'] = "Bearer #{tok}"
req['Content-Type'] = 'application/json; charset=utf-8'
req.body = JSON.generate(payload)
res = http.request(req)
puts "tozi_followup_lanc -> #{res.code}: #{res.body}"
