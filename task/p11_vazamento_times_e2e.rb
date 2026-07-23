# E2E do P11: conversa de um time NÃO pode vazar pelos sub-recursos.
#
# O furo: `authorize_team_access` vivia só no ConversationsController, então a
# conversa dava 403 na porta da frente e 200 pela janela — a ConversationPolicy
# aprova por ACESSO À CAIXA, que o agente de fora tem.
#
# Este script monta o cenário REAL no staging e bate na API por HTTP (não chama
# controller na mão), provando que:
#   1) o agente de FORA do time leva 403 na conversa, nas mensagens, nas
#      etiquetas, nos participantes, ao ESCREVER e ao tentar tirar o time;
#   2) quem tem direito (membro do time, assignee, admin) continua com 200;
#   3) conversa SEM time segue aberta a quem tem a caixa (não apertamos demais).
#
# Uso:  RAILS_ENV=production rails runner task/p11_vazamento_times_e2e.rb
#       RAILS_ENV=production rails runner task/p11_vazamento_times_e2e.rb -- --limpar
#
# Cria e apaga o próprio cenário (tag p11_e2e). Não toca em dado real.

$stdout.sync = true

require 'net/http'
require 'json'

TAG = 'p11_e2e'.freeze
BASE = 'https://nicolas.chatspx.app'.freeze
SENHA = 'Test@12345678'.freeze
LIMPAR = ARGV.include?('--limpar')

account = Account.find(1)

def exec_sql(sql)
  ActiveRecord::Base.connection.execute(sql)
end

# Toda FK que aponta para `tabela`. Apagar seed na mão quebra em cascata (cada
# filho barra o DELETE, um por vez) — varrer o catálogo evita o whack-a-mole e
# não envelhece quando o schema muda.
def fks_para(tabela)
  exec_sql(<<-SQL.squish).to_a
    SELECT tc.table_name, kcu.column_name, c.is_nullable
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
    JOIN information_schema.columns c ON c.table_name = tc.table_name AND c.column_name = kcu.column_name
    WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = '#{tabela}' AND ccu.column_name = 'id'
  SQL
end

# Nullable → NULL (não levar linha REAL junto); NOT NULL → apagar a linha.
def soltar_filhos!(fks, id)
  fks.each do |r|
    exec_sql(
      if r['is_nullable'] == 'YES'
        "UPDATE #{r['table_name']} SET #{r['column_name']} = NULL WHERE #{r['column_name']} = #{id.to_i}"
      else
        "DELETE FROM #{r['table_name']} WHERE #{r['column_name']} = #{id.to_i}"
      end
    )
  end
end

def limpar_conversas!(account)
  fks = fks_para('conversations')
  Conversation.where(account_id: account.id)
              .where("additional_attributes->>'seed' = ?", TAG).each do |c|
    Message.where(conversation_id: c.id).each { |m| m.attachments.each(&:destroy) }
    # conversation_id é NOT NULL nos filhos: aqui é apagar, nunca nulificar
    fks.each { |r| exec_sql("DELETE FROM #{r['table_name']} WHERE #{r['column_name']} = #{c.id.to_i}") }
    exec_sql("DELETE FROM conversations WHERE id = #{c.id.to_i}")
  end
  Contact.where(account_id: account.id).where("additional_attributes->>'seed' = ?", TAG).each(&:destroy)
end

def limpar_times!(account)
  # Criar um Team dispara `create_default_funnel` E `sync_internal_team_channel`
  # (after_create no Team); cada filho segura o time por FK.
  fks = fks_para('teams')
  Team.where(account_id: account.id).where('name LIKE ?', "#{TAG}%").each do |t|
    Funnel.where(team_id: t.id).destroy_all # pelo modelo, p/ levar stages/itens junto
    soltar_filhos!(fks, t.id)
    exec_sql("DELETE FROM teams WHERE id = #{t.id.to_i}")
  end
end

def limpar_usuarios!
  fks = fks_para('users')
  User.where('email LIKE ?', "#{TAG}%").each do |u|
    soltar_filhos!(fks, u.id)
    exec_sql("DELETE FROM users WHERE id = #{u.id.to_i}")
  end
end

def limpar!(account)
  limpar_conversas!(account)
  limpar_times!(account)
  limpar_usuarios!
end

if LIMPAR
  limpar!(account)
  puts "Limpo: cenário #{TAG} removido."
  exit 0
end

limpar!(account) # idempotente

def cria_agente(account, sufixo, role: :agent)
  u = User.create!(name: "P11 #{sufixo}", email: "#{TAG}_#{sufixo}@example.com", password: SENHA, confirmed_at: Time.current)
  AccountUser.create!(account_id: account.id, user_id: u.id, role: role)
  u
end

inbox = Inbox.find(2)
time_a = Team.create!(account_id: account.id, name: "#{TAG}_time_A")

de_fora  = cria_agente(account, 'defora')   # tem a CAIXA, não é do time  <- o invasor
do_time  = cria_agente(account, 'dotime')   # é do time                   <- legítimo
assignee = cria_agente(account, 'assignee') # não é do time, mas é o dono <- legítimo
admin    = cria_agente(account, 'admin', role: :administrator)

[de_fora, do_time, assignee, admin].each do |u|
  InboxMember.find_or_create_by!(inbox_id: inbox.id, user_id: u.id)
end
TeamMember.create!(team_id: time_a.id, user_id: do_time.id)

contato = Contact.create!(account_id: account.id, name: 'Cliente P11', email: "#{TAG}@example.com",
                          additional_attributes: { 'seed' => TAG })
ci = ContactInbox.create!(contact_id: contato.id, inbox_id: inbox.id, source_id: "#{TAG}-#{SecureRandom.hex(4)}")

conv = Conversation.create!(account_id: account.id, inbox_id: inbox.id, contact_id: contato.id,
                            contact_inbox_id: ci.id, team_id: time_a.id, status: :open,
                            additional_attributes: { 'seed' => TAG })
Message.create!(account_id: account.id, inbox_id: inbox.id, conversation_id: conv.id,
                message_type: :incoming, content: 'SEGREDO DO TIME A', sender: contato)

# conversa SEM time: tem que continuar acessível a quem tem a caixa
conv_sem_time = Conversation.create!(account_id: account.id, inbox_id: inbox.id, contact_id: contato.id,
                                     contact_inbox_id: ci.id, team_id: nil, status: :open,
                                     additional_attributes: { 'seed' => TAG })

# assignee: atribuir sem passar pela validação que exige time
conv.update_columns(assignee_id: assignee.id) # rubocop:disable Rails/SkipsModelValidations

def token(user)
  user.create_new_auth_token
end

def http(metodo, caminho, user, corpo = nil)
  uri = URI("#{BASE}#{caminho}")
  req = case metodo
        when :get then Net::HTTP::Get.new(uri)
        when :post then Net::HTTP::Post.new(uri)
        end
  token(user).each { |k, v| req[k] = v }
  req['Content-Type'] = 'application/json'
  req.body = corpo.to_json if corpo
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
  [res.code.to_i, res.body.to_s]
end

# Sem `.freeze`: o `<<` abaixo precisa mutar. Congelar faria o script estourar
# justamente quando achasse um vazamento — o pior momento para quebrar.
FALHAS = [] # rubocop:disable Style/MutableConstant

def checa(nome, esperado, obtido, corpo: nil, nao_pode_conter: nil)
  ok = obtido == esperado
  ok &&= corpo.to_s.exclude?(nao_pode_conter) if nao_pode_conter && ok
  puts(format('  %<nome>-58s %<res>s (%<code>s)', nome: nome, res: ok ? 'PASS' : 'FALHOU', code: obtido))
  FALHAS << nome unless ok
end

base = "/api/v1/accounts/#{account.id}/conversations/#{conv.display_id}"

puts "\n=== 1) AGENTE DE FORA DO TIME (tem a caixa) — tudo deve dar 403 ==="
code, = http(:get, base, de_fora)
checa('GET conversa', 403, code)
code, body = http(:get, "#{base}/messages", de_fora)
checa('GET mensagens (o vazamento P11)', 403, code, corpo: body, nao_pode_conter: 'SEGREDO DO TIME A')
code, = http(:get, "#{base}/labels", de_fora)
checa('GET etiquetas', 403, code)
code, = http(:get, "#{base}/participants", de_fora)
checa('GET participantes', 403, code)
code, = http(:post, "#{base}/messages", de_fora, { content: 'invadindo' })
checa('POST mensagem (escrita)', 403, code)
code, = http(:post, "#{base}/assignments", de_fora, { team_id: 0 })
checa('POST tirar o time (escalada)', 403, code)

puts "\n=== 2) QUEM TEM DIREITO — deve continuar 200 ==="
code, body = http(:get, "#{base}/messages", do_time)
checa('membro do time lê mensagens', 200, code)
puts "     (conteúdo chegou: #{body.include?('SEGREDO DO TIME A')})"
code, = http(:get, "#{base}/messages", assignee)
checa('assignee (fora do time) lê mensagens', 200, code)
code, = http(:get, "#{base}/messages", admin)
checa('admin lê mensagens', 200, code)
code, = http(:get, "/api/v1/accounts/#{account.id}/conversations/#{conv_sem_time.display_id}/messages", de_fora)
checa('conversa SEM time segue aberta pela caixa', 200, code)

puts "\n#{'=' * 62}"
if FALHAS.empty?
  puts 'RESULTADO: ALL GREEN — o furo fechou e ninguém legítimo foi trancado.'
else
  puts "RESULTADO: #{FALHAS.size} FALHA(S): #{FALHAS.join(' | ')}"
end
puts "Conversa #{conv.display_id} (time #{time_a.name}) · limpar: rails runner #{$PROGRAM_NAME} -- --limpar"
