# Dado de QA da linha do tempo do rodízio (tela Relatórios → Rodízio, faixa do consultor).
#
#   bundle exec rails runner scripts/spx/tozi/seed_rodizio_qa.rb
#   bundle exec rails runner scripts/spx/tozi/seed_rodizio_qa.rb limpar
#
# Por que existe: o motor da distribuição só roda na TOZI. Em qualquer outra máquina
# `distribuicao_logs` está vazia, a faixa abre sem nada e não dá para validar a tela. Isto planta
# os seis casos que a faixa precisa saber desenhar.
#
# Não cria conversa: usa as que já existem na conta e pendura designações nelas. Tudo o que planta
# leva `policy_snapshot->>'seed' = 'rodizio_qa'`, e o `limpar` apaga exatamente isso — inclusive os
# ReportingEvent que criou, pelo id guardado no próprio snapshot, para não encostar em evento real.
SEED = 'rodizio_qa'.freeze
LOG = Spx::Distribuicao::Log

# Minutos atrás de cada instante. `chegou` vira uma reabertura da conversa: sem ela a fase da IA
# contaria desde o nascimento da conversa (semanas atrás) e esmagaria a espera na barra.
CENARIOS = [
  { nota: 'pegou em 2 min e resolveu',
    motivo: 'rodizio', status: 'assumido', chegou: 80, designado: 76, encerrado: 74, resolvido: 4 },
  { nota: 'deixou o lead 38 min esperando',
    motivo: 'rodizio', status: 'assumido', chegou: 130, designado: 129, encerrado: 91, resolvido: 69 },
  { nota: 'não pegou: expirou em 45 min',
    motivo: 'rodizio', status: 'expirado', chegou: 51, designado: 48, encerrado: 3 },
  { nota: 'o repasse que recebeu o lead expirado',
    motivo: 'repasse_sla', status: 'designado', chegou: 51, designado: 3, conversa: 2, corretor: :outro },
  { nota: 'pegou e ainda está atendendo',
    motivo: 'rodizio', status: 'assumido', chegou: 40, designado: 38, encerrado: 26 },
  { nota: 'designado e parado, ninguém encostou',
    motivo: 'rodizio', status: 'designado', chegou: 27, designado: 26 },
  { nota: 'continuidade — NÃO pode aparecer na faixa',
    motivo: 'continuidade', status: 'assumido', chegou: 200, designado: 199, encerrado: 198 }
].freeze

def limpar
  plantados = LOG.where("policy_snapshot->>'seed' = ?", SEED)
  eventos = plantados.flat_map { |log| log.policy_snapshot['reporting_event_ids'] || [] }
  ReportingEvent.where(id: eventos).delete_all
  total = plantados.count
  plantados.delete_all
  puts "removidos: #{total} designações e #{eventos.size} eventos"
end

def evento(conversa, nome, inicio, fim)
  ReportingEvent.create!(account_id: conversa.account_id, name: nome, conversation_id: conversa.id,
                         inbox_id: conversa.inbox_id, event_start_time: inicio, event_end_time: fim,
                         value: (fim - inicio).round).id
end

def designar(conversa, corretor, cenario, agora)
  atras = ->(chave) { cenario[chave] && (agora - cenario[chave].minutes) }
  chegou = atras.call(:chegou)

  ids = [evento(conversa, 'conversation_opened', chegou, chegou)]
  ids << evento(conversa, 'conversation_resolved', chegou, atras.call(:resolvido)) if cenario[:resolvido]

  LOG.create!(account_id: conversa.account_id, conversation_id: conversa.id, chosen_user_id: corretor.id,
              motivo: cenario[:motivo], status: cenario[:status],
              designado_em: atras.call(:designado), encerrado_em: atras.call(:encerrado),
              candidatos: [corretor.id],
              policy_snapshot: { 'seed' => SEED, 'reporting_event_ids' => ids })
end

def plantar(conversas, corretor, outro)
  agora = Time.zone.now
  CENARIOS.each_with_index do |cenario, indice|
    conversa = conversas[cenario[:conversa] || indice]
    quem = cenario[:corretor] == :outro ? (outro || corretor) : corretor
    designar(conversa, quem, cenario, agora)
  end
end

def semear
  conta = Account.find(ENV.fetch('ACCOUNT_ID', Account.first.id))
  # Com `order`, e não só `limit`: sem ordem o Postgres devolve quem quiser e cada rodada
  # plantaria em outro consultor, o que torna a validação impossível de repetir.
  corretor, outro = conta.users.order(:id).limit(2).to_a
  conversas = conta.conversations.order(id: :desc).limit(CENARIOS.size).to_a
  raise 'conta sem atendente ou sem conversas suficientes' if corretor.nil? || conversas.size < CENARIOS.size

  plantar(conversas, corretor, outro)

  puts "conta #{conta.id} · consultor #{corretor.name} (id #{corretor.id})"
  puts "plantadas #{LOG.where("policy_snapshot->>'seed' = ?", SEED).count} designações"
  puts 'abra Relatórios → Rodízio e clique no nome do consultor'
end

ARGV.first == 'limpar' ? limpar : semear
