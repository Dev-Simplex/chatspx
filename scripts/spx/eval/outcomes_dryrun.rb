# frozen_string_literal: true

# F3 · DRY-RUN v2 — vê a escada de desfechos ANTES de existir migration.
#
#   rails runner /tmp/f3_dryrun.rb              # conta 6, 500 episódios
#   ACCOUNT=6 LIMIT=1000 rails runner /tmp/f3_dryrun.rb
#
# SOMENTE LEITURA. Todo acesso por pluck/count; nenhum objeto instanciado pra salvar.
#
# SELF-CONTAINED: replica a detecção do Captain::EpisodeOutcomeService usando só o que
# existe na árvore desde 17/07 (episodes, tool_calls, assistant_logs, funnel_items,
# messages, conversations). Não referencia captain_episode_outcomes nem as colunas de
# traço, que vivem só na branch spx/eval.
#
# ── o que mudou da v1 (rodada de 30/07 na conta 6) ─────────────────────────────
# 1. HANDOFF/ASSUMIDO estavam cegos. `aguardando_humano_desde` é TRANSITÓRIO (2 de
#    20.170 conversas o tinham) e AssistantLog 'handoff' nunca é escrito. Agora o
#    degrau durável é o `assumido`, detectado pela 1ª outgoing de sender_type 'User',
#    qualificado por "a IA atendia antes?" (log human_takeover ou msg da IA anterior).
# 2. MESSAGE_TYPE: a v1 comparava com inteiro e nunca casava — `pluck` de coluna enum
#    devolve o RÓTULO. Agora normaliza os dois e IMPRIME o que a box devolveu.
# 3. TOOLS eram métrica circular (salvar_info_lead é o próprio detector de
#    `qualificado`). Agora conta só ferramenta de CONTEÚDO, e reporta a cobertura do F2.

ACCOUNT_ID = (ENV['ACCOUNT'] || ARGV[0] || 6).to_i
LIMIT = (ENV['LIMIT'] || ARGV[1] || 500).to_i

TOOL_WINDOW = 3 * 60
IA_SENDERS = %w[Captain::Assistant AgentBot].freeze
HANDOFF_TOOLS = %w[handoff transferir_para_agente].freeze
TOOLS_DETECTORAS = %w[salvar_info_lead handoff transferir_para_agente].freeze
STATUS_DEGRAU = {
  'qualificado' => 'qualificado', 'convertido' => 'qualificado',
  'esfriado' => 'esfriou', 'perdido' => 'esfriou',
  'nao_qualificado' => 'descartado'
}.freeze
STAGE_DEGRAU = { 'qualificado' => 'qualificado', 'frio' => 'esfriou' }.freeze
DEGRAUS = %w[respondeu qualificado handoff assumido esfriou descartado].freeze
ROTULOS = { 'incoming' => 0, 'outgoing' => 1, 'activity' => 2, 'template' => 3 }.freeze

# pluck de coluna enum devolve rótulo em algumas versões e inteiro em outras —
# normaliza os dois em vez de apostar (foi essa aposta que zerou a v1).
def tipo_de(valor)
  valor.is_a?(Integer) ? valor : ROTULOS[valor.to_s]
end

def media(vals)
  vals.empty? ? 0 : vals.sum.to_f / vals.size
end

account = Account.find(ACCOUNT_ID)
puts '=' * 78
puts 'F3 · DRY-RUN v2 — somente leitura, nada é gravado'
puts '=' * 78
puts "conta #{account.id} · #{account.name}"

episodios = Captain::ConversationEpisode
            .where(account_id: ACCOUNT_ID).where.not(ended_at: nil)
            .order(ended_at: :desc).limit(LIMIT).to_a
if episodios.empty?
  puts 'Nenhum episódio fechado — sem isso o F3 não tem o que ler.'
  exit
end
conv_ids = episodios.map(&:conversation_id).uniq
puts "episódios fechados: #{Captain::ConversationEpisode.where(account_id: ACCOUNT_ID).where.not(ended_at: nil).count} " \
     "— analisando os #{episodios.size} mais recentes (#{conv_ids.size} conversas)"

# ── SANIDADE DOS SINAIS (é aqui que se descobre detector cego) ──────────────
puts "\n#{'─' * 78}\nSANIDADE DOS SINAIS"
amostra = Message.where(conversation_id: conv_ids).limit(1).pluck(:message_type).first
puts "  pluck(:message_type) devolve #{amostra.class} #{amostra.inspect} → normalizado p/ #{tipo_de(amostra).inspect}"

fronteiras = Captain::ConversationEpisode.where(account_id: ACCOUNT_ID)
                                         .where.not(ended_at: nil).group(:boundary_reason).count
puts "  fronteiras dos episódios: #{fronteiras.sort_by { |_, v| -v }.map { |k, v| "#{k} #{v}" }.join(' · ')}"
if fronteiras.fetch('resolve', 0).zero? && fronteiras.fetch('hsm_campanha', 0).zero?
  puts '    ⚠ ZERO resolve e ZERO hsm_campanha: o EpisodeSegmenterService compara message_type'
  puts '      com INTEIRO (type == 2 / == 3). Se o pluck acima devolveu rótulo, essas duas'
  puts '      fronteiras nunca disparam E activities entram como mensagem do episódio.'
end

logs = Captain::AssistantLog.where(conversation_id: conv_ids).group(:event_type).count
puts "  AssistantLog nestas conversas: #{logs.sort_by { |_, v| -v }.map { |k, v| "#{k} #{v}" }.join(' · ')}"
puts '    (event_type "handoff" existe em EVENT_TYPES mas NADA no repo o escreve — ' \
     'log_tool_usage só loga no Rails.logger)'

com_assignee = Conversation.where(id: conv_ids).where.not(assignee_id: nil).count
puts "  conversas com assignee humano: #{com_assignee} de #{conv_ids.size}"

# ── carregamentos em lote ───────────────────────────────────────────────────
conversas = Conversation.where(id: conv_ids).pluck(:id, :custom_attributes).to_h

tool_calls = Hash.new { |h, k| h[k] = [] }
Captain::ToolCall.where(conversation_id: conv_ids)
                 .pluck(:conversation_id, :tool_name, :args, :status, :created_at, :captain_assistant_id)
                 .each { |cid, nome, args, st, at, aid| tool_calls[cid] << { nome: nome, args: args || {}, st: st, at: at, aid: aid } }

takeovers = Hash.new { |h, k| h[k] = [] }
Captain::AssistantLog.where(conversation_id: conv_ids, event_type: 'human_takeover')
                     .pluck(:conversation_id, :created_at)
                     .each { |cid, at| takeovers[cid] << at }

funil = Hash.new { |h, k| h[k] = [] }
FunnelItem.joins(:funnel_stage)
          .where(conversation_id: conv_ids, funnel_stages: { automation_type: STAGE_DEGRAU.keys })
          .pluck(:conversation_id, :moved_at, :moved_by_id, Arel.sql('funnel_stages.automation_type'))
          .each { |cid, at, by, tipo| funil[cid] << { at: at, by: by, tipo: tipo } }

# ── detecção ────────────────────────────────────────────────────────────────
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
                .map { |id, tp, st, sid, at, len| { id: id, tipo: tipo_de(tp), stype: st, sid: sid, at: at, len: len.to_i } }
  if msgs.empty?
    sem_mensagem += 1
    next
  end

  calls = tool_calls[ep.conversation_id].select { |c| janela.cover?(c[:at]) }
  sem_tool_call += 1 if calls.empty?
  respostas_ia = msgs.select { |m| m[:tipo] == 1 && IA_SENDERS.include?(m[:stype]) }
  ia_msg_ids.concat(respostas_ia.map { |m| m[:id] })

  degraus = {}
  registrar = ->(degrau, quem) { degraus[degrau] ||= quem if degrau }

  registrar.call('respondeu', 'contato') if msgs.any? { |m| m[:tipo].zero? }

  calls.select { |c| c[:nome] == 'salvar_info_lead' && c[:st] == 'ok' }
       .each { |c| registrar.call(STATUS_DEGRAU[c[:args]['status'].to_s], 'ia') }

  funil[ep.conversation_id].select { |f| f[:at] && janela.cover?(f[:at]) }
                           .each { |f| registrar.call(STAGE_DEGRAU[f[:tipo]], f[:by] ? 'humano' : 'sistema') }

  registrar.call('handoff', 'ia') if calls.any? { |c| HANDOFF_TOOLS.include?(c[:nome]) && c[:st] == 'ok' }

  # assumido: o humano FALOU (não só foi atribuído)
  primeira_humana = msgs.find { |m| m[:tipo] == 1 && m[:stype] == 'User' }
  ia_antes = false
  if primeira_humana
    ia_antes = takeovers[ep.conversation_id].any? { |at| janela.cover?(at) } ||
               respostas_ia.any? { |m| m[:at] < primeira_humana[:at] }
    registrar.call('assumido', 'humano')
  end

  textos = respostas_ia.map { |m| m[:len] }.reject(&:zero?)
  resultados << {
    degraus: degraus, campanha: (conversas[ep.conversation_id] || {})['meta_campanha'],
    ia_ids: respostas_ia.map { |m| m[:id] }, turnos_ia: respostas_ia.size,
    chars: textos.empty? ? nil : (textos.sum.to_f / textos.size).round,
    ferramentas: calls.count { |c| !TOOLS_DETECTORAS.include?(c[:nome]) },
    tem_f2: calls.any?, assumido_com_ia: primeira_humana && ia_antes,
    assumido_sem_ia: primeira_humana && !ia_antes
  }
rescue StandardError => e
  warn "  ! episódio #{ep.id}: #{e.class} #{e.message.to_s[0, 90]}"
end

com_midia = Attachment.where(message_id: ia_msg_ids.uniq).distinct.pluck(:message_id).to_set
resultados.each { |r| r[:midia] = r[:ia_ids].any? { |id| com_midia.include?(id) } }
analisados = resultados.size

# ── escada ──────────────────────────────────────────────────────────────────
puts "\n#{'─' * 78}\nESCADA"
DEGRAUS.each do |degrau|
  atingiram = resultados.select { |r| r[:degraus].key?(degrau) }
  next if atingiram.empty?

  autoria = atingiram.group_by { |r| r[:degraus][degrau] }.map { |q, l| "#{q} #{l.size}" }
                     .sort_by { |s| -s.split.last.to_i }.join(' · ')
  puts format('    %<d>-12s %<n>5d  %<p>5.1f%%   (%<a>s)', d: degrau, n: atingiram.size,
                                                           p: 100.0 * atingiram.size / analisados, a: autoria)
end

com_ia = resultados.count { |r| r[:assumido_com_ia] }
sem_ia = resultados.count { |r| r[:assumido_sem_ia] }
puts "\n  dos 'assumido': #{com_ia} com a IA atendendo antes · #{sem_ia} sem IA nenhuma (atendimento só-humano)"

sem_degrau = resultados.count { |r| r[:degraus].empty? }
puts "  SEM DEGRAU NENHUM: #{sem_degrau} de #{analisados} (#{(100.0 * sem_degrau / analisados).round}%)"

# ── os dois cortes de conversão, lado a lado ────────────────────────────────
corte_a = resultados.count { |r| r[:degraus].key?('qualificado') || r[:degraus].key?('handoff') }
corte_b = resultados.count { |r| r[:degraus].key?('qualificado') || r[:assumido_com_ia] }
puts "\n#{'─' * 78}\nCONVERSÃO — dois cortes, pra decidir com dado"
puts format('    A · qualificado + handoff        %<n>5d  %<p>5.1f%%   (handoff só existe onde o F2 gravou)',
            n: corte_a, p: 100.0 * corte_a / analisados)
puts format('    B · qualificado + assumido-c/-IA %<n>5d  %<p>5.1f%%   (durável; exclui conversa só-humana)',
            n: corte_b, p: 100.0 * corte_b / analisados)

# ── conduta × desfecho ──────────────────────────────────────────────────────
def linha_conduta(rotulo, grupo)
  return if grupo.empty?

  com_f2 = grupo.select { |r| r[:tem_f2] }
  format('    %<r>-15s %<n>5d eps · %<c>4d chars/resposta · %<t>4.1f turnos IA · %<m>3d%% mídia · tools %<f>4.1f (n=%<k>d)',
         r: rotulo, n: grupo.size, c: media(grupo.filter_map { |r| r[:chars] }).round,
         t: media(grupo.map { |r| r[:turnos_ia] }),
         m: (100.0 * grupo.count { |r| r[:midia] } / grupo.size).round,
         f: media(com_f2.map { |r| r[:ferramentas] }), k: com_f2.size)
end

converteu = ->(r) { r[:degraus].key?('qualificado') || r[:assumido_com_ia] }
puts "\n#{'─' * 78}\nCONDUTA × DESFECHO (corte B) — correlação, NÃO causalidade"
puts "  cobertura do F2: #{analisados - sem_tool_call} de #{analisados} episódios com tool call " \
     '— a média de tools vale só sobre esse subconjunto (n=)'
puts linha_conduta('converteu', resultados.select(&converteu))
puts linha_conduta('não converteu', resultados.reject(&converteu))

por_campanha = resultados.reject { |r| r[:campanha].to_s.empty? }.group_by { |r| r[:campanha] }
if por_campanha.any?
  puts "\n#{'─' * 78}\nPOR CAMPANHA (5 maiores)"
  por_campanha.sort_by { |_, l| -l.size }.first(5).each do |campanha, list|
    conv = list.count(&converteu)
    puts "\n  #{campanha.to_s[0, 62]} — #{list.size} eps · conversão #{(100.0 * conv / list.size).round}%"
    puts linha_conduta('converteu', list.select(&converteu))
    puts linha_conduta('não converteu', list.reject(&converteu))
  end
end

puts "\n#{'─' * 78}\nAVISOS"
puts "  · #{sem_mensagem} episódio(s) sem mensagem avaliável (pulados)" if sem_mensagem.positive?
puts "  · #{sem_tool_call} de #{analisados} sem NENHUMA tool call — F2 não cobria o período" if sem_tool_call.positive?
puts '  · zero chars/turnos: a normalização de message_type falhou — investigar tipo_de()' \
  if resultados.all? { |r| r[:turnos_ia].zero? }
puts '  · nada foi gravado — este script é somente leitura.'
puts '=' * 78
