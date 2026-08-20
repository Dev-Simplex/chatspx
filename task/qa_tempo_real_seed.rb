# frozen_string_literal: true

# Cenário de QA do Kanban em TEMPO REAL (task/kanban-tempo-real.md).
#
# Por que um time/inbox/funil próprios em vez de usar um funil existente:
# a validação exige DOIS usuários diferentes com o MESMO board aberto (duas abas
# do mesmo usuário compartilham o pubsub_token e mascaram bug de alcance), e pela
# FunnelPolicy um agente só enxerga funil do time dele — os dois usuários de teste
# não estavam em time nenhum, ou seja, não viam funil nenhum.
#
# O que cria:
#   • time "QA Tempo Real" com Realtime Test A (#15), Realtime Test B (#16) e o admin
#   • inbox "QA Tempo Real" (Channel::Api, SEM auto-assign para não embaralhar os
#     responsáveis do seed)
#   • funil do time (criado automaticamente pelo Team) + a coluna "Aguardando cliente"
#   • 75 cartões de conversa + 3 cartões de tarefa, distribuídos de propósito:
#       Aberto ............. 45  → a página carrega 30, então 15 ficam FORA do store
#                                  (é o cenário do relato: "arrastei um card que o
#                                  outro nunca rolou até ver")
#       Em andamento ....... 12  → reordenar dentro da coluna
#       Aguardando cliente .. 8
#       Resolvido .......... 10  → o board NÃO carrega coluna resolved; arrastar um
#                                  card daqui para "Aberto" é o teste mais duro do
#                                  "card desconhecido entra desenhado"
#     com prioridade, responsável, etiqueta e idade variados, para dar o que filtrar.
#
# Idempotente: marca tudo com additional_attributes['seed']='qa_tempo_real'.
# Para limpar:  RAILS_ENV=production bundle exec rails runner task/qa_tempo_real_clean.rb
$stdout.sync = true

TAG = 'qa_tempo_real'
SEED_SQL = "additional_attributes->>'seed' = ?"

account = Account.find(1)
admin = account.account_users.where(role: :administrator).first.user
agent_a = User.from_email('rt-test-a@chatspx.test')
agent_b = User.from_email('rt-test-b@chatspx.test')
abort 'Usuários de teste (rt-test-a/b@chatspx.test) não encontrados' if agent_a.nil? || agent_b.nil?

ja = account.conversations.where(SEED_SQL, TAG).count
if ja.positive?
  puts "Já semeado (#{ja} conversas #{TAG}). Rode o clean antes de semear de novo."
  exit 0
end

# ── time ────────────────────────────────────────────────────────────────
# O Team normaliza o nome para minúsculas (before_validation), então a busca tem
# que ser pelo nome já minúsculo — senão o script recria o time a cada execução.
TEAM_NAME = 'qa tempo real'
team = account.teams.find_by(name: TEAM_NAME)
if team.nil?
  team = account.teams.create!(name: TEAM_NAME, description: 'Cenário de teste do Kanban em tempo real')
  puts "time ##{team.id} criado"
end
team.add_members([agent_a.id, agent_b.id, admin.id].uniq - team.members.pluck(:id))

# ── inbox ───────────────────────────────────────────────────────────────
inbox = account.inboxes.find_by(name: 'QA Tempo Real')
if inbox.nil?
  channel = Channel::Api.create!(account: account)
  inbox = account.inboxes.create!(
    name: 'QA Tempo Real', channel: channel,
    # auto-assign ligado embaralharia os responsáveis escolhidos abaixo
    enable_auto_assignment: false
  )
  puts "inbox ##{inbox.id} criada"
end
[agent_a, agent_b, admin].each { |u| InboxMember.find_or_create_by!(inbox: inbox, user: u) }

# ── funil (o Team já cria um; só completamos as colunas) ────────────────
funnel = Funnel.find_by(team_id: team.id, account_id: account.id)
abort 'Funil do time não foi criado' if funnel.nil?
funnel.update!(name: 'QA Tempo Real') if funnel.name != 'QA Tempo Real'

resolvido = funnel.funnel_stages.find_by(automation_type: 'resolved')
resolvido&.update!(position: 3)
unless funnel.funnel_stages.exists?(name: 'Aguardando cliente')
  FunnelStage.create!(funnel: funnel, name: 'Aguardando cliente', position: 2, color: '#f59e0b')
end

stages = funnel.funnel_stages.ordered.to_a
puts "funil ##{funnel.id} #{funnel.name.inspect} — colunas: #{stages.map { |s| "#{s.id}:#{s.name}" }.join(' | ')}"

aberto = stages[0]
andamento = stages[1]

# ── cartões ─────────────────────────────────────────────────────────────
PRIMEIROS_NOMES = %w[Ana Bruno Carla Diego Elisa Fábio Gabriela Heitor Isabela João Karina Lucas Marina
                     Natan Olívia Pedro Quésia Rafael Sofia Thiago Úrsula Vinícius Yara Zeca].freeze
SOBRENOMES = %w[Almeida Barbosa Cardoso Dias Esteves Ferreira Gomes Henrique Ibrahim Justino Klein
                Lopes Martins Nogueira Oliveira Prado Queiroz Ribeiro Souza Teixeira].freeze
ASSUNTOS = [
  'Bom dia! Meu boleto não chegou, podem reenviar?',
  'Quero um orçamento para 200 sacas de soja.',
  'Alguém pode me atender? Estou esperando desde ontem.',
  'A entrega está atrasada, qual a previsão?',
  'Preciso trocar o produto, veio errado.',
  'Podem refazer a simulação com entrada de 30%?',
  'Consegui resolver sozinho, obrigado!',
  'Qual o prazo de entrega para Sinop?',
  'O sistema não deixa eu finalizar o pedido.',
  'Gostaria de falar com o gerente, por favor.'
].freeze
PRIORIDADES = [nil, 'low', 'medium', 'high', 'urgent'].freeze
ETIQUETAS = [[], ['financeiro'], ['duvida'], ['reclamacao'], %w[financeiro duvida], ['agendamento']].freeze

DISTRIBUICAO = [[0, 45], [1, 12], [2, 8], [3, 10]].freeze # [índice da coluna, quantidade]

criados = 0
indice = 0
now = Time.current

DISTRIBUICAO.each do |stage_idx, quantidade| # rubocop:disable Metrics/BlockLength
  stage = stages[stage_idx]
  quantidade.times do # rubocop:disable Metrics/BlockLength
    indice += 1
    nome = "#{PRIMEIROS_NOMES[indice % PRIMEIROS_NOMES.size]} #{SOBRENOMES[indice % SOBRENOMES.size]} (QA RT)"
    telefone = format('+55669%08d', 71_000_000 + indice)

    contato = account.contacts.create!(name: nome, phone_number: telefone,
                                       additional_attributes: { 'seed' => TAG })
    ci = ContactInbox.create!(contact: contato, inbox: inbox, source_id: SecureRandom.uuid)

    # Idade espalhada: uns poucos minutos até ~20 dias, para exercitar os trilhos
    # de espera/envelhecimento do card (e dar o que ordenar).
    idade = case indice % 6
            when 0 then 4.minutes
            when 1 then 40.minutes
            when 2 then 3.hours
            when 3 then 1.day
            when 4 then 6.days
            else 19.days
            end
    quando = now - idade

    responsavel = [nil, agent_a, agent_b, admin][indice % 4]
    # `team` é obrigatório aqui por dois motivos: o funil é de time, e tanto o
    # `FunnelItemsQueryService` quanto o caminho legado filtram os cards por
    # `conversations.team_id = funnel.team_id` — sem isso o board nasce VAZIO.
    # Além disso, criar conversa já resolvida sem time bate na validação de
    # "encerramento por atribuição".
    conversa = account.conversations.create!(
      inbox: inbox, contact: contato, contact_inbox: ci,
      team: team,
      assignee: responsavel,
      status: stage.automation_type == 'resolved' ? :resolved : :open,
      priority: PRIORIDADES[indice % PRIORIDADES.size],
      additional_attributes: { 'seed' => TAG },
      created_at: quando, updated_at: quando
    )
    conversa.messages.create!(account: account, inbox: inbox, message_type: :incoming,
                              content: ASSUNTOS[indice % ASSUNTOS.size], sender: contato,
                              created_at: quando)
    etiquetas = ETIQUETAS[indice % ETIQUETAS.size]
    conversa.update_labels(etiquetas) if etiquetas.any?
    conversa.update_columns(last_activity_at: quando, waiting_since: quando) # rubocop:disable Rails/SkipsModelValidations

    # find_or_initialize, não create!: atribuir a conversa a um agente deste time
    # dispara a rotina que já coloca o card no funil do time, e um create! aqui
    # bateria na unicidade (conversation_id + funnel_id).
    card = FunnelItem.find_or_initialize_by(conversation: conversa, funnel: funnel)
    card.assign_attributes(funnel_stage: stage, moved_by: admin, moved_at: quando,
                           position: FunnelItem.top_position_for(stage.id, excluding_id: card.id))
    card.save!
    # O before_save :set_moved_at sobrescreve moved_at quando a etapa muda; aqui
    # queremos a idade artificial (ela alimenta o sinal de "tempo na etapa").
    card.update_columns(moved_at: quando) # rubocop:disable Rails/SkipsModelValidations
    criados += 1
    print "\rcartões criados: #{criados}"
  end
end
puts ''

# ── cartões de TAREFA (sem conversa) ────────────────────────────────────
TAREFAS = [
  ['[QA] Ligar para o cliente Ana', 'Retornar a ligação sobre o orçamento.', 0],
  ['[QA] Conferir boleto em aberto', 'Financeiro precisa confirmar a baixa.', 1],
  ['[QA] Revisar proposta comercial', nil, 1]
].freeze

TAREFAS.each_with_index do |(titulo, descricao, stage_idx), i|
  stage = [aberto, andamento][stage_idx]
  FunnelItem.create!(funnel: funnel, funnel_stage: stage, title: titulo, description: descricao,
                     assignee: [agent_a, agent_b, nil][i], moved_by: admin, moved_at: now,
                     position: FunnelItem.top_position_for(stage.id))
end
puts "#{TAREFAS.size} cartões de tarefa criados"

puts "\n== pronto =="
stages.each { |s| puts "  #{s.name}: #{funnel.funnel_items.where(funnel_stage_id: s.id).count} cartões" }
puts "\nboard: /app/accounts/#{account.id}/kanban/#{funnel.id}"
puts "\nLinks de login (5 min, uso único) — abra cada um numa janela/navegador diferente:"
[[agent_a, 'Realtime Test A'], [agent_b, 'Realtime Test B'], [admin, 'admin']].each do |user, rotulo|
  puts "  #{rotulo}: #{user.generate_sso_link}"
end
