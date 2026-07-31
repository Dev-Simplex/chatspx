# frozen_string_literal: true

# F3 · DRY-RUN — vê a escada de desfechos ANTES de existir migration.
#
#   rails runner /tmp/f3_dryrun.rb              # conta 6, 500 episódios
#   ACCOUNT=6 LIMIT=1000 rails runner /tmp/f3_dryrun.rb
#   rails runner /tmp/f3_dryrun.rb 6 1000       # posicional, se preferir
#
# SOMENTE LEITURA. Não grava, não migra, não instancia objeto pra salvar — todo
# acesso é por pluck. Pode rodar em produção sem alterar uma linha do banco.
#
# SELF-CONTAINED de propósito: replica a detecção do Captain::EpisodeOutcomeService
# sem depender de NADA que a árvore da box não tenha. Só usa o que existe desde
# 17/07 — captain_conversation_episodes, captain_tool_calls, funnel_items,
# messages, conversations. Não referencia captain_episode_outcomes nem as colunas
# de traço, que ainda vivem só na branch spx/eval.
#
# Se a distribuição vier torta aqui (zero qualificado, tudo em "sem degrau"), o
# modelo está errado e nenhuma migration deveria subir.

ACCOUNT_ID = (ENV['ACCOUNT'] || ARGV[0] || 6).to_i
LIMIT = (ENV['LIMIT'] || ARGV[1] || 500).to_i

# ── espelho das constantes do serviço ───────────────────────────────────────
TOOL_WINDOW = 3 * 60 # segundos
IA_SENDERS = %w[Captain::Assistant AgentBot].freeze
HANDOFF_TOOLS = %w[handoff transferir_para_agente].freeze
STATUS_DEGRAU = {
  'qualificado' => 'qualificado', 'convertido' => 'qualificado',
  'esfriado' => 'esfriou', 'perdido' => 'esfriou',
  'nao_qualificado' => 'descartado'
}.freeze
STAGE_DEGRAU = { 'qualificado' => 'qualificado', 'frio' => 'esfriou' }.freeze
DEGRAUS = %w[respondeu qualificado handoff assumido esfriou descartado].freeze
CONVERSAO = %w[qualificado handoff].freeze

MSG_INCOMING = 0
MSG_OUTGOING = 1

account = Account.find(ACCOUNT_ID)
tem_tool_calls = defined?(Captain::ToolCall) && Captain::ToolCall.table_exists?

puts '=' * 78
puts 'F3 · DRY-RUN — somente leitura, nada é gravado'
puts '=' * 78
puts "conta #{account.id} · #{account.name}"
puts "eval_enabled=#{account.custom_attributes&.dig('eval_enabled').inspect} " \
     "eval_unit=#{account.custom_attributes&.dig('eval_unit').inspect}"

episodios = Captain::ConversationEpisode
            .where(account_id: ACCOUNT_ID)
            .where.not(ended_at: nil)
            .order(ended_at: :desc)
            .limit(LIMIT)
            .to_a

total_fechados = Captain::ConversationEpisode.where(account_id: ACCOUNT_ID).where.not(ended_at: nil).count
puts "episódios fechados na conta: #{total_fechados} — analisando os #{episodios.size} mais recentes"
puts "tool_calls (F2) disponível: #{tem_tool_calls ? 'sim' : 'NÃO — autoria da IA vai sair subestimada'}"

if episodios.empty?
  puts "\nNenhum episódio fechado. Sem isso o F3 não tem o que ler."
  puts 'Conferir: eval_unit=episode na conta e o ConversationEvalSchedulerJob rodando.'
  exit
end

conv_ids = episodios.map(&:conversation_id).uniq

# ── carregamentos em lote (poucas queries, nenhuma escrita) ─────────────────
conversas = Conversation.where(id: conv_ids).pluck(:id, :custom_attributes).to_h

tool_calls = Hash.new { |h, k| h[k] = [] }
if tem_tool_calls
  Captain::ToolCall.where(conversation_id: conv_ids)
                   .pluck(:conversation_id, :tool_name, :args, :status, :created_at, :captain_assistant_id)
                   .each { |cid, nome, args, status, at, aid| tool_calls[cid] << { nome: nome, args: args || {}, status: status, at: at, aid: aid } }
end

funil = Hash.new { |h, k| h[k] = [] }
FunnelItem.joins(:funnel_stage)
          .where(conversation_id: conv_ids, funnel_stages: { automation_type: STAGE_DEGRAU.keys })
          .pluck(:conversation_id, :moved_at, :moved_by_id, Arel.sql('funnel_stages.automation_type'))
          .each { |cid, moved_at, by, tipo| funil[cid] << { at: moved_at, by: by, tipo: tipo } }

# ── detecção, episódio a episódio ──────────────────────────────────────────
resultados = []
sem_mensagem = 0
sem_tool_call = 0
ia_msg_ids = []

episodios.each do |ep|
  fim = ep.ended_at || ep.last_message_at
  janela = (ep.started_at..(fim + TOOL_WINDOW))

  msgs = Message.where(conversation_id: ep.conversation_id, private: false)
                .where(id: ep.first_message_id..ep.last_message_id)
                .order(:created_at)
                .pluck(:id, :message_type, :sender_type, :sender_id, :created_at,
                       Arel.sql("LENGTH(BTRIM(COALESCE(content, '')))"))
                .map { |id, tipo, stype, sid, at, len| { id: id, tipo: tipo, stype: stype, sid: sid, at: at, len: len.to_i } }

  if msgs.empty?
    sem_mensagem += 1
    next
  end

  calls = tool_calls[ep.conversation_id].select { |c| janela.cover?(c[:at]) }
  sem_tool_call += 1 if calls.empty?
  respostas_ia = msgs.select { |m| m[:tipo] == MSG_OUTGOING && IA_SENDERS.include?(m[:stype]) }
  ia_msg_ids.concat(respostas_ia.map { |m| m[:id] })

  degraus = {}
  registrar = lambda { |degrau, quem| degraus[degrau] ||= quem }

  # 1. respondeu — o lead deu sinal de vida
  registrar.call('respondeu', 'contato') if msgs.any? { |m| m[:tipo] == MSG_INCOMING }

  # 2. caminho da IA: salvar_info_lead com status que move a escada (tool antes de funil)
  calls.select { |c| c[:nome] == 'salvar_info_lead' && c[:status] == 'ok' }.each do |call|
    degrau = STATUS_DEGRAU[call[:args]['status'].to_s]
    registrar.call(degrau, 'ia') if degrau
  end

  # 3. caminho humano/sistema: card movido no Kanban dentro da janela
  funil[ep.conversation_id].select { |f| f[:at] && janela.cover?(f[:at]) }.each do |mov|
    degrau = STAGE_DEGRAU[mov[:tipo]]
    registrar.call(degrau, mov[:by] ? 'humano' : 'sistema') if degrau
  end

  # 4. handoff — o marcador já é um timestamp ISO8601
  attrs = conversas[ep.conversation_id] || {}
  handoff_at = begin
    bruto = attrs['aguardando_humano_desde']
    bruto.present? ? Time.zone.parse(bruto.to_s) : nil
  rescue ArgumentError
    nil
  end
  handoff_at = nil unless handoff_at && janela.cover?(handoff_at)
  if handoff_at
    por_tool = calls.any? { |c| HANDOFF_TOOLS.include?(c[:nome]) && c[:status] == 'ok' }
    registrar.call('handoff', por_tool ? 'ia' : 'sistema')

    # 5. assumido — humano respondeu depois do handoff
    assumiu = msgs.any? { |m| m[:tipo] == MSG_OUTGOING && m[:stype] == 'User' && m[:at] >= handoff_at }
    registrar.call('assumido', 'humano') if assumiu
  end

  textos = respostas_ia.map { |m| m[:len] }.reject(&:zero?)
  resultados << {
    id: ep.id,
    degraus: degraus,
    converteu: CONVERSAO.any? { |d| degraus.key?(d) },
    campanha: attrs['meta_campanha'],
    ia_ids: respostas_ia.map { |m| m[:id] },
    turnos_ia: respostas_ia.size,
    chars: textos.empty? ? nil : (textos.sum.to_f / textos.size).round,
    ferramentas: calls.size
  }
rescue StandardError => e
  warn "  ! episódio #{ep.id}: #{e.class} #{e.message.to_s[0, 90]}"
end

com_midia = Attachment.where(message_id: ia_msg_ids.uniq).distinct.pluck(:message_id).to_set
resultados.each { |r| r[:midia] = r[:ia_ids].any? { |id| com_midia.include?(id) } }

# ── relatório ───────────────────────────────────────────────────────────────
analisados = resultados.size
puts "\n#{'─' * 78}\nESCADA — degrau detectado (autoria entre parênteses)"
DEGRAUS.each do |degrau|
  atingiram = resultados.select { |r| r[:degraus].key?(degrau) }
  next if atingiram.empty?

  autoria = atingiram.group_by { |r| r[:degraus][degrau] }
                     .map { |quem, list| "#{quem} #{list.size}" }
                     .sort_by { |s| -s.split.last.to_i }.join(' · ')
  marca = CONVERSAO.include?(degrau) ? '*' : ' '
  puts format('  %<m>s %<d>-12s %<n>5d  %<p>5.1f%%   (%<a>s)',
              m: marca, d: degrau, n: atingiram.size,
              p: 100.0 * atingiram.size / analisados, a: autoria)
end
puts '  (* = compõe a conversão)'

sem_degrau = resultados.count { |r| r[:degraus].empty? }
convertidos = resultados.count { |r| r[:converteu] }
puts "\nSEM DEGRAU NENHUM: #{sem_degrau} de #{analisados} " \
     "(#{(100.0 * sem_degrau / analisados).round}%) — lead nunca respondeu ou sem sinal"
puts "CONVERSÃO (qualificado ou handoff): #{convertidos} de #{analisados} = " \
     "#{(100.0 * convertidos / analisados).round}%"

def resumo_conduta(rotulo, grupo)
  return if grupo.empty?

  com_chars = grupo.filter_map { |r| r[:chars] }
  media = ->(vals) { vals.empty? ? 0 : vals.sum.to_f / vals.size }
  format('    %<r>-15s %<n>5d eps · %<c>4d chars/resposta · %<t>4.1f turnos IA · %<f>4.1f tools · %<m>3d%% mídia',
         r: rotulo, n: grupo.size, c: media.call(com_chars).round,
         t: media.call(grupo.map { |r| r[:turnos_ia] }),
         f: media.call(grupo.map { |r| r[:ferramentas] }),
         m: (100.0 * grupo.count { |r| r[:midia] } / grupo.size).round)
end

puts "\n#{'─' * 78}\nCONDUTA × DESFECHO — correlação, NÃO causalidade"
puts resumo_conduta('converteu', resultados.select { |r| r[:converteu] })
puts resumo_conduta('não converteu', resultados.reject { |r| r[:converteu] })

por_campanha = resultados.reject { |r| r[:campanha].to_s.empty? }.group_by { |r| r[:campanha] }
if por_campanha.any?
  puts "\n#{'─' * 78}\nPOR CAMPANHA (5 maiores)"
  por_campanha.sort_by { |_, list| -list.size }.first(5).each do |campanha, list|
    conv = list.count { |r| r[:converteu] }
    puts "\n  #{campanha.to_s[0, 62]} — #{list.size} eps · conversão #{(100.0 * conv / list.size).round}%"
    puts resumo_conduta('converteu', list.select { |r| r[:converteu] })
    puts resumo_conduta('não converteu', list.reject { |r| r[:converteu] })
  end
else
  puts "\n(nenhum episódio com meta_campanha — o corte por campanha fica cego)"
end

puts "\n#{'─' * 78}\nAVISOS"
puts "  · #{sem_mensagem} episódio(s) sem mensagem avaliável (pulados)" if sem_mensagem.positive?
puts "  · #{sem_tool_call} episódio(s) sem NENHUMA tool call — se for a maioria, o F2 não cobria o período" if sem_tool_call.positive?
puts '  · zero "qualificado": ninguém chama salvar_info_lead com esse status. Conferir o prompt.' \
  if resultados.none? { |r| r[:degraus].key?('qualificado') }
puts '  · zero "handoff": conferir se aguardando_humano_desde está sendo escrito.' \
  if resultados.none? { |r| r[:degraus].key?('handoff') }
puts '  · nada foi gravado — este script é somente leitura.'
puts '=' * 78
