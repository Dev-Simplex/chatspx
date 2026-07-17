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

  pattr_initialize [:account!, :conversation_display_id!]

  def perform
    transcript, response_map = build_transcript
    return { error: 'Sem mensagens para avaliar' } if transcript.blank?

    response = make_api_call(
      model: eval_model,
      messages: [
        { role: 'system', content: prompt_from_file('conversation_eval') },
        { role: 'user', content: [system_events_summary, transcript].compact.join("\n\n") }
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
    conversation.messages
                .where(message_type: %i[incoming outgoing])
                .where(private: false)
                .reorder('id asc')
  end

  def build_transcript
    messages = trim_to_limit(countable_messages.to_a)
    response_num = 0
    response_map = {}
    lines = messages.filter_map do |message|
      text = message_text(message)
      next if text.blank?

      if message.incoming?
        "[Cliente]: #{text}"
      elsif (label = sender_label(message))
        response_num += 1
        response_map[response_num] = message.id
        "[R#{response_num}][#{label}]: #{text}"
      else
        "[Sistema]: #{text}"
      end
    end
    [lines.join("\n"), response_map]
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
    counts = Captain::AssistantLog.where(conversation_id: conversation.id).group(:event_type).count
    return if counts.blank?

    "Eventos do sistema nesta conversa: #{counts.map { |k, v| "#{k}=#{v}" }.join(', ')}."
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
