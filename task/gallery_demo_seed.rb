# frozen_string_literal: true

# Seed de teste para a GALERIA de mídias. Cria conversas com mensagens OUTGOING
# carregando imagens reais (anexos Active Storage). Outgoing é obrigatório:
# o GalleryScopeBuilder esconde mídia INCOMING de canais WhatsApp/Api, e todas
# as inboxes da conta #1 são Channel::Api.
# Idempotente: marca com additional_attributes['seed']='gallery_demo'.
account = Account.order(:id).first
TAG = 'gallery_demo'
SEED_SQL = "additional_attributes->>'seed' = ?"

already = account.conversations.where(SEED_SQL, TAG).count
if already.positive?
  puts "Ja semeado (#{already} conversas gallery_demo). Para re-semear, rode o cleanup antes."
  exit 0
end

IMG_DIR = '/tmp/gallery_demo'
images = Dir.glob(File.join(IMG_DIR, '*.jpg')).sort
abort "Sem imagens em #{IMG_DIR} (gere com o passo de ImageMagick)." if images.empty?

admin = account.account_users.where(role: :administrator).first.user
inbox = account.inboxes.where(name: 'Site / Widget').first || account.inboxes.order(:id).first
now = Time.current

# 3 conversas; distribui as imagens entre elas.
CONVS = [
  { name: 'Galeria Cliente A (teste)', phone: '+5592710000001', n: 3 },
  { name: 'Galeria Cliente B (teste)', phone: '+5592710000002', n: 3 },
  { name: 'Galeria Cliente C (teste)', phone: '+5592710000003', n: 2 }
]

img_i = 0
total_att = 0
CONVS.each_with_index do |spec, ci|
  contact = account.contacts.create!(name: spec[:name], phone_number: spec[:phone],
                                     additional_attributes: { 'seed' => TAG })
  cinbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  conv = account.conversations.create!(
    inbox: inbox, contact: contact, contact_inbox: cinbox, assignee: admin,
    status: :open, additional_attributes: { 'seed' => TAG },
    created_at: now - (ci + 1).hours, updated_at: now - (ci + 1).hours
  )

  spec[:n].times do |k|
    path = images[img_i % images.size]
    img_i += 1
    msg = conv.messages.create!(
      account: account, inbox: inbox, message_type: :outgoing,
      content: "Imagem de teste #{img_i} — #{File.basename(path)}",
      sender: admin, created_at: conv.created_at + (k * 120)
    )
    att = msg.attachments.new(account_id: account.id, file_type: :image)
    att.file.attach(io: File.open(path), filename: File.basename(path), content_type: 'image/jpeg')
    att.save!
    total_att += 1
  end
end

puts '== Seed galeria concluido =='
puts "Conversas gallery_demo: #{account.conversations.where(SEED_SQL, TAG).count}"
puts "Anexos imagem criados:  #{total_att} (outgoing, inbox '#{inbox.name}')"
