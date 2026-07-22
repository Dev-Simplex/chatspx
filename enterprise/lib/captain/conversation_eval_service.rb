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

  pattr_initialize [:account!, :conversation_display_id!, :episode, :model_override]

  def perform
    transcript, response_map = build_transcript
    return { error: 'Sem mensagens para avaliar' } if transcript.blank?

    response = make_api_call(
      model: eval_model,
      messages: [
        { role: 'system', content: [prompt_from_file('conversation_eval'), spec_context].compact.join("\n\n") },
        { role: 'user', content: [carryover_context, system_events_summary, transcript].compact.join("\n\n") }
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

  SPEC_CHAR_LIMIT = 14_000

  # Spec-grounded judging (padrão Model Spec Evals): o juiz recebe as NORMAS do
  # agente de IA que atendeu o episódio (instructions da conta, lidas do banco) e
  # julga CONFORMIDADE — divergência factual ou de conduta em relação à spec vira
  # falha mesmo quando o juiz não conhece o negócio. Multi-tenant de graça: cada
  # conta injeta a própria spec.
  def spec_context
    instructions = episode_assistant&.config&.dig('instructions').to_s
    return if instructions.blank?

    "NORMAS DO AGENTE DE IA AVALIADO (#{episode_assistant.name}). A conduta e as afirmações da IA devem " \
      "CONFORMAR com estas normas: contradizer um fato ou uma regra daqui é falha (info_incorreta ou " \
      "quebrou_regra). As normas valem só para as respostas da IA, não para as dos humanos.\n---\n" \
      "#{instructions[0, SPEC_CHAR_LIMIT]}\n---"
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
                 "[R#{response_num}][#{label}]: #{text}"
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
      resultado = call.status == 'error' ? "ERRO: #{call.error}" : call.result_preview.to_s[0, 400]
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
  def message_text(message)
    content = message.content.to_s.strip
    return content if content.present?
    return "[#{message.attachments.first.file_type}]" if message.attachments.any?

    ''
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
