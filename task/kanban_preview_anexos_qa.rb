# QA VISUAL da pré-visualização do Kanban: prova que áudio, imagem e arquivo APARECEM de verdade
# (player/miniatura/chip), e não como o texto genérico "Anexo".
#
# Monta UMA conversa no funil Geral (12) com um exemplar de cada caso que o modal precisa tratar:
#
#   1) audio  + sem texto      -> player de áudio (chips/Audio.vue)
#   2) image  + legenda        -> miniatura + a legenda embaixo
#   3) file   (pdf)            -> chip de arquivo com nome + download (chips/File.vue)
#   4) audio  + texto          -> player E texto na MESMA bolha (o caso que o `v-else-if` antigo comia)
#   5) attachment SEM data_url -> rótulo "Anexo" (degradação; nunca bolha vazia)
#   6) sem texto e sem anexo   -> "sem conteúdo para exibir" (nunca bolha vazia)
#
# O caso 5 é o que o dono descreveu como "não aparece o áudio nem o arquivo": mídia que o
# reconciliador da WAHA pulou (job é TEXT-ONLY) chega sem attachment utilizável.
#
# Usa um admin de teste descartável — ninguém tem a senha do dono e resetar a de um agente REAL
# o trancaria fora do staging (mesma decisão de task/sino_teste_visual.rb).
#
# Uso:  RAILS_ENV=production rails runner task/kanban_preview_anexos_qa.rb
#       RAILS_ENV=production rails runner task/kanban_preview_anexos_qa.rb -- --limpar
#
# Só toca no que tem additional_attributes.seed = TAG e no usuário com e-mail começando em TAG.

$stdout.sync = true

TAG = 'kanban_preview_anexos_qa'.freeze
BASE_URL = 'https://nicolas.chatspx.app'.freeze
ADMIN_EMAIL = "#{TAG}_admin@example.com".freeze
SENHA = 'Test@12345678'.freeze
FUNNEL_ID = 12
LIMPAR = ARGV.include?('--limpar')

account = Account.find(1)
inbox = Inbox.find(2) # WhatsApp Vendas (Channel::Api)

# ── limpeza ────────────────────────────────────────────────────────────────
if LIMPAR
  convs = Conversation.where(account_id: account.id)
                      .where("additional_attributes->>'seed' = ?", TAG)
  # Duas armadilhas aqui: (1) `c.messages.delete_all` NULIFICA a FK (has_many sem :dependent) e
  # messages.conversation_id é NOT NULL; (2) várias tabelas apontam para conversations e cada uma
  # barra o DELETE com FK. Então varre o catálogo do PG em vez de listar tabela por tabela.
  child_tables = ActiveRecord::Base.connection.execute(<<-SQL.squish).to_a
    SELECT tc.table_name, kcu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND ccu.table_name = 'conversations' AND ccu.column_name = 'id'
  SQL

  convs.each do |c|
    Message.where(conversation_id: c.id).each { |m| m.attachments.each(&:destroy) }
    child_tables.each do |row|
      ActiveRecord::Base.connection.execute(
        "DELETE FROM #{row['table_name']} WHERE #{row['column_name']} = #{c.id.to_i}"
      )
    end
    Notification.where(primary_actor_type: 'Conversation', primary_actor_id: c.id).delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM conversations WHERE id = #{c.id.to_i}")
  end
  Contact.where(account_id: account.id)
         .where("additional_attributes->>'seed' = ?", TAG)
         .each(&:destroy)
  # Idem para users: carimbos de auditoria (ex.: funnel_items.moved_by_id) seguram o DELETE.
  # Onde a coluna aceita NULL, nulifica (o carimbo aponta para um usuário descartável, então
  # perde o sentido junto com ele); onde é NOT NULL, apaga a linha filha.
  user_fks = ActiveRecord::Base.connection.execute(<<-SQL.squish).to_a
    SELECT tc.table_name, kcu.column_name, c.is_nullable
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    JOIN information_schema.columns c
      ON c.table_name = tc.table_name AND c.column_name = kcu.column_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND ccu.table_name = 'users' AND ccu.column_name = 'id'
  SQL

  User.where('email LIKE ?', "#{TAG}%").each do |u|
    user_fks.each do |row|
      table = row['table_name']
      col = row['column_name']
      sql = if row['is_nullable'] == 'YES'
              "UPDATE #{table} SET #{col} = NULL WHERE #{col} = #{u.id.to_i}"
            else
              "DELETE FROM #{table} WHERE #{col} = #{u.id.to_i}"
            end
      ActiveRecord::Base.connection.execute(sql)
    end
    ActiveRecord::Base.connection.execute("DELETE FROM users WHERE id = #{u.id.to_i}")
  end
  puts "Limpo: cenário #{TAG} removido."
  exit 0
end

# ── admin de teste ─────────────────────────────────────────────────────────
admin = User.from_email(ADMIN_EMAIL)
if admin.nil?
  admin = User.create!(name: 'QA Preview Anexos', email: ADMIN_EMAIL,
                       password: SENHA, confirmed_at: Time.current)
end
unless AccountUser.exists?(account_id: account.id, user_id: admin.id)
  AccountUser.create!(account_id: account.id, user_id: admin.id, role: :administrator)
end

# ── contato + conversa ─────────────────────────────────────────────────────
contact = Contact.find_or_create_by!(account_id: account.id, email: "#{TAG}@example.com") do |c|
  c.name = 'Cliente QA Anexos'
  c.additional_attributes = { 'seed' => TAG }
end
contact.update!(additional_attributes: (contact.additional_attributes || {}).merge('seed' => TAG))

ci = ContactInbox.find_or_create_by!(contact_id: contact.id, inbox_id: inbox.id) do |x|
  x.source_id = "#{TAG}-#{SecureRandom.hex(4)}"
end

conv = Conversation.where(account_id: account.id)
                   .where("additional_attributes->>'seed' = ?", TAG).first
if conv.nil?
  conv = Conversation.create!(account_id: account.id, inbox_id: inbox.id,
                              contact_id: contact.id, contact_inbox_id: ci.id,
                              assignee_id: admin.id, status: :open,
                              additional_attributes: { 'seed' => TAG })
else
  conv.messages.each { |m| m.attachments.each(&:destroy) }
  conv.messages.delete_all
  conv.update!(assignee_id: admin.id)
end

# ── fixtures reais do repo (nada de baixar da internet) ────────────────────
def anexar!(message, file_type, path, filename)
  att = message.attachments.new(account_id: message.account_id, file_type: file_type)
  att.file.attach(io: File.open(path), filename: filename)
  att.save!
  att
end

AUDIO = Rails.root.join('spec/assets/sample.mp3')
IMAGE = Rails.root.join('spec/assets/avatar.png')
PDF   = Rails.root.join('spec/assets/sample.pdf')
[AUDIO, IMAGE, PDF].each { |p| raise "fixture ausente: #{p}" unless File.exist?(p) }

def msg!(conv, content, incoming: true)
  Message.create!(
    account_id: conv.account_id, inbox_id: conv.inbox_id, conversation_id: conv.id,
    message_type: incoming ? :incoming : :outgoing, content: content,
    content_attributes: {}, sender: incoming ? conv.contact : nil
  )
end

# 1) áudio sem texto -> só o player
anexar!(msg!(conv, nil), :audio, AUDIO, 'recado.mp3')

# 2) imagem com legenda -> miniatura + legenda
anexar!(msg!(conv, 'Segue a foto do produto'), :image, IMAGE, 'produto.png')

# 3) arquivo (pdf) -> chip com nome + download
anexar!(msg!(conv, nil), :file, PDF, 'orcamento.pdf')

# 4) áudio COM texto, saindo -> player E texto juntos na mesma bolha
anexar!(msg!(conv, 'Ouve esse áudio que eu gravei', incoming: false), :audio, AUDIO, 'resposta.mp3')

# 5) anexo sem arquivo/URL (mídia que a WAHA pulou) -> rótulo "Anexo"
bare = msg!(conv, nil)
Attachment.create!(account_id: conv.account_id, message_id: bare.id, file_type: :file)

# 5b) MÍDIA sem data_url: file_type diz "audio"/"image", mas não há arquivo nem external_url.
# Sem checar a URL isso vira player morto / imagem em branco (parece mídia QUEBRADA, e não
# mídia que nunca chegou). Tem que cair no rótulo "Anexo" igual ao caso 5.
%i[audio image video].each do |ft|
  m = msg!(conv, nil)
  Attachment.create!(account_id: conv.account_id, message_id: m.id, file_type: ft)
end

# 6) mensagem sem texto e sem anexo -> "sem conteúdo para exibir"
msg!(conv, nil)

# ── põe o cartão no Kanban ─────────────────────────────────────────────────
funnel = Funnel.find(FUNNEL_ID)
stage = funnel.funnel_stages.order(:position).first
item = FunnelItem.find_or_initialize_by(conversation_id: conv.id, funnel_id: funnel.id)
item.funnel_stage_id = stage.id
item.moved_at = Time.current
item.save!

puts '─' * 72
puts "Conversa QA: ##{conv.display_id} (id #{conv.id})  contato: #{contact.name}"
puts "Mensagens: #{conv.messages.count} | anexos: #{Attachment.where(message_id: conv.messages.select(:id)).count}"
conv.messages.order(:id).each do |m|
  a = m.attachments.map { |x| "#{x.file_type}#{x.file.attached? ? '' : '(sem arquivo)'}" }.join(',')
  puts "  msg #{m.id} #{m.message_type.to_s.ljust(8)} content=#{m.content.inspect.ljust(32)} anexos=[#{a}]"
end
puts "Funil: #{funnel.name} (#{funnel.id}) / coluna: #{stage.name}"
puts
puts "Login QA: #{ADMIN_EMAIL} / #{SENHA}"
puts "Kanban:   #{BASE_URL}/app/accounts/#{account.id}/kanban"
puts '─' * 72
