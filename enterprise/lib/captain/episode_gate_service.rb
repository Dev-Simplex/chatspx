# Gate determinístico do eval (Eval 2.0 F2): asserts de custo zero sobre o episódio,
# no padrão τ-bench/BFCL — fato binário é verificado por código, não por LLM. Os
# findings do gate entram em response_findings com 'origem' => 'gate' (o juiz LLM
# marca os dele sem origem) e severidade alta porque são flagras objetivos.
class Captain::EpisodeGateService
  NEGATIVE_REPLY = /n[ãa]o\s+(encontr|ach|localiz|temos|tem\b)/i
  EMPTY_RESULT = /nenhum|n[ãa]o encontr|not found|\A\s*\[\]\s*\z/i
  REPLY_WINDOW = 3.minutes
  MIN_REPEAT_LENGTH = 40

  pattr_initialize [:episode!]

  def perform
    findings = []
    findings.concat(contradicted_tool_findings)
    findings.concat(tool_error_findings)
    findings.concat(literal_repetition_findings)
    findings
  end

  private

  def conversation
    @conversation ||= episode.conversation
  end

  def ia_messages
    @ia_messages ||= conversation.messages
                                 .where(id: episode.first_message_id..episode.last_message_id)
                                 .where(message_type: :outgoing, private: false, sender_type: 'Captain::Assistant')
                                 .reorder(:created_at)
                                 .to_a
  end

  def tool_calls
    @tool_calls ||= Captain::ToolCall.for_conversation(conversation.id)
                                     .in_window(episode.started_at, (episode.ended_at || Time.current) + REPLY_WINDOW)
                                     .order(:created_at)
                                     .to_a
  end

  # Busca devolveu resultados e a resposta seguinte da IA nega — o flagra objetivo
  # do "não achei imóvel" falso.
  def contradicted_tool_findings
    tool_calls.filter_map do |call|
      next if call.status == 'error' || call.result_preview.blank?
      next if call.result_preview.match?(EMPTY_RESULT)

      reply = ia_messages.find { |m| m.created_at.between?(call.created_at, call.created_at + REPLY_WINDOW) }
      next unless reply && reply.content.to_s.match?(NEGATIVE_REPLY)

      gate_finding('contradisse_tool', reply,
                   "a ferramenta #{call.tool_name} devolveu resultados e a resposta seguinte negou tê-los encontrado")
    end
  end

  def tool_error_findings
    tool_calls.select { |call| call.status == 'error' }.map do |call|
      gate_finding('ignorou_erro_da_tool', nil,
                   "a ferramenta #{call.tool_name} falhou (#{call.error.to_s[0, 80]}) durante o atendimento",
                   severidade: 'media')
    end
  end

  # Bot-loop: a IA repetindo literalmente a mesma resposta no episódio.
  def literal_repetition_findings
    seen = {}
    ia_messages.filter_map do |message|
      key = message.content.to_s.strip.downcase.gsub(/\s+/, ' ')
      next if key.length < MIN_REPEAT_LENGTH

      first = seen[key]
      seen[key] = message
      next unless first

      gate_finding('repeticao', message, 'a IA repetiu literalmente uma resposta já enviada neste atendimento')
    end
  end

  def gate_finding(categoria, message, porque, severidade: 'alta')
    {
      'origem' => 'gate',
      'quem' => 'ia',
      'categoria' => categoria,
      'severidade' => severidade,
      'message_id' => message&.id,
      'trecho' => message&.content.to_s[0, 120],
      'porque' => porque
    }
  end
end
