# -*- coding: utf-8 -*-
# Cria os 3 templates MARKETING/pt_BR da campanha VENDA na WABA da inbox 91.
# {{1}}=nome do lead, {{2}}=corretor. 2 botoes quick-reply positivos.
require 'net/http'
require 'json'

pc = Inbox.find(91).channel.provider_config || {}
waba = pc['business_account_id']
token = pc['api_key']
abort 'WABA/token ausente' if waba.to_s.empty? || token.to_s.empty?

templates = [
  { name: 'tozi_venda_prioridade',
    body: "Oi {{1}}, aqui é o {{2}} da Tozi Imóveis. Tudo bem? Vamos lançar um empreendimento de apartamento de 3 suítes agora em junho e antes de abrir para o público estou dando prioridade para clientes que tiveram casa para venda conosco.\n\nÉ do seu interesse saber mais?" },
  { name: 'tozi_venda_investidor',
    body: "Oi {{1}}, tudo bem? {{2}} aqui, da Tozi. Selecionei alguns clientes nossos para contar que vai sair um lançamento com um perfil de investimento muito forte, tipo de imóvel que valoriza rápido e ainda gera aluguel. Como você já teve imóvel para venda com a gente, achei que valia te mostrar antes de ser aberto a público em geral.\n\nÉ do seu interesse mais informações?" },
  { name: 'tozi_venda_condicoes',
    body: "Oi {{1}}, {{2}} da Tozi. Estamos com previsão para um lançamento esse mês, com condições especiais nas primeiras unidades. Estou fazendo contato antecipado pros clientes da casa.\n\nÉ do seu interesse mais informações?" },
]

uri = URI("https://graph.facebook.com/v22.0/#{waba}/message_templates")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

templates.each do |t|
  payload = {
    name: t[:name],
    language: 'pt_BR',
    category: 'MARKETING',
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
  puts "#{t[:name]} -> HTTP #{res.code}"
  puts "  #{res.body}"
end
