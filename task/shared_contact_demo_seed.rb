# frozen_string_literal: true

# Seed de teste para o CARD RICO DE CONTATO COMPARTILHADO ([[shared-contact-rich-card-feature]]).
# Cria 1 conversa com mensagens INCOMING, cada uma carregando anexos :contact
# gerados pelo caminho REAL (Vcard::ContactAttachmentService -> Vcard::ParserService)
# a partir de vCards de exemplo em vários formatos. Permite validar o render do
# card sem depender de um WAHA real.
# Idempotente: marca com additional_attributes['seed']='shared_contact_demo'.
account = Account.order(:id).first
TAG = 'shared_contact_demo'
SEED_SQL = "additional_attributes->>'seed' = ?"

already = account.conversations.where(SEED_SQL, TAG).count
if already.positive?
  puts "Ja semeado (#{already} conversa shared_contact_demo). Rode o cleanup antes para re-semear."
  exit 0
end

# Simula o ActionDispatch::Http::UploadedFile que o controller publico recebe,
# para exercitar o service exatamente como em produção.
FakeUpload = Struct.new(:content_type, :original_filename, :tempfile) do
  def read = tempfile.read
  def rewind = tempfile.rewind
end

def upload(text, content_type:, filename:)
  FakeUpload.new(content_type, filename, StringIO.new(text))
end

# Cenarios cobrindo os formatos suportados.
VCARDS = [
  {
    label: 'Contato simples com foto (vCard 3.0)',
    content_type: 'text/vcard', filename: 'contato-1.vcf',
    vcf: <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      N:Almeida;Carlos;;;
      FN:Carlos Almeida
      TEL;TYPE=CELL:+5592991110001
      PHOTO;VALUE=URI:https://i.pravatar.cc/150?img=12
      END:VCARD
    VCF
  },
  {
    label: 'Contato com empresa e foto (ORG)',
    content_type: 'text/x-vcard', filename: 'contato-2.vcf',
    vcf: <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      N:Souza;Mariana;;;
      FN:Mariana Souza
      ORG:Tozi Advogados;Civel
      TEL;TYPE=CELL:+5592991110002
      EMAIL:mariana@tozi.adv.br
      PHOTO;VALUE=URI:https://i.pravatar.cc/150?img=47
      END:VCARD
    VCF
  },
  {
    label: 'vCard 2.1 com acentos e foto (QUOTED-PRINTABLE), octet-stream',
    content_type: 'application/octet-stream', filename: 'contato-3.vcf',
    vcf: "BEGIN:VCARD\r\nVERSION:2.1\r\nFN;ENCODING=QUOTED-PRINTABLE:Jo=C3=A3o Concei=C3=A7=C3=A3o\r\nTEL;CELL:+5592991110003\r\nPHOTO;VALUE=URI:https://i.pravatar.cc/150?img=33\r\nEND:VCARD\r\n"
  },
  {
    label: 'Um .vcf com DOIS contatos (1 card por contato)',
    content_type: 'text/vcard', filename: 'contatos-4.vcf',
    vcf: <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:Equipe Comercial
      TEL:+5592991110004
      END:VCARD
      BEGIN:VCARD
      VERSION:3.0
      FN:Equipe Suporte
      ORG:ChatSPX
      TEL:+5592991110005
      END:VCARD
    VCF
  },
  {
    label: 'Contato so com telefone (sem nome) -> avatar usa inicial do numero',
    content_type: 'text/vcard', filename: 'contato-5.vcf',
    vcf: "BEGIN:VCARD\nVERSION:3.0\nTEL:+5592991110006\nEND:VCARD"
  }
].freeze

inbox = account.inboxes.where(name: 'Site / Widget').first || account.inboxes.order(:id).first
admin = account.account_users.where(role: :administrator).first.user
now = Time.current

contact = account.contacts.create!(name: 'Contatos Compartilhados (teste)', phone_number: '+5592991110000',
                                   additional_attributes: { 'seed' => TAG })
cinbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conv = account.conversations.create!(
  inbox: inbox, contact: contact, contact_inbox: cinbox, assignee: admin,
  status: :open, additional_attributes: { 'seed' => TAG },
  created_at: now - 1.hour, updated_at: now
)

total_cards = 0
VCARDS.each_with_index do |spec, i|
  msg = conv.messages.create!(
    account: account, inbox: inbox, message_type: :incoming,
    content: spec[:label], sender: contact,
    created_at: conv.created_at + (i * 60)
  )
  handled = Vcard::ContactAttachmentService.new(
    message: msg,
    uploaded_file: upload(spec[:vcf], content_type: spec[:content_type], filename: spec[:filename])
  ).build
  abort "ERRO: vCard nao reconhecido no cenario '#{spec[:label]}'" unless handled
  msg.save!
  cards = msg.attachments.where(file_type: :contact).count
  total_cards += cards
  puts "  [#{i + 1}] #{spec[:label]} -> #{cards} card(s)"
end

puts '== Seed contato compartilhado concluido =='
puts "Conversa: '#{conv.contact.name}' (id #{conv.display_id}), inbox '#{inbox.name}'"
puts "Mensagens incoming: #{VCARDS.size} | cards de contato: #{total_cards}"
