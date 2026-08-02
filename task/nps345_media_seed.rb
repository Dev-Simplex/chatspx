# frozen_string_literal: true

# Seed de QA para a secao "Midia, links e docs" (faixa compacta + painel com abas).
# Injeta na conversa da contato "NPS Sim invalid2" um exemplar de cada tipo que a
# secao sabe exibir: IMAGEM (aba Midia), PDF (aba Docs) e LINK (aba Links).
#
# As mensagens sao OUTGOING de proposito: o GalleryScopeBuilder esconde midia
# INCOMING de canais WhatsApp/Api, e a inbox dessa conversa e Channel::Api —
# incoming simplesmente nao apareceria.
#
# Idempotente: marca cada mensagem com content_attributes['seed']='nps345_media'.
# Limpeza: task/nps345_media_cleanup.rb

TAG = 'nps345_media'
ASSET_DIR = ENV.fetch('NPS345_ASSETS', '/tmp/nps345_assets')

conv = Conversation.joins(:contact).find_by(contacts: { name: 'NPS Sim invalid2' })
abort 'Conversa de "NPS Sim invalid2" nao encontrada.' if conv.nil?

account = conv.account
already = conv.messages.where("content_attributes->>'seed' = ?", TAG).count
if already.positive?
  puts "Ja semeado (#{already} mensagens #{TAG}) na conversa ##{conv.display_id}."
  puts 'Rode task/nps345_media_cleanup.rb antes de re-semear.'
  exit 0
end

admin = account.account_users.where(role: :administrator).first.user
base = 4.minutes.ago

img = File.join(ASSET_DIR, 'comprovante-teste.jpg')
pdf = File.join(ASSET_DIR, 'contrato-teste.pdf')
[img, pdf].each { |p| abort "Asset ausente: #{p}" unless File.exist?(p) }

created = []

# 1) IMAGEM -> alimenta a tira de miniaturas e a aba "Midia"
msg = conv.messages.create!(
  account: account, inbox: conv.inbox, message_type: :outgoing,
  content: 'Segue o comprovante que voce pediu.',
  sender: admin, content_attributes: { 'seed' => TAG }, created_at: base
)
att = msg.attachments.new(account_id: account.id, file_type: :image)
att.file.attach(io: File.open(img), filename: 'comprovante-teste.jpg', content_type: 'image/jpeg')
att.save!
created << [msg.id, 'imagem']

# 2) PDF -> aba "Docs"
msg = conv.messages.create!(
  account: account, inbox: conv.inbox, message_type: :outgoing,
  content: 'Contrato em anexo (2 paginas).',
  sender: admin, content_attributes: { 'seed' => TAG }, created_at: base + 60
)
att = msg.attachments.new(account_id: account.id, file_type: :file)
att.file.attach(io: File.open(pdf), filename: 'contrato-teste.pdf', content_type: 'application/pdf')
att.save!
created << [msg.id, 'pdf']

# 3) LINK -> aba "Links" (lida das URLs das mensagens em memoria, nao de anexo:
#    o backend nunca devolve anexo do tipo embed)
msg = conv.messages.create!(
  account: account, inbox: conv.inbox, message_type: :outgoing,
  content: 'Detalhes da politica no site: https://www.chatspx.com.br/politica-de-privacidade',
  sender: admin, content_attributes: { 'seed' => TAG }, created_at: base + 120
)
created << [msg.id, 'link']

puts "== Seed #{TAG} concluido na conversa ##{conv.display_id} (id=#{conv.id}) =="
created.each { |id, kind| puts "  msg ##{id} -> #{kind}" }
