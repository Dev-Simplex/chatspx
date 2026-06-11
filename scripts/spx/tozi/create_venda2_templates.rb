# -*- coding: utf-8 -*-
# Cria os 3 templates NOVOS de venda (copy refinada) MARKETING/pt_BR na WABA da inbox 91.
# {{1}}=nome do lead, {{2}}=corretor (genero-neutro). Botoes: Tenho interesse / Quero, mas outro horario.
require 'net/http'
require 'json'

pc = Inbox.find(91).channel.provider_config || {}
waba = pc['business_account_id']
token = pc['api_key']
abort 'WABA/token ausente' if waba.to_s.empty? || token.to_s.empty?

templates = [
  { name: 'tozi_venda_condicao',
    body: 'Oi {{1}}, aqui é {{2}}, da Tozi. Vai sair um lançamento esse mês com condição especial nas primeiras unidades, e estou avisando os clientes da casa antes de abrir. É do seu interesse saber mais?' },
  { name: 'tozi_venda_invest',
    body: 'Oi {{1}}, aqui é {{2}}, da Tozi. Vai sair um lançamento com perfil forte de investimento, que valoriza rápido e ainda gera aluguel. Como você já teve imóvel pra venda com a gente, quis te mostrar antes de abrir ao público. É do seu interesse saber mais?' },
  { name: 'tozi_venda_suites',
    body: 'Oi {{1}}, aqui é {{2}}, da Tozi Imóveis. Vamos lançar um apartamento de 3 suítes agora em junho e, antes de abrir ao público, estou dando prioridade pra quem já teve casa pra venda com a gente. É do seu interesse saber mais?' },
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
        { type: 'QUICK_REPLY', text: 'Tenho interesse' },
        { type: 'QUICK_REPLY', text: 'Quero, mas outro horário' },
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
