# frozen_string_literal: true

# Adiciona UMA imagem de teste com FUNDO PRETO à galeria demo, como mensagem
# OUTGOING (incoming de Channel::Api fica oculto) anexada a uma conversa
# gallery_demo existente. Idempotente pelo filename do blob.
account = Account.order(:id).first
TAG = 'gallery_demo'
FILENAME = 'teste-galeria-9-Preto.jpg'
PATH = "/tmp/gallery_demo/#{FILENAME}"

abort "Imagem nao encontrada: #{PATH}" unless File.exist?(PATH)

conv = account.conversations.where("additional_attributes->>'seed' = ?", TAG).order(:id).first
abort 'Nenhuma conversa gallery_demo — rode task/gallery_demo_seed.rb antes.' unless conv

already = ActiveStorage::Blob
          .joins("JOIN active_storage_attachments asa ON asa.blob_id = active_storage_blobs.id AND asa.record_type = 'Attachment'")
          .exists?(filename: FILENAME)
if already
  puts "Imagem '#{FILENAME}' ja existe na galeria. Nada a fazer."
  exit 0
end

admin = account.account_users.where(role: :administrator).first.user
msg = conv.messages.create!(
  account: account, inbox: conv.inbox, message_type: :outgoing,
  content: "Imagem de teste #9 - fundo preto (#{FILENAME})",
  sender: admin, created_at: Time.current
)
att = msg.attachments.new(account_id: account.id, file_type: :image)
att.file.attach(io: File.open(PATH), filename: FILENAME, content_type: 'image/jpeg')
att.save!

# A galeria cacheia IDs por 5 min (user+filtro). Limpa p/ aparecer na hora.
begin
  Rails.cache.delete_matched('gallery_attachments*')
  Rails.cache.delete_matched('gallery_links*')
rescue StandardError => e
  puts "(cache nao limpo automaticamente: #{e.class} - aparece em ate 5 min)"
end

puts '== Imagem preta adicionada =='
puts "Conversa ##{conv.display_id} (#{conv.contact&.name}); anexo ##{att.id}; msg ##{msg.id}"
