# Smoke-test carrossel — PASSO 2: envio (conta 3, HML .232, inbox 44)
# Prova: (a) typing indicator (v23.0) e (b) interactive media carousel (3 cards + quick replies).
# Alvo: contato da mensagem incoming MAIS RECENTE do inbox (janela aberta pelo Paulo via celular).
# Override: SMOKE_TO=5566999999999 (digitos) força o destinatário.
# Não imprime credenciais.
require 'net/http'
require 'json'

INBOX_ID = 44
GRAPH_VER = 'v23.0'.freeze

inbox = Inbox.find(INBOX_ID)
raise "inbox errada" unless inbox.account_id == 3

cfg = inbox.channel.provider_config
phone_number_id = cfg['phone_number_id']
api_key = cfg['api_key']

def graph_post(phone_number_id, api_key, payload)
  uri = URI("https://graph.facebook.com/#{GRAPH_VER}/#{phone_number_id}/messages")
  req = Net::HTTP::Post.new(uri)
  req['Authorization'] = "Bearer #{api_key}"
  req['Content-Type'] = 'application/json'
  req.body = payload.to_json
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  [res.code.to_i, res.body.to_s]
end

# --- localizar a última incoming do inbox (ou o contato do SMOKE_TO) ---
# ⚠️ Message tem default_scope order(created_at: :asc) — usar reorder, senão .first pega a mais ANTIGA
scope = Message.where(inbox_id: INBOX_ID, message_type: :incoming)
if ENV['SMOKE_TO'].to_s.strip.length > 5
  digits = ENV['SMOKE_TO'].gsub(/\D/, '')
  contact = Contact.where(account_id: 3).where("phone_number LIKE ?", "%#{digits[-10..]}").order(updated_at: :desc).first
  raise "contato nao encontrado pro SMOKE_TO" unless contact
  conv_ids = Conversation.where(inbox_id: INBOX_ID, contact_id: contact.id).pluck(:id)
  last_in = scope.where(conversation_id: conv_ids).reorder(created_at: :desc).first
else
  last_in = scope.reorder(created_at: :desc).first
end
raise "nenhuma mensagem incoming no inbox #{INBOX_ID} — mande uma msg do celular pro numero antes" unless last_in

contact = last_in.conversation.contact
to = contact.phone_number.to_s.gsub(/\D/, '')
age_h = ((Time.zone.now - last_in.created_at) / 3600.0).round(2)
masked = to.sub(/\d{4}(\d{2})$/) { "****#{$1}" }
puts "ALVO: contato=#{contact.name.inspect} tel=#{masked} | ultima incoming ha #{age_h}h (wamid presente=#{last_in.source_id.present?})"
puts "AVISO: janela de 24h possivelmente FECHADA (#{age_h}h) — carrossel deve falhar com 131047" if age_h > 24

# --- (a) typing indicator + mark-as-read ---
if last_in.source_id.present?
  code, body = graph_post(phone_number_id, api_key,
                          { messaging_product: 'whatsapp', status: 'read',
                            message_id: last_in.source_id, typing_indicator: { type: 'text' } })
  puts "TYPING_INDICATOR: HTTP #{code} => #{body[0, 300]}"
  sleep 4
else
  puts "TYPING_INDICATOR: pulado (sem wamid na ultima incoming)"
end

# --- (b) carrossel de midia interativo: 3 cards + quick replies ---
imgs = [
  'https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=800&q=80&fm=jpg',
  'https://images.unsplash.com/photo-1570129477492-45c003edd2be?w=800&q=80&fm=jpg',
  'https://images.unsplash.com/photo-1583608205776-bfd35f0d9f83?w=800&q=80&fm=jpg'
]
textos = [
  "*Casa teste 1 — Jardim Botanico*\nR$ 2.500/mes - 3 quartos",
  "*Casa teste 2 — Menino Jesus*\nR$ 3.200/mes - 2 suites",
  "*Apto teste 3 — Centro*\nR$ 1.800/mes - 2 quartos"
]
cards = imgs.each_with_index.map do |img, i|
  {
    card_index: i,
    type: 'cta_url',
    header: { type: 'image', image: { link: img } },
    body: { text: textos[i] },
    action: {
      buttons: [
        { type: 'quick_reply', quick_reply: { id: "smoke-interesse-#{i + 1}", title: 'Tenho interesse' } },
        { type: 'quick_reply', quick_reply: { id: "smoke-fotos-#{i + 1}", title: 'Ver mais fotos' } }
      ]
    }
  }
end
payload = {
  messaging_product: 'whatsapp', recipient_type: 'individual', to: to,
  type: 'interactive',
  interactive: {
    type: 'carousel',
    body: { text: 'Smoke-test SPX: carrossel de imoveis (3 cards). Desliza pro lado e toca num botao.' },
    action: { cards: cards }
  }
}
code, body = graph_post(phone_number_id, api_key, payload)
puts "CARROSSEL: HTTP #{code} => #{body[0, 600]}"
puts code == 200 ? "RESULTADO: ACEITO pela API — confira a renderizacao no celular" : "RESULTADO: REJEITADO — analisar erro acima"
