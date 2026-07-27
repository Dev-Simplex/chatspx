# -*- coding: utf-8 -*-
# Cria o template de encerramento de atendimento (MARKETING/pt_BR) na WABA da inbox 91.
# {{1}}=nome do lead. Sem botoes. Uso: resposta manual em conversas (nao e disparo em massa).
# Rodar no box prod: RAILS_ENV=production bundle exec rails runner scripts/spx/tozi/create_encerramento_template.rb
require 'net/http'
require 'json'

pc = Inbox.find(91).channel.provider_config || {}
waba = pc['business_account_id']
token = pc['api_key']
abort 'WABA/token ausente' if waba.to_s.empty? || token.to_s.empty?

body = "Olá {{1}}, tudo bem?\n\n" \
  "Após algumas tentativas de contato, percebo que talvez este não seja o melhor momento " \
  "para avançarmos com a parceria. Entendo que prioridades podem mudar, e respeito seu tempo.\n\n" \
  "Estou encerrando este atendimento. Caso no futuro veja valor em retomarmos essa conversa, " \
  "ficarei à disposição para explorarmos juntos as melhores oportunidades. " \
  "Agradeço pela atenção até aqui e desejo sucesso!"

payload = {
  name: 'tozi_encerramento_atendimento',
  language: 'pt_BR',
  category: 'MARKETING',
  components: [
    { type: 'BODY',
      text: body,
      example: { body_text: [%w[Maria]] } },
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
puts "tozi_encerramento_atendimento -> HTTP #{res.code}"
puts "  #{res.body}"
