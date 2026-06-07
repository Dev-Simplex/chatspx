# -*- coding: utf-8 -*-
# Cria 3 templates INQUILINOS MARKETING/pt_BR. 2 com header IMAGE (mapa localizacao), 1 texto.
# SEM variavel de corpo (sem nome). Botoes: Tenho interesse / Me chama depois.
require 'net/http'
require 'json'

APP_ID = '1147301410628990'
pc = Inbox.find(91).channel.provider_config || {}
waba = pc['business_account_id']
tok = pc['api_key']
IMG = '/tmp/inq_mapa.jpeg'
abort 'WABA/token ausente' if waba.to_s.empty? || tok.to_s.empty?

# Resumable upload -> header_handle (fresco por template)
def upload_handle(app_id, tok, img)
  bytes = File.binread(img)
  u1 = URI("https://graph.facebook.com/v22.0/#{app_id}/uploads")
  u1.query = URI.encode_www_form(file_name: 'inq_mapa.jpeg', file_length: bytes.bytesize,
                                 file_type: 'image/jpeg', access_token: tok)
  h1 = Net::HTTP.new(u1.host, 443); h1.use_ssl = true
  r1 = h1.post(u1.request_uri, '')
  sess = (JSON.parse(r1.body)['id'] rescue nil)
  return [nil, "session FAIL: #{r1.code} #{r1.body}"] unless sess

  u2 = URI("https://graph.facebook.com/v22.0/#{sess}")
  h2 = Net::HTTP.new(u2.host, 443); h2.use_ssl = true
  req = Net::HTTP::Post.new(u2.request_uri)
  req['Authorization'] = "OAuth #{tok}"
  req['file_offset'] = '0'
  req.body = bytes
  r2 = h2.request(req)
  handle = (JSON.parse(r2.body)['h'] rescue nil)
  [handle, "upload: #{r2.code}"]
end

BTNS = [
  { type: 'QUICK_REPLY', text: 'Tenho interesse' },
  { type: 'QUICK_REPLY', text: 'Me chama depois' },
].freeze

templates = [
  { name: 'tozi_inq_lancamento', image: true,
    body: 'Tá chegando o lançamento mais esperado de Sinop: apartamentos de até 3 suítes do lado da UNEMAT, com entrada parcelada na obra. Tô avisando os clientes da casa antes de abrir ao público — quem se antecipa garante as melhores condições. Quer saber mais?' },
  { name: 'tozi_inq_invest', image: true,
    body: 'Quis te mostrar uma oportunidade antes de abrir ao público: lançamento de apartamentos de até 3 suítes na região do Aquarela das Artes, do lado da UNEMAT — uma das que mais valorizam em Sinop. Entrada parcelada na obra, ótima pra morar ou investir. Faz sentido pra você?' },
  { name: 'tozi_inq_cliente', image: false,
    body: 'Como você foi cliente da Tozi, quis te avisar em primeira mão: tá chegando um lançamento de apartamentos de até 3 suítes na região do Aquarela das Artes, com entrada parcelada na obra. Posso te passar os detalhes e reservar sua prioridade antes de abrir ao público?' },
]

uri = URI("https://graph.facebook.com/v22.0/#{waba}/message_templates")
http = Net::HTTP.new(uri.host, 443); http.use_ssl = true

templates.each do |t|
  comps = []
  if t[:image]
    handle, info = upload_handle(APP_ID, tok, IMG)
    puts "  [#{t[:name]}] #{info} handle=#{handle ? 'OK' : 'NIL'}"
    unless handle
      puts "  -> SEM handle, pulando #{t[:name]}"
      next
    end
    comps << { type: 'HEADER', format: 'IMAGE', example: { header_handle: [handle] } }
  end
  comps << { type: 'BODY', text: t[:body] }
  comps << { type: 'BUTTONS', buttons: BTNS }
  payload = { name: t[:name], language: 'pt_BR', category: 'MARKETING', components: comps }
  req = Net::HTTP::Post.new(uri.request_uri)
  req['Authorization'] = "Bearer #{tok}"
  req['Content-Type'] = 'application/json; charset=utf-8'
  req.body = JSON.generate(payload)
  res = http.request(req)
  puts "#{t[:name]} (img=#{t[:image]}) -> #{res.code}: #{res.body}"
end
