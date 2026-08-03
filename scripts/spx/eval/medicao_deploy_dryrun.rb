# frozen_string_literal: true

# MEDIÇÃO ANTES/DEPOIS do deploy de 31/07 — somente leitura.
#
#   rails runner /tmp/medicao_deploy.rb
#   ACCOUNT=6 DEPLOY='2026-07-31 16:00' HORA_INI=8 HORA_FIM=20 rails runner /tmp/medicao_deploy.rb
#
# SOMENTE LEITURA: todo acesso por pluck/count. Nada é gravado.
# SELF-CONTAINED: não referencia nada que só exista na branch spx/eval.
#
# ── O QUE ESTE INSTRUMENTO MEDE ────────────────────────────────────────────────
# Três mudanças entraram na MESMA janela e se misturam nas MESMAS conversas:
#   (1) safety-net de handoff passou a disparar   → evento handoff_auto_fired
#   (2) format_chunk entrega a passagem situada   → afeta toda conversa com knowledge
#   (3) prompt da Júlia, "# Quando o cliente pede pra falar depois"
#                                                 → baseline spx/fricoes: 41,2% (7/17)
#
# ⚠️ VERIFICADO em 02/08 contra o commit da VM (f542675b7), não assumido:
#   · 3be2381ce (mudança de contrato da tool programar_followup, spx/fricoes) NÃO está
#     deployada → esta medição é de PROMPT-SÓ. Se a tool entrar depois, a série quebra
#     ali e as janelas não são mais comparáveis.
#   · 0f320f967 (log durável de handoff, spx/rodizio) NÃO está deployada → o event_type
#     'handoff' segue sem ser escrito em produção.
#
# ── COMO ELE TENTA SEPARÁ-LAS ─────────────────────────────────────────────────
# Não dá pra separar por tempo (mesma janela). Dá pra separar por POPULAÇÃO, usando
# dois grupos de controle que já existem no dado:
#
#   · o prompt tocou SÓ A JÚLIA  → os outros agentes são controle. Se o cumprimento
#     sobe só na Júlia, é o prompt. Se sobe em todo mundo, não é o prompt.
#   · o format_chunk só afeta conversa COM RETRIEVAL → conversa sem knowledge é
#     controle. Se o efeito aparece nos dois grupos, não é o format_chunk.
#
# O que NENHUM corte separa está listado na seção RESSALVAS, no fim. Leia antes de
# concluir qualquer coisa.
#
# ── MÉTODO DA JANELA ──────────────────────────────────────────────────────────
# Sazonalidade mata esta medição: fim de semana derruba tudo e não significa nada.
# Por isso as duas janelas são restritas a DIA ÚTIL (seg–sex) ∩ HORÁRIO DE
# EXPEDIENTE, e a janela ANTES é dimensionada pra ter exatamente o MESMO tempo de
# expediente que a DEPOIS. As duas janelas são impressas dia a dia — confira.

ACCOUNT_ID = (ENV['ACCOUNT'] || 6).to_i
DEPLOY = Time.zone.parse(ENV['DEPLOY'] || '2026-07-31 16:00')
H_INI = (ENV['HORA_INI'] || 8).to_i
H_FIM = (ENV['HORA_FIM'] || 20).to_i
RESPOSTA_JANELA = (ENV['RESPOSTA_MIN'] || 30).to_i * 60
MIN_AMOSTRA = (ENV['MIN_AMOSTRA'] || 12).to_i

IA_SENDERS = %w[Captain::Assistant AgentBot].freeze
KNOWLEDGE_TOOLS = %w[search_knowledge faq_lookup].freeze

# Adiamento pedido PELO CLIENTE. Botão de template é sinal limpo (texto exato);
# o texto livre usa só frases inequívocas — "depois" solto pega "depois eu vejo".
BOTOES_ADIAMENTO = ['me chama depois', 'quero, mas outro horário', 'agendar horário',
                    'me chama mais tarde', 'depois eu falo'].freeze
ADIAMENTO = /
  (me\s+chama\s+(depois|mais\s+tarde)) | (te\s+chamo\s+(depois|mais\s+tarde)) |
  (falo\s+(com\s+voc[êe]\s+)?depois) | (agora\s+n[ãa]o\s+(posso|d[áa]|consigo)) |
  (mais\s+tarde\s+(eu|a\s+gente)?\s*(falo|vejo|respondo)?) | (outro\s+hor[áa]rio) |
  (outra\s+hora) | (estou\s+trabalhando|to\s+trabalhando|t[ôo]\s+trabalhando) |
  (em\s+reuni[ãa]o) | (ocupad[oa]\s+(agora|no\s+momento)) |
  (amanh[ãa]\s+(eu|a\s+gente)\s+(falo|conversa|vejo))
/xi

# Cumprimento da regra: a IA PERGUNTA o melhor horário em vez de só aceitar o adiamento.
PERGUNTA_HORARIO = /
  (melhor\s+hor[áa]rio) | (que\s+hor[áa]s) | (qual\s+hor[áa]rio) |
  (qual\s+(seria\s+)?o\s+melhor) | (quando\s+(fica|seria|for)\s+melhor) |
  (que\s+dia\s+(e\s+hor[áa]rio|fica|seria)) | (posso\s+te\s+(chamar|ligar))
/xi

# O CLIENTE já informou quando pode. Achado na amostra de 02/08 (conv 41665: "vou entrar
# em reunião às 15:15hs"): cobrar "perguntou o melhor horário?" nesses casos é errado — a
# conduta certa ali é USAR o horário, não perguntar de novo. Contá-los como
# não-cumprimento subestima a taxa. Ficam num grupo à parte, fora do denominador.
HORARIO_INFORMADO = /
  (\d{1,2}\s*[:h]\s*\d{0,2}) | (de\s+)?(manh[ãa]|tarde|noite)\b |
  \b(segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo)\b |
  (daqui\s+a\s+\d+) | (em\s+\d+\s*(min|hora))
/xi

def dia_util?(time)
  !time.saturday? && !time.sunday?
end

# Intervalos de expediente entre dois instantes (pula fim de semana).
def expediente(de, ate)
  out = []
  dia = de.to_date
  while dia <= ate.to_date
    base = Time.zone.local(dia.year, dia.month, dia.day)
    if dia_util?(base)
      ini = [base + H_INI.hours, de].max
      fim = [base + H_FIM.hours, ate].min
      out << [ini, fim] if fim > ini
    end
    dia += 1
  end
  out
end

# Caminha PRA TRÁS a partir de `ate`, acumulando o mesmo tanto de expediente.
def expediente_para_tras(ate, segundos)
  out = []
  restante = segundos
  dia = ate.to_date
  guarda = 0
  while restante > 1 && (guarda += 1) < 90
    base = Time.zone.local(dia.year, dia.month, dia.day)
    if dia_util?(base)
      fim = [base + H_FIM.hours, ate].min
      ini = base + H_INI.hours
      if fim > ini
        usar = [fim - ini, restante].min
        out.unshift([fim - usar, fim])
        restante -= usar
      end
    end
    dia -= 1
  end
  out
end

def dentro?(intervalos, instante)
  intervalos.any? { |ini, fim| instante >= ini && instante <= fim }
end

def fmt(intervalos)
  intervalos.map { |a, b| "#{a.strftime('%a %d/%m %H:%M')}–#{b.strftime('%H:%M')}" }.join(' · ')
end

def pct(parte, total)
  total.zero? ? 0.0 : 100.0 * parte / total
end

# ── janelas ───────────────────────────────────────────────────────────────────
agora = Time.zone.now
depois_iv = expediente(DEPLOY, agora)
depois_seg = depois_iv.sum { |a, b| b - a }
antes_iv = expediente_para_tras(DEPLOY, depois_seg)

puts '=' * 82
puts 'MEDIÇÃO ANTES/DEPOIS · deploy 31/07 — somente leitura, nada é gravado'
puts '=' * 82
account = Account.find(ACCOUNT_ID)
puts "conta #{account.id} · #{account.name} · agora #{agora.strftime('%a %d/%m %H:%M %Z')}"
puts "expediente considerado: dias úteis, #{H_INI}h–#{H_FIM}h (fim de semana fora das duas janelas)"
puts "  ANTES  (#{(depois_seg / 3600.0).round(1)}h): #{fmt(antes_iv)}"
puts "  DEPOIS (#{(depois_seg / 3600.0).round(1)}h): #{fmt(depois_iv)}"
if depois_iv.empty? || antes_iv.empty?
  puts "\n  Janela vazia (deploy no futuro, ou só fim de semana desde então). Nada a medir."
  exit
end
if depois_seg < 6 * 3600
  puts "\n  ⚠ menos de 6h de expediente pós-deploy. Rode de novo com um dia útil cheio."
end

# ── carga de mensagens (só nas janelas, + folga pra achar a resposta) ─────────
todos_iv = antes_iv + depois_iv
cond = todos_iv.map { '(messages.created_at BETWEEN ? AND ?)' }.join(' OR ')
args = todos_iv.flat_map { |a, b| [a, b + RESPOSTA_JANELA] }

msgs = Message.where(account_id: ACCOUNT_ID, private: false)
              .where(message_type: [0, 1])
              .where(cond, *args)
              .order(:created_at)
              .pluck(:id, :conversation_id, :message_type, :sender_type, :sender_id, :created_at,
                     Arel.sql('LEFT(COALESCE(content, \'\'), 300)'))
              .map do |id, cid, tp, st, sid, at, txt|
  { id: id, cid: cid, tipo: tp.is_a?(Integer) ? tp : { 'incoming' => 0, 'outgoing' => 1 }[tp.to_s],
    stype: st, sid: sid, at: at, txt: txt.to_s }
end
por_conversa = msgs.group_by { |m| m[:cid] }
conv_ids = por_conversa.keys

# ── SANIDADE DOS SINAIS ───────────────────────────────────────────────────────
puts "\n#{'─' * 82}\nSANIDADE DOS SINAIS"
amostra_tipo = Message.where(account_id: ACCOUNT_ID).limit(1).pluck(:message_type).first
puts "  pluck(:message_type) devolve #{amostra_tipo.class} #{amostra_tipo.inspect}"
puts "  mensagens carregadas: #{msgs.size} em #{conv_ids.size} conversas"
puts "    ANTES  #{msgs.count { |m| dentro?(antes_iv, m[:at]) }} · DEPOIS #{msgs.count { |m| dentro?(depois_iv, m[:at]) }}"

eventos = Captain::AssistantLog.where(conversation_id: conv_ids).group(:event_type).count
puts "  AssistantLog nestas conversas: #{eventos.sort_by { |_, v| -v }.map { |k, v| "#{k} #{v}" }.join(' · ').presence || '(nenhum)'}"
tem_auto_fired = Captain::AssistantLog.where(event_type: 'handoff_auto_fired').exists?
puts "  event_type 'handoff_auto_fired' existe no banco: #{tem_auto_fired ? 'SIM' : 'NÃO — o safety-net não gravou nada ainda'}"

assistentes = Captain::Assistant.where(account_id: ACCOUNT_ID).pluck(:id, :name).to_h
julia_ids = assistentes.select { |_, n| n.to_s.match?(/j[uú]lia/i) }.keys
puts "  agentes da conta: #{assistentes.map { |i, n| "#{i}:#{n}" }.join(' · ')}"
puts "  JÚLIA (alvo do prompt novo) = #{julia_ids.inspect} · controle = os demais"

tool_calls = Hash.new { |h, k| h[k] = [] }
Captain::ToolCall.where(conversation_id: conv_ids)
                 .pluck(:conversation_id, :tool_name, :created_at)
                 .each { |cid, nome, at| tool_calls[cid] << { nome: nome, at: at } }
puts "  conversas com tool call registrada (F2): #{tool_calls.size} de #{conv_ids.size}"

# ── (1) SAFETY-NET DE HANDOFF ─────────────────────────────────────────────────
puts "\n#{'─' * 82}\n(1) SAFETY-NET DE HANDOFF — baseline histórico: 0 (o evento não era gravável)"
%w[handoff_auto_fired handoff human_takeover].each do |ev|
  antes_n = antes_iv.sum { |i, f| Captain::AssistantLog.where(event_type: ev, created_at: i..f).count }
  depois_n = depois_iv.sum { |i, f| Captain::AssistantLog.where(event_type: ev, created_at: i..f).count }
  total = Captain::AssistantLog.where(event_type: ev).count
  puts format('    %<e>-20s antes %<a>4d · depois %<d>4d   (total histórico na instância: %<t>d)',
              e: ev, a: antes_n, d: depois_n, t: total)
end
puts '    → antes=0 e depois>0 aqui é ESPERADO e NÃO é efeito de conduta: o evento passou a existir.'
puts '      handoff_auto_fired nasceu no deploy de 31/07; handoff só passa a ser escrito quando'
puts '      0f320f967 (spx/rodizio) deployar — em 02/08 ele NÃO estava na VM. Se der 0 nos dois'
puts '      lados, é ausência de instrumento, não ausência de handoff.'

# ── (3) REGRA DO "FALAR DEPOIS" — o número que decide ─────────────────────────
def classificar_adiamentos(por_conversa, ia_senders, resposta_janela, botoes, regex_adia, regex_perg)
  eventos = []
  por_conversa.each_value do |lista|
    lista.each_with_index do |m, idx|
      next unless m[:tipo].zero?

      texto = m[:txt].strip
      via_botao = botoes.include?(texto.downcase)
      next unless via_botao || texto.match?(regex_adia)

      resposta = lista[(idx + 1)..].to_a.find do |n|
        n[:tipo] == 1 && ia_senders.include?(n[:stype]) && (n[:at] - m[:at]) <= resposta_janela
      end
      eventos << {
        cid: m[:cid], at: m[:at], via_botao: via_botao,
        pedido: texto, resposta: resposta&.dig(:txt).to_s,
        assistant_id: resposta&.dig(:sid),
        cumpriu: resposta ? resposta[:txt].match?(regex_perg) : false,
        respondeu: !resposta.nil?,
        # cliente já disse quando pode → cobrar a pergunta aqui é errado (ver HORARIO_INFORMADO)
        ja_deu_horario: !via_botao && texto.match?(HORARIO_INFORMADO)
      }
    end
  end
  eventos
end

adiamentos = classificar_adiamentos(por_conversa, IA_SENDERS, RESPOSTA_JANELA,
                                    BOTOES_ADIAMENTO, ADIAMENTO, PERGUNTA_HORARIO)
adiamentos.each do |e|
  e[:janela] = dentro?(antes_iv, e[:at]) ? :antes : (dentro?(depois_iv, e[:at]) ? :depois : nil)
end
adiamentos.select! { |e| e[:janela] }
# Denominador da regra = só quem adiou SEM dizer quando. Quem já deu o horário vira
# grupo à parte (a conduta certa lá é usar o horário, não perguntar).
com_horario = adiamentos.select { |e| e[:ja_deu_horario] }
adiamentos = adiamentos.reject { |e| e[:ja_deu_horario] }

def linha_cumprimento(rotulo, lista)
  a = lista.select { |e| e[:janela] == :antes }
  d = lista.select { |e| e[:janela] == :depois }
  return if a.empty? && d.empty?

  ca = a.count { |e| e[:cumpriu] }
  cd = d.count { |e| e[:cumpriu] }
  format('    %<r>-26s antes %<ca>3d/%<na>-3d %<pa>5.1f%%   depois %<cd>3d/%<nd>-3d %<pd>5.1f%%',
         r: rotulo, ca: ca, na: a.size, pa: pct(ca, a.size), cd: cd, nd: d.size, pd: pct(cd, d.size))
end

puts "\n#{'─' * 82}"
puts '(3) "QUANDO O CLIENTE PEDE PRA FALAR DEPOIS" — a IA pergunta o melhor horário?'
puts '    baseline spx/fricoes (método deles, 14 dias): 41,2% — 7 de 17'
puts "    detector daqui: adiamento do cliente → resposta da IA em até #{RESPOSTA_JANELA / 60}min"
puts '    denominador = adiamento SEM horário informado pelo cliente'
puts linha_cumprimento('GERAL', adiamentos)
if com_horario.any?
  ca = com_horario.count { |e| e[:janela] == :antes }
  cd = com_horario.count { |e| e[:janela] == :depois }
  puts "    (fora do denominador: #{ca + cd} adiamento(s) em que o CLIENTE já deu o horário" \
       " — antes #{ca} · depois #{cd}. Ali a conduta certa é usar, não perguntar.)"
end
puts "\n  por agente — a Júlia é o alvo do prompt; os outros são CONTROLE:"
puts linha_cumprimento('Júlia (alvo)', adiamentos.select { |e| julia_ids.include?(e[:assistant_id]) })
puts linha_cumprimento('outros agentes (ctrl)', adiamentos.reject { |e| julia_ids.include?(e[:assistant_id]) || e[:assistant_id].nil? })

puts "\n  por origem do pedido:"
puts linha_cumprimento('botão do template', adiamentos.select { |e| e[:via_botao] })
puts linha_cumprimento('texto livre', adiamentos.reject { |e| e[:via_botao] })

# Campanha: público diferente adia de jeito diferente, e a mistura entre as janelas
# pode se mover sozinha. Sem este corte, mudança de composição vira "efeito".
campanhas = Conversation.where(id: conv_ids).pluck(:id, :custom_attributes)
                        .to_h { |id, attrs| [id, (attrs || {})['meta_campanha']] }
adiamentos.each { |e| e[:campanha] = campanhas[e[:cid]] }
com_campanha = adiamentos.reject { |e| e[:campanha].to_s.empty? }
if com_campanha.any?
  puts "\n  por campanha (só onde a conversa tem meta_campanha):"
  com_campanha.group_by { |e| e[:campanha] }
              .sort_by { |_, l| -l.size }.first(5)
              .each { |campanha, lista| puts linha_cumprimento(campanha.to_s[0, 26], lista) }
  puts linha_cumprimento('(sem campanha)', adiamentos.select { |e| e[:campanha].to_s.empty? })
end

sem_resposta = adiamentos.reject { |e| e[:respondeu] }
puts "\n  adiamentos SEM resposta da IA em #{RESPOSTA_JANELA / 60}min: " \
     "antes #{sem_resposta.count { |e| e[:janela] == :antes }} · depois #{sem_resposta.count { |e| e[:janela] == :depois }}" \
     ' (ficam no denominador como não-cumprimento)'

fu = lambda do |jan|
  adiamentos.count do |e|
    e[:janela] == jan &&
      tool_calls[e[:cid]].any? { |t| t[:nome] == 'programar_followup' && (t[:at] - e[:at]).abs < 900 }
  end
end
puts "  adiamentos com programar_followup chamado (±15min): antes #{fu.call(:antes)} · depois #{fu.call(:depois)}"

# ── (2) FORMAT_CHUNK — controle por população ─────────────────────────────────
com_knowledge = ->(cid) { tool_calls[cid].any? { |t| KNOWLEDGE_TOOLS.include?(t[:nome]) } }
puts "\n#{'─' * 82}\n(2) FORMAT_CHUNK — conversa COM knowledge é a afetada; SEM knowledge é CONTROLE"
puts linha_cumprimento('com knowledge', adiamentos.select { |e| com_knowledge.call(e[:cid]) })
puts linha_cumprimento('sem knowledge (ctrl)', adiamentos.reject { |e| com_knowledge.call(e[:cid]) })

def conduta(msgs_ia)
  textos = msgs_ia.map { |m| m[:txt].strip.length }.reject(&:zero?)
  return '        (sem resposta da IA na janela)' if textos.empty?

  format('        %<n>5d respostas · %<c>4d chars/resposta (mediana %<m>4d)',
         n: textos.size, c: textos.sum / textos.size, m: textos.sort[textos.size / 2])
end

%i[antes depois].each do |jan|
  iv = jan == :antes ? antes_iv : depois_iv
  ia = msgs.select { |m| m[:tipo] == 1 && IA_SENDERS.include?(m[:stype]) && dentro?(iv, m[:at]) }
  puts "\n    #{jan.to_s.upcase} · resposta da IA em conversa COM knowledge:"
  puts conduta(ia.select { |m| com_knowledge.call(m[:cid]) })
  puts "    #{jan.to_s.upcase} · SEM knowledge (controle):"
  puts conduta(ia.reject { |m| com_knowledge.call(m[:cid]) })
end

# ── amostras, pra conferir o detector com o olho ──────────────────────────────
puts "\n#{'─' * 82}\nAMOSTRAS (confira se o detector está pegando a coisa certa)"
%i[depois antes].each do |jan|
  puts "\n  #{jan.to_s.upcase}:"
  adiamentos.select { |e| e[:janela] == jan }.first(4).each do |e|
    marca = e[:cumpriu] ? '✓' : '✗'
    puts "    #{marca} conv #{e[:cid]} #{e[:via_botao] ? '[botão]' : '[texto]'}"
    puts "        cliente: #{e[:pedido][0, 88]}"
    puts "        IA:      #{e[:resposta].to_s[0, 88].presence || '(não respondeu na janela)'}"
  end
end

# ── conversão (corte B), só se a tabela do F3 existir ─────────────────────────
if ActiveRecord::Base.connection.table_exists?('captain_episode_outcomes') &&
   defined?(Captain::EpisodeOutcome) && Captain::EpisodeOutcome.respond_to?(:conversao)
  puts "\n#{'─' * 82}\nCONVERSÃO — usa o scope `conversao` do model INSTALADO NA VM"
  puts '  (se a VM estiver num commit anterior ao corte B, este número ainda é o corte A)'
  %i[antes depois].each do |jan|
    iv = jan == :antes ? antes_iv : depois_iv
    conv = iv.sum { |i, f| Captain::EpisodeOutcome.conversao.where(account_id: ACCOUNT_ID, ocorreu_em: i..f).distinct.count(:episode_id) }
    tot = iv.sum { |i, f| Captain::EpisodeOutcome.where(account_id: ACCOUNT_ID, ocorreu_em: i..f).distinct.count(:episode_id) }
    puts format('    %<j>-7s %<c>4d de %<t>4d episódios com desfecho = %<p>5.1f%%', j: jan, c: conv, t: tot, p: pct(conv, tot))
  end
else
  puts "\n(tabela captain_episode_outcomes ausente — seção de conversão pulada)"
end

# ── RESSALVAS ─────────────────────────────────────────────────────────────────
puts "\n#{'─' * 82}\nRESSALVAS — leia antes de concluir"
n_depois = adiamentos.count { |e| e[:janela] == :depois }
if n_depois < MIN_AMOSTRA
  puts "  ⚠ AMOSTRA PEQUENA: só #{n_depois} adiamentos na janela DEPOIS (mínimo sugerido #{MIN_AMOSTRA})."
  puts '    Com esse N, uma diferença de 10-20 pontos ainda é ruído. NÃO decida a mudança da tool com isto.'
end
puts '  · As três mudanças subiram na MESMA janela. Movimento no cumprimento pode ser o prompt'
puts '    OU o format_chunk melhorando a resposta inteira. Os cortes por agente e por knowledge'
puts '    dão separação PARCIAL, não prova: a Júlia também usa knowledge.'
puts '  · O detector é de TEXTO. Ele não vê intenção — cliente que adia sem usar as frases'
puts '    conhecidas fica fora, e a IA pode ter perguntado o horário com palavras que a regex não'
puts '    cobre. Compare a AMOSTRA acima com o número antes de confiar nele.'
puts '  · O baseline de 41,2% veio de OUTRO método (spx/fricoes). O antes/depois válido é'
puts '    antes×depois DESTA saída; os 41,2% servem de ordem de grandeza, não de linha de base.'
puts '  · Nada aqui isola efeito de composição: se a mistura de campanhas mudou entre as janelas,'
puts '    parte do movimento é isso. Confira o volume por campanha antes de atribuir à conduta.'
puts '  · Somente leitura — nada foi gravado.'
puts '=' * 82
