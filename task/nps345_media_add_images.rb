# frozen_string_literal: true

# Complemento do seed de QA da secao "Midia, links e docs": adiciona 9 imagens
# NUMERADAS (foto-1..foto-9) na conversa da contato "NPS Sim invalid2".
#
# Serve para exercitar o que 2 anexos nao alcancam:
#   - o contador "+N" da 4a casinha da tira (so aparece a partir do 5o anexo)
#   - o "Ver mais" / paginacao da grade dentro do painel
#   - a ORDEM: cada imagem estampa seu numero, e o created_at e escalonado, entao
#     a mais recente (foto-9) tem que aparecer PRIMEIRO na tira.
#
# OUTGOING obrigatorio: o GalleryScopeBuilder esconde midia INCOMING de canais
# WhatsApp/Api, e essa inbox e Channel::Api.
#
# Idempotente: reusa a mesma marca content_attributes['seed']='nps345_media',
# entao task/nps345_media_cleanup.rb ja limpa estas junto das outras.

TAG = 'nps345_media'
ASSET_DIR = ENV.fetch('NPS345_ASSETS', '/tmp/nps345_assets')

conv = Conversation.joins(:contact).find_by(contacts: { name: 'NPS Sim invalid2' })
abort 'Conversa de "NPS Sim invalid2" nao encontrada.' if conv.nil?

account = conv.account
admin = account.account_users.where(role: :administrator).first.user

paths = (1..9).map { |i| File.join(ASSET_DIR, "foto-#{i}.jpg") }
paths.each { |p| abort "Asset ausente: #{p}" unless File.exist?(p) }

# Idempotencia: nao duplica se as fotos numeradas ja estiverem la.
existing = conv.messages.where('content LIKE ?', 'Foto de teste %').count
if existing.positive?
  puts "Ja existem #{existing} mensagens 'Foto de teste' na conversa ##{conv.display_id}."
  puts 'Rode task/nps345_media_cleanup.rb antes de re-semear.'
  exit 0
end

# Escalonado a partir de 3 min atras: foto-1 mais antiga ... foto-9 mais recente.
base = 3.minutes.ago
created = []

paths.each_with_index do |path, idx|
  n = idx + 1
  msg = conv.messages.create!(
    account: account, inbox: conv.inbox, message_type: :outgoing,
    content: "Foto de teste #{n} de 9",
    sender: admin, content_attributes: { 'seed' => TAG },
    created_at: base + (idx * 10)
  )
  att = msg.attachments.new(account_id: account.id, file_type: :image)
  att.file.attach(io: File.open(path), filename: "foto-#{n}.jpg", content_type: 'image/jpeg')
  att.save!
  created << [msg.id, n]
end

puts "== #{created.size} imagens adicionadas na conversa ##{conv.display_id} (id=#{conv.id}) =="
created.each { |id, n| puts "  msg ##{id} -> foto-#{n}.jpg" }
