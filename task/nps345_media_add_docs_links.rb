# frozen_string_literal: true

# Complemento do seed de QA da secao "Midia, links e docs": adiciona 9 DOCUMENTOS
# e 9 LINKS na conversa da contato "NPS Sim invalid2", para que as abas Docs e
# Links fiquem tao populadas quanto a aba Midia.
#
# Docs sao de formatos VARIADOS de proposito (5 PDF, 2 TXT, 1 CSV, 1 audio), para
# exercitar icone/label por tipo e o player inline de audio — 9 PDFs iguais nao
# testariam nada disso. O audio entra como file_type :audio, que a aba Docs do
# painel tambem lista.
#
# Links sao 9 URLs distintas e numeradas: a aba Links le as URLs do CONTEUDO das
# mensagens em memoria (o backend nunca devolve anexo do tipo embed).
#
# OUTGOING obrigatorio: o GalleryScopeBuilder esconde midia INCOMING de canais
# WhatsApp/Api, e essa inbox e Channel::Api.
#
# Idempotente: reusa a marca content_attributes['seed']='nps345_media', entao
# task/nps345_media_cleanup.rb limpa tudo junto.

TAG = 'nps345_media'
ASSET_DIR = ENV.fetch('NPS345_ASSETS', '/tmp/nps345_assets')

conv = Conversation.joins(:contact).find_by(contacts: { name: 'NPS Sim invalid2' })
abort 'Conversa de "NPS Sim invalid2" nao encontrada.' if conv.nil?

account = conv.account
admin = account.account_users.where(role: :administrator).first.user

DOCS = [
  ['doc-1.pdf',        'application/pdf', :file,  'Proposta comercial 1'],
  ['doc-2.pdf',        'application/pdf', :file,  'Contrato revisado 2'],
  ['doc-3.pdf',        'application/pdf', :file,  'Aditivo 3'],
  ['doc-4.pdf',        'application/pdf', :file,  'Nota fiscal 4'],
  ['doc-5.pdf',        'application/pdf', :file,  'Recibo 5'],
  ['relatorio-1.txt',  'text/plain',      :file,  'Relatorio em texto 6'],
  ['anotacoes-2.txt',  'text/plain',      :file,  'Anotacoes 7'],
  ['planilha-3.csv',   'text/csv',        :file,  'Planilha de valores 8'],
  ['audio-9.wav',      'audio/wav',       :audio, 'Audio explicativo 9']
].freeze

LINKS = [
  'https://www.chatspx.com.br/planos',
  'https://www.chatspx.com.br/integracoes',
  'https://docs.chatspx.com.br/primeiros-passos',
  'https://docs.chatspx.com.br/api/webhooks',
  'https://status.chatspx.com.br',
  'https://blog.chatspx.com.br/atendimento-no-whatsapp',
  'https://www.chatspx.com.br/contato',
  'https://github.com/chatwoot/chatwoot',
  'https://www.chatspx.com.br/termos-de-uso'
].freeze

DOCS.each { |f, _, _, _| abort "Asset ausente: #{File.join(ASSET_DIR, f)}" unless File.exist?(File.join(ASSET_DIR, f)) }

if conv.messages.exists?(['content LIKE ?', 'Documento de teste %'])
  puts "Docs/links ja semeados na conversa ##{conv.display_id}."
  puts 'Rode task/nps345_media_cleanup.rb antes de re-semear.'
  exit 0
end

# Escalonado a partir de 2 min atras: doc-1 mais antigo ... link 9 mais recente.
base = 2.minutes.ago
created = []

DOCS.each_with_index do |(fname, ctype, ftype, label), idx|
  msg = conv.messages.create!(
    account: account, inbox: conv.inbox, message_type: :outgoing,
    content: "Documento de teste #{idx + 1} de 9 — #{label}",
    sender: admin, content_attributes: { 'seed' => TAG },
    created_at: base + (idx * 5)
  )
  att = msg.attachments.new(account_id: account.id, file_type: ftype)
  att.file.attach(io: File.open(File.join(ASSET_DIR, fname)), filename: fname, content_type: ctype)
  att.save!
  created << [msg.id, "doc #{idx + 1}: #{fname} (#{ftype})"]
end

LINKS.each_with_index do |url, idx|
  msg = conv.messages.create!(
    account: account, inbox: conv.inbox, message_type: :outgoing,
    content: "Link de teste #{idx + 1} de 9: #{url}",
    sender: admin, content_attributes: { 'seed' => TAG },
    created_at: base + 60 + (idx * 5)
  )
  created << [msg.id, "link #{idx + 1}: #{url}"]
end

puts "== #{created.size} itens adicionados na conversa ##{conv.display_id} (id=#{conv.id}) =="
created.each { |id, what| puts "  msg ##{id} -> #{what}" }
