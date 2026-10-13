# SUP-1415 — ensaio no staging: ficha antiga (Evolution) x ficha nova (WAHA) e a mesclagem.
#
# Reproduz, contra a API HTTP real do staging, as MESMAS chamadas que a WAHA Chatwoot App faz ao
# receber uma mensagem (código público: devlikeapro/waha, src/apps/chatwoot):
#   1. ContactService#search  -> POST /contacts/filter (waha_whatsapp_chat_id | identifier | jid | lid | phone)
#      candidatos = contatos com contact_inbox na caixa; prefere quem tem telefone
#   2. ConversationSelector   -> GET /contacts/:id/conversations, filtra a caixa, ordena por `sort`
#      (a Realizare usa created_newest + status null — lido em GET /api/apps?session=Realizare_adm)
#   3. grava a mensagem       -> POST /conversations/:id/messages (message_type incoming)
#
# Caixa própria SEM webhook (nada sai para o WhatsApp), conta 1, usuário de teste id 11, números fictícios.
#
#   MODO=montar  bundle exec rails runner task/sup1415_ensaio_qa.rb
#   MODO=ensaiar bundle exec rails runner task/sup1415_ensaio_qa.rb
#   MODO=limpar  bundle exec rails runner task/sup1415_ensaio_qa.rb
require 'net/http'
require 'json'

IDS_FILE = File.expand_path('~/qa-sup1415-ids.json')
ACCOUNT_ID = 1
USER_ID = 11
SHORT = '+556588661415'.freeze  # ficha antiga, 12 dígitos (formato Evolution)
LONG = '+5565988661415'.freeze  # ficha da WAHA, 13 dígitos
LID = '990000001415@lid'.freeze
JID = '556588661415@c.us'.freeze

def ids = JSON.parse(File.read(IDS_FILE))
def save_ids(h) = File.write(IDS_FILE, JSON.pretty_generate(h))

def api(method, path, body = nil)
  uri = URI("http://127.0.0.1:3000/api/v1/accounts/#{ACCOUNT_ID}#{path}")
  req = (method == :get ? Net::HTTP::Get : Net::HTTP::Post).new(uri)
  req['api_access_token'] = User.find(USER_ID).access_token.token
  req['Content-Type'] = 'application/json'
  req.body = body.to_json if body
  res = Net::HTTP.start(uri.host, uri.port) { |h| h.request(req) }
  raise "#{method} #{path} -> #{res.code} #{res.body[0, 200]}" unless res.code.start_with?('2')

  JSON.parse(res.body)
end

def clause(key, values) = { attribute_key: key, filter_operator: 'equal_to', values: values,
                            attribute_model: 'standard', custom_attribute_type: '', query_operator: 'OR' }

# Cópia fiel do ContactService#search + ConversationSelector da WAHA App.
def waha_inbound(content, sort)
  inbox_id = ids['inbox_id']
  chat_ids = [LID, JID].uniq
  payload = [clause('waha_whatsapp_chat_id', chat_ids), clause('identifier', chat_ids),
             clause('waha_whatsapp_jid', [JID]), clause('waha_whatsapp_lid', [LID]),
             clause('phone_number', [LONG, LONG.delete('+')])]
  payload.last.delete(:query_operator)
  contacts = api(:post, '/contacts/filter', { payload: payload })['payload']
  candidates = contacts.select { |c| Array(c['contact_inboxes']).any? { |ci| ci.dig('inbox', 'id') == inbox_id } }
  return { erro: 'nenhum contato achado (a App criaria uma ficha NOVA)' } if candidates.empty?

  contact = candidates.find { |c| c['phone_number'].present? } || candidates.first
  convs = api(:get, "/contacts/#{contact['id']}/conversations")['payload'].select { |c| c['inbox_id'] == inbox_id }
  field = sort == 'created_newest' ? 'created_at' : 'last_activity_at'
  conv = convs.max_by { |c| c[field].to_i }
  api(:post, "/conversations/#{conv['id']}/messages", { content: content, message_type: 'incoming' })
  { contato: "#{contact['id']} #{contact['name']}", conversa: conv['id'], achados_no_filtro: contacts.map { |c| c['id'] } }
end

def kamili_escreve(display_id, texto)
  conv = Conversation.find_by!(account_id: ACCOUNT_ID, display_id: display_id)
  conv.update!(status: :open)
  api(:post, "/conversations/#{display_id}/messages", { content: texto, message_type: 'outgoing' })
end

def montar
  abort "já montado: #{IDS_FILE}" if File.exist?(IDS_FILE)
  out = {}
  ActiveRecord::Base.transaction do
    channel = Channel::Api.create!(account_id: ACCOUNT_ID, webhook_url: '')
    inbox = Inbox.create!(account_id: ACCOUNT_ID, name: 'QA SUP-1415 – fichas partidas', channel: channel)
    member = InboxMember.create!(inbox: inbox, user_id: USER_ID)
    out.merge!('channel_api_id' => channel.id, 'inbox_id' => inbox.id, 'inbox_member_id' => member.id)

    antiga = Contact.create!(account_id: ACCOUNT_ID, name: 'QA Energisa (ficha antiga)', identifier: '556588661415@s.whatsapp.net',
                             custom_attributes: { 'whatsapp_number_exists' => true })
    antiga.update_column(:phone_number, SHORT) # rubocop:disable Rails/SkipsModelValidations -- o modelo normalizaria para 13 díg.
    nova = Contact.create!(account_id: ACCOUNT_ID, name: '556588661415', phone_number: LONG,
                           custom_attributes: { 'waha_whatsapp_chat_id' => LID, 'waha_whatsapp_lid' => LID, 'waha_whatsapp_jid' => JID })

    ci_a = ContactInbox.create!(contact: antiga, inbox: inbox, source_id: SecureRandom.uuid)
    ci_b = ContactInbox.create!(contact: nova, inbox: inbox, source_id: SecureRandom.uuid)
    conv_a = Conversation.create!(account_id: ACCOUNT_ID, inbox: inbox, contact: antiga, contact_inbox: ci_a)
    conv_b = Conversation.create!(account_id: ACCOUNT_ID, inbox: inbox, contact: nova, contact_inbox: ci_b)
    conv_a.update_columns(status: :resolved, created_at: Time.zone.parse('2025-11-10 16:31'), last_activity_at: Time.zone.parse('2025-11-10 16:31')) # rubocop:disable Rails/SkipsModelValidations
    conv_b.update_columns(status: :resolved, created_at: Time.zone.parse('2026-03-03 09:11'), last_activity_at: Time.zone.parse('2026-10-07 17:07')) # rubocop:disable Rails/SkipsModelValidations
    out.merge!('contato_antigo' => antiga.id, 'contato_novo' => nova.id, 'contact_inboxes' => [ci_a.id, ci_b.id],
               'conv_antiga' => conv_a.reload.display_id, 'conv_nova' => conv_b.reload.display_id)
  end
  save_ids(out)
  puts JSON.pretty_generate(out)
end

def ensaiar
  i = ids
  linha = ->(t, r) { puts format('%-58s -> %s', t, r) }
  puts "Kamili escreve na conversa ANTIGA ##{i['conv_antiga']} (reaberta), como em 07/10"
  kamili_escreve(i['conv_antiga'], 'Bom dia')

  puts "\n--- ANTES da mesclagem"
  linha.call('resposta com a config atual (created_newest)', waha_inbound('Ok! Vou te ajudar (antes, created)', 'created_newest'))
  linha.call('resposta com activity_newest', waha_inbound('Ok! Vou te ajudar (antes, activity)', 'activity_newest'))

  antiga = Contact.find(i['contato_antigo'])
  nova = Contact.find(i['contato_novo'])
  ContactMergeAction.new(account: Account.find(ACCOUNT_ID), base_contact: antiga, mergee_contact: nova).perform
  antiga.reload
  puts "\n--- MESCLADO (base = antiga #{antiga.id}, a #{i['contato_novo']} foi apagada)"
  puts "ficha mantida: #{antiga.name} | #{antiga.phone_number} | ident=#{antiga.identifier} | waha=#{antiga.custom_attributes.slice('waha_whatsapp_chat_id', 'waha_whatsapp_jid').to_json}"
  puts "fichas com esse número: #{Contact.where(account_id: ACCOUNT_ID, phone_number: [SHORT, LONG]).count}; conversas da ficha: #{antiga.conversations.pluck(:display_id).inspect}"

  kamili_escreve(i['conv_antiga'], 'Bom dia de novo')
  puts "\n--- DEPOIS da mesclagem (Kamili escreveu de novo na ##{i['conv_antiga']})"
  linha.call('resposta com a config atual (created_newest)', waha_inbound('Qual segunda via? (depois, created)', 'created_newest'))
  kamili_escreve(i['conv_antiga'], 'Simplificada')
  linha.call('resposta com activity_newest', waha_inbound('Certo! Já vou verificar (depois, activity)', 'activity_newest'))
  puts "\nmensagens recebidas por conversa: " +
       Message.where(inbox_id: i["inbox_id"], message_type: :incoming).reorder(nil).group(:conversation_id).count
              .transform_keys { |cid| "##{Conversation.find(cid).display_id}" }.inspect
end

# Varredura de FK (memória qa-seed-delete-fk-sweep): limpa tudo que aponta para as conversas do seed.
def limpar
  i = ids
  conv_ids = Conversation.where(inbox_id: i['inbox_id']).pluck(:id)
  fks = ActiveRecord::Base.connection.select_rows(<<~SQL)
    SELECT tc.table_name, kcu.column_name, c.is_nullable FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    JOIN information_schema.columns c ON c.table_name = tc.table_name AND c.column_name = kcu.column_name
    WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'conversations' AND ccu.column_name = 'id'
  SQL
  ActiveRecord::Base.transaction do
    Message.where(conversation_id: conv_ids).find_each { |m| m.attachments.destroy_all }
    Message.where(conversation_id: conv_ids).delete_all
    fks.each do |table, col, nullable|
      next if table == 'messages'

      sql = nullable == 'YES' ? "UPDATE #{table} SET #{col} = NULL" : "DELETE FROM #{table}"
      ActiveRecord::Base.connection.execute("#{sql} WHERE #{col} IN (#{conv_ids.join(',')})") if conv_ids.any?
    end
    Conversation.where(id: conv_ids).delete_all
    ContactInbox.where(inbox_id: i['inbox_id']).delete_all
    Contact.where(id: [i['contato_antigo'], i['contato_novo']]).destroy_all
    InboxMember.where(id: i['inbox_member_id']).delete_all
    Inbox.where(id: i['inbox_id']).destroy_all
    Channel::Api.where(id: i['channel_api_id']).delete_all
  end
  File.delete(IDS_FILE)
  puts "limpo: caixa #{i['inbox_id']}, contatos #{i['contato_antigo']}/#{i['contato_novo']}, conversas #{conv_ids.inspect}"
end

case ENV.fetch('MODO', nil)
when 'montar' then montar
when 'ensaiar' then ensaiar
when 'limpar' then limpar
else abort 'MODO=montar|ensaiar|limpar'
end
