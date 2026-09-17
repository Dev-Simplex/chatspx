# Avalia UM atendimento (IA e/ou humano) via LLM-as-a-Judge e devolve um veredito
# estruturado: classificação do arco (interesse/intenção/funil/handoff) + auditoria
# resposta-a-resposta (respostas_problematicas).
#
# Espelha o ConversationCompletionService: é avaliação operacional interna e NÃO
# consome a cota do Captain — o retorno não expõe a chave :message, que é o que
# Enterprise::Captain::BaseTaskService usa para cobrar/incrementar uso.
class Captain::ConversationEvalService < Captain::BaseTaskService
  RESPONSE_SCHEMA = Captain::ConversationEvalSchema
  TRANSCRIPT_CHAR_LIMIT = 60_000
  EVAL_CONTEXT_CHAR_LIMIT = 20_000

  pattr_initialize [:account!, :conversation_display_id!, :episode, :model_override]

  def perform
    transcript, response_map = build_transcript
    return { error: 'Sem mensagens para avaliar' } if transcript.blank?

    response = make_api_call(
      model: eval_model,
      messages: [
        { role: 'system', content: [prompt_from_file('conversation_eval'), spec_context, eval_context].compact.join("\n\n") },
        { role: 'user', content: user_content(transcript) }
      ],
      schema: RESPONSE_SCHEMA
    )

    return { error: response[:error] } if response[:error].present?

    parse_verdict(response[:message], response_map)
  end

  private

  # Prompt vive no overlay Enterprise (não em lib/integrations/openai/openai_prompts).
  def prompt_from_file(file_name)
    Rails.root.join('enterprise/lib/captain/prompts', "#{file_name}.liquid").read
  end

  # Prefere a chave de sistema (custo interno, não debita a chave do cliente).
  def api_key
    @api_key ||= eval_api_key.presence || system_api_key.presence || openai_hook&.settings&.dig('api_key')
  end

  # Chave e modelo dedicados do eval, com fallback pra config compartilhada do captain.
  # Isola custo / rate-limit / blast-radius do juiz das demais funções OpenAI.
  def eval_api_key
    InstallationConfig.find_by(name: 'EVAL_OPEN_AI_API_KEY')&.value
  end

  def eval_model
    model_override.presence ||
      InstallationConfig.find_by(name: 'EVAL_OPEN_AI_MODEL')&.value.presence ||
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || GPT_MODEL
  end

  # O eval é avaliação operacional interna com opt-in próprio (eval_enabled),
  # desacoplado da feature 'captain_tasks' (tarefas clássicas do captain, que a
  # conta pode não ter). Este é o gate real do serviço: sem eval_enabled, o wrapper
  # Enterprise e o make_api_call curto-circuitam antes de gastar LLM.
  def captain_tasks_enabled?
    Captain::ConversationEval.enabled_for?(account)
  end

  def countable_messages
    scope = conversation.messages
                        .where(message_type: %i[incoming outgoing])
                        .where(private: false)
    # Unidade episódio: só as mensagens do episódio, nunca o blob da conversa.
    scope = scope.where(id: episode.first_message_id..episode.last_message_id) if episode.present?
    scope.reorder('id asc')
  end

  # Quanto do prompt do agente o juiz enxerga. Em 14k, ele julgava contra uma FATIA da norma
  # e tratava o resto como inexistente: medido em 31/08/2026 numa conta, 7 dos 8 agentes
  # ficavam truncados — a Júlia perdia 71% do prompt, a Bruna 64%, a Sofia 56%.
  #
  # O estrago concreto (conv 32808): a regra "quando há restrição no nome existem produtos da
  # casa que atendem" mora no char 15.825 do prompt da Júlia. A IA a cumpriu à risca, e o juiz
  # — que parava no 14.000 — marcou `info_incorreta` de severidade ALTA em cima da própria
  # norma que ela obedecia.
  #
  # Custo de cobrir o maior prompt: +8,4k tokens por avaliação, ~254 avaliações/dia, ≈ US$ 26
  # por mês no gpt-4.1-mini — e bem menos na prática, porque o spec_context é IDÊNTICO entre
  # avaliações do mesmo agente, que é exatamente o caso que o prompt caching desconta.
  # 60k acompanha o TRANSCRIPT_CHAR_LIMIT e deixa folga sobre o maior prompt real (47.691).
  SPEC_CHAR_LIMIT = 60_000

  # Spec-grounded judging (padrão Model Spec Evals): o juiz recebe as NORMAS do
  # agente de IA que atendeu o episódio (instructions da conta, lidas do banco) e
  # julga CONFORMIDADE — divergência factual ou de conduta em relação à spec vira
  # falha mesmo quando o juiz não conhece o negócio. Multi-tenant de graça: cada
  # conta injeta a própria spec.
  # De onde o cliente veio — anúncio, campanha, jornada do site.
  #
  # O agente JÁ recebe isso no state dele (`meta_anuncio` e afins), mas o juiz não recebia
  # nada além da transcrição e das tool calls. Resultado medido numa conta em 31/08/2026: a
  # IA repetia o texto do próprio anúncio ("a partir de R$ 500/mês", que é o criativo da
  # campanha) e o juiz, cego para a origem, marcava `alucinacao` de severidade alta. Eram
  # **61 dos 275** findings de alucinação em 30 dias vindos de conversas com anúncio.
  #
  # Julgar sem o contexto que o avaliado tinha não é rigor, é erro de medição — e um juiz
  # que acusa invenção onde houve leitura correta ensina a ignorar o juiz.
  ORIGEM_KEYS = { 'meta_anuncio' => 'anúncio', 'meta_campanha' => 'campanha',
                  'meta_origem' => 'origem', 'meta_tipo' => 'tipo de entrada',
                  'jornada' => 'jornada no site', 'meta_imovel' => 'imóvel do anúncio' }.freeze

  def origem_context
    attrs = conversation.custom_attributes || {}
    linhas = ORIGEM_KEYS.filter_map do |chave, rotulo|
      valor = attrs[chave].to_s.strip
      "- #{rotulo}: #{valor}" if valor.present?
    end
    return if linhas.empty?

    cabecalho = 'ORIGEM DA CONVERSA (o agente avaliado recebeu estes mesmos dados; o que ' \
                'estiver aqui é fonte legítima para ele, não invenção):'
    [cabecalho, *linhas].join("\n")
  end

  # O transcript vem por ARGUMENTO, não por leitura de escopo: ele é variável local do
  # `perform`, e quando este corpo foi extraído para cá (078efe33e6) o método passou a
  # referenciar um nome que não existe aqui. O efeito foi mudo e invertido — episódio SEM
  # atendimento saía cedo no `perform` e era gravado como 'sem_mensagens', enquanto todo
  # episódio COM atendimento estourava NameError e não gravava veredito nenhum. Em 3 dias,
  # ~420 atendimentos reais ficaram sem julgamento e o digest emudeceu por falta de finding.
  def user_content(transcript)
    [origem_context, carryover_context, system_events_summary,
     human_annotations_context, desfecho_context, transcript].compact.join("\n\n")
  end

  def spec_context
    instructions = episode_assistant&.config&.dig('instructions').to_s
    return if instructions.blank?

    "NORMAS DO AGENTE DE IA AVALIADO (#{episode_assistant.name}). A conduta e as afirmações da IA devem " \
      "CONFORMAR com estas normas: contradizer um fato ou uma regra daqui é falha (info_incorreta ou " \
      "quebrou_regra). As normas valem só para as respostas da IA, não para as dos humanos.\n---\n" \
      "#{instructions[0, SPEC_CHAR_LIMIT]}\n---"
  end

  def eval_context
    contexto = episode_assistant&.behavior&.dig('eval', 'contexto').to_s
    return if contexto.blank?

    "CONTEXTO DO NEGÓCIO AVALIADO (vale como os exemplos específicos deste cliente):\n---\n" \
      "#{contexto[0, EVAL_CONTEXT_CHAR_LIMIT]}\n---"
  end

  # O assistente dominante da janela avaliada (episódio) ou da conversa (legado).
  def episode_assistant
    @episode_assistant ||= begin
      scope = conversation.messages.where(sender_type: 'Captain::Assistant')
      scope = scope.where(id: episode.first_message_id..episode.last_message_id) if episode.present?
      sender_id = scope.reorder(:created_at).last&.sender_id
      Captain::Assistant.find_by(id: sender_id) if sender_id
    end
  end

  # Carryover (unidade episódio): resumo dos atendimentos ANTERIORES do mesmo contato,
  # pra o juiz não marcar falso "ignorou contexto" quando a IA referencia algo combinado
  # antes. Vem dos vereditos já gravados — custo zero de LLM.
  def carryover_context
    return if episode.blank? || episode.seq <= 1

    previous_ids = Captain::ConversationEpisode.where(conversation_id: conversation.id)
                                               .where(seq: ...episode.seq)
                                               .order(seq: :desc).limit(3).pluck(:id)
    resumos = Captain::ConversationEval.where(episode_id: previous_ids)
                                       .order(avaliado_em: :desc)
                                       .pluck(:funil, :resumo)
                                       .filter_map { |funil, resumo| "- [#{funil}] #{resumo}" if resumo.present? }
    return if resumos.empty?

    "Contexto (NÃO avaliar): atendimentos anteriores deste contato, do mais recente ao mais antigo:\n" \
      "#{resumos.join("\n")}\nAvalie SOMENTE o atendimento transcrito abaixo."
  end

  ANNOTATION_CHAR_LIMIT = 500

  # F4.2 (Eval humano): notas privadas da gestão com o marcador #eval são veredito
  # humano — quem opera o negócio apontou o problema (ou o acerto). Entram no prompt
  # com peso máximo, acima de qualquer inferência do próprio juiz.
  def human_annotations_context
    notes = annotation_scope.limit(10).filter_map do |message|
      texto = message.content.to_s.gsub(/#eval\b/i, ' ').gsub(/\s+/, ' ').strip
      "- [#{message.sender&.name.presence || 'gestor'}] #{texto[0, ANNOTATION_CHAR_LIMIT]}" if texto.present?
    end
    return if notes.empty?

    "AVALIAÇÃO HUMANA DA GESTÃO sobre este atendimento (peso MÁXIMO — a gestão conhece o negócio; " \
      "incorpore estes apontamentos ao veredito, refletindo-os na nota, nas respostas_problematicas " \
      "e no resumo; não os contradiga sem evidência forte no transcript):\n#{notes.join("\n")}"
  end

  def annotation_scope
    return episode.human_annotations if episode.present?

    conversation.messages
                .where(private: true, sender_type: 'User')
                .where('content ILIKE ?', '%#eval%')
                .reorder(:created_at)
  end

  def build_transcript
    messages = trim_to_limit(countable_messages.to_a)
    tools = pending_tool_lines(messages)
    response_num = 0
    response_map = {}
    lines = []
    messages.each do |message|
      # tool calls entram na posição cronológica correta (Eval 2.0 F2)
      lines << tools.shift[:line] while tools.any? && tools.first[:at] <= message.created_at
      text = message_text(message)
      next if text.blank?

      lines << if message.incoming?
                 "[Cliente]: #{text}"
               elsif (label = sender_label(message))
                 response_num += 1
                 response_map[response_num] = message.id
                 "[R#{response_num}][#{label}]#{marca_de_falha(message)}: #{text}"
               else
                 "[Sistema]: #{text}"
               end
    end
    tools.each { |t| lines << t[:line] }
    [lines.join("\n"), response_map]
  end

  # Tool calls da janela avaliada, prontas pra intercalar no transcript. O juiz passa
  # a VER o que cada ferramenta recebeu e devolveu — sem isso, "não achei imóvel" com
  # a busca retornando resultados passa invisível.
  def pending_tool_lines(messages)
    return [] if messages.empty?

    from = messages.first.created_at
    to = messages.last.created_at + 2.minutes
    Captain::ToolCall.for_conversation(conversation.id).in_window(from, to).order(:created_at).map do |call|
      resultado = call.status == 'error' ? "ERRO: #{call.error}" : call.result_preview.to_s[0, 1200]
      { at: call.created_at, line: "[TOOL #{call.tool_name} args=#{call.args.to_json[0, 200]} => #{resultado}]" }
    end
  end

  # Conversas longas: mantém a cauda (mensagens mais recentes) dentro do teto de chars.
  def trim_to_limit(messages)
    total = messages.sum { |m| message_text(m).length }
    while total > TRANSCRIPT_CHAR_LIMIT && messages.size > 1
      total -= message_text(messages.shift).length
    end
    messages
  end

  # Texto puro (NÃO content_for_llm — evita transcrição síncrona de áudio, que é
  # justamente a fonte de aborto do runtime). Mídia sem texto vira placeholder.
  # Áudio do cliente entra TRANSCRITO, como o agente o recebeu.
  #
  # Antes, mensagem de voz virava `[audio]` no transcript e o juiz não fazia ideia do que
  # tinha sido dito. Medido na conv 32808 (31/08/2026): o cliente perguntou por áudio *"essas
  # casinhas aonde mesmo? que cidade que é?"*, a IA respondeu *"É aqui em Sinop mesmo, MT"* —
  # resposta exata — e o juiz marcou `nao_respondeu_pergunta` de severidade alta, porque para
  # ele a IA falou de Sinop do nada.
  #
  # `content_for_llm` é o método que o próprio modelo já expõe para isso; usar outro caminho
  # seria duplicar a regra de fallback em dois lugares que vão divergir.
  def message_text(message)
    texto = message.content_for_llm.to_s.strip
    return texto if texto.present? && texto != '[Attachment]'
    return "[#{message.attachments.first.file_type}]" if message.attachments.any?

    ''
  end

  # O transcript carregava só o TEXTO, então uma resposta que a Meta recusou chegava ao juiz
  # idêntica a uma entregue. Numa conversa de 01/09 as três mensagens de foto falharam
  # (`100 - The parameter message[attachments][1][type] is required`), a cliente escreveu
  # "Não recebi fotos" e a IA reafirmou o envio — e o juiz não tinha como discordar, porque
  # para ele a foto tinha sido enviada. Sem esta marca, "afirmou ter enviado o que não chegou"
  # é invisível por construção.
  def marca_de_falha(message)
    return '' unless message.status == 'failed'

    motivo = message.external_error.to_s.strip
    motivo.present? ? " (NÃO ENTREGUE — #{motivo[0, 120]})" : ' (NÃO ENTREGUE)'
  end

  # O que aconteceu DEPOIS da última fala. O juiz mede a conversa e vai embora; lead que fica
  # esperando não é evento na transcrição e por isso nunca foi julgado. Com isto ele pode
  # separar "atendimento que terminou" de "atendimento que parou no meio".
  def desfecho_context
    ultima = conversation.messages.where(private: false, message_type: %i[incoming outgoing])
                         .order(:created_at).last
    return if ultima.nil?

    horas = ((Time.current - ultima.created_at) / 3600).round
    return if horas < 1

    attrs = conversation.custom_attributes || {}
    linhas = ["- última mensagem foi #{ultima.incoming? ? 'do CLIENTE' : 'do atendimento'}, há #{horas}h",
              "- a conversa está #{conversation.status}",
              "- dono agora: #{dono_atual}",
              "- follow-up (cutucada) programado ou disparado depois disso: #{cutucada_estado(attrs)}"]
    ['DESFECHO (o que aconteceu depois da última fala — use para julgar abandono, não a condução):',
     *linhas].join("\n")
  end

  def dono_atual
    return "humano (#{conversation.assignee.name})" if conversation.assignee.present?
    return 'a própria IA' if conversation.assignee_agent_bot.present?

    'ninguém'
  end

  def cutucada_estado(attrs)
    return "sim, #{attrs['followup_count']} já disparada(s)" if attrs['followup_count'].to_i.positive?
    return 'agendada, ainda não disparou' if attrs['followup_token'].present? || attrs['followup_status'].present?

    'NÃO'
  end

  def sender_label(message)
    case message.sender_type
    when 'User' then 'Humano'
    when 'Captain::Assistant', 'AgentBot' then 'IA'
    end
  end

  def system_events_summary
    scope = Captain::AssistantLog.where(conversation_id: conversation.id)
    scope = scope.where(created_at: episode.started_at..(episode.ended_at || Time.current)) if episode.present?
    counts = scope.group(:event_type).count
    return if counts.blank?

    "Eventos do sistema neste atendimento: #{counts.map { |k, v| "#{k}=#{v}" }.join(', ')}."
  end

  def parse_verdict(message, response_map)
    return { error: 'Formato de veredito inválido' } unless message.is_a?(Hash)

    message = deep_sanitize(message)
    {
      verdict: {
        representatividade: message['representatividade'].presence || 'atendimento_real',
        interesse: message['interesse'],
        intencao: message['intencao'],
        funil: message['funil'],
        conduzido_por: message['conduzido_por'],
        handoff_timing: message['handoff_timing'],
        nota: message['nota'],
        resumo: message['resumo'],
        objecoes: Array(message['objecoes']).map(&:to_s),
        response_findings: normalize_findings(message['respostas_problematicas'], response_map),
        veredito_raw: message
      }
    }
  end

  # Remove null bytes / caracteres de controle C0 que o Postgres (jsonb/text) recusa
  # ( e cia., vindos de mensagens do WhatsApp e ecoados pelo juiz no trecho).
  def deep_sanitize(obj)
    case obj
    when String then obj.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, '')
    when Array then obj.map { |v| deep_sanitize(v) }
    when Hash then obj.transform_values { |v| deep_sanitize(v) }
    else obj
    end
  end

  def normalize_findings(raw, response_map)
    Array(raw).filter_map do |finding|
      next unless finding.is_a?(Hash)

      {
        'resposta_num' => finding['resposta_num'],
        'message_id' => response_map[finding['resposta_num']],
        'quem' => finding['quem'],
        'categoria' => finding['categoria'],
        'severidade' => finding['severidade'],
        'trecho' => finding['trecho'],
        'porque' => finding['porque']
      }
    end
  end

  def event_name
    'captain.conversation_eval'
  end

  def build_follow_up_context?
    false
  end
end
