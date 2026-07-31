# Transferência IA->IA (C6 do modelo IA-como-agente): troca o dono-espelho da conversa.
# O AssignmentKickJob (callback de assignee_agent_bot_id) cutuca o agente novo, e o
# re-check do ResponseBuilderJob silencia o agente antigo — a passagem é invisível
# pro cliente e não duplica resposta.
class Captain::Tools::TransferirParaAgenteTool < Captain::Tools::BasePublicTool
  description 'Transfere a conversa para outro agente de IA da equipe (especialista do assunto). ' \
              'Use quando o assunto da conversa pertence a outro agente. A transferência é invisível ' \
              'para o cliente: o novo agente assume e continua a conversa.'

  param :agente, type: 'string', desc: 'Nome exato do agente de destino, conforme as regras de transferência das instruções.', required: true

  # Trilho anti-ping-pong. Sem ele, A passa pra B, B devolve pra A e o cliente fica esperando
  # enquanto a conversa quica entre as duas — caso real: conv 17770 em 24/07, Júlia<->Bruna
  # três vezes em três minutos, até um humano quebrar o loop na mão.
  #
  # A janela é curta DE PROPÓSITO: com conversa única por contato (lock_to_single_conversation)
  # a conversa vive meses e troca de assunto legitimamente (locação -> financeiro -> manutenção).
  # Contar "transferências da conversa inteira" travaria a troca legítima semanas depois; o
  # loop, ao contrário, se resolve em minutos. Estourou o trilho -> chama gente, que é a saída
  # segura: melhor um humano a mais do que um cliente preso no vaivém.
  TRANSFER_WINDOW = 1.hour
  MAX_TRANSFERS_IN_WINDOW = 3
  TRANSFER_HISTORY_KEY = 'ia_transferencias'.freeze
  HISTORY_LIMIT = 10

  def perform(tool_context, agente:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa.' unless conversation

    alvo = resolve_target(conversation.account_id, agente)
    return "Não encontrei o agente #{agente} na equipe." if alvo.nil?
    return 'A conversa já está com este agente.' if conversation.assignee_agent_bot&.captain_assistant_id == alvo.id

    bloqueio = guard_transfer(conversation, alvo)
    return bloqueio if bloqueio

    # Lookup direto do espelho (sem mirror_agent_bot/sync!): a transferência não deve
    # criar espelho — se não existe, o agente não está operacional.
    mirror = AgentBot.find_by(captain_assistant_id: alvo.id)
    return "O agente #{alvo.name} está indisponível no momento." if mirror.nil?

    attrs = transfer_attributes(conversation, alvo, mirror)
    conversation.update!(attrs)
    log_tool_usage('transfer', conversation_id: conversation.id, to: alvo.name, team_id: attrs[:team_id])
    "Conversa transferida para #{alvo.name}, que assume a partir daqui. NÃO envie mais nenhuma resposta nesta conversa."
  rescue StandardError => e
    Rails.logger.warn("[TransferirParaAgenteTool] conv=#{conversation&.id}: #{e.message}")
    'Não consegui transferir a conversa agora.'
  end

  private

  # nil = pode transferir. String = recusa (o texto vai pro agente, que segue atendendo).
  # Dois gatilhos: (1) o destino JÁ participou do vaivém recente — devolver pra ele é o
  # ping-pong; (2) transferências demais na janela, mesmo sem repetir destino (o caso do
  # rodízio Rafa->vendas->captação->recepção, quatro setores em dois minutos).
  def guard_transfer(conversation, alvo)
    recentes = recent_transfers(conversation)
    return nil if recentes.empty?

    repetido = recentes.any? { |t| [t['de'], t['para']].include?(alvo.id) }
    estourou = recentes.size >= MAX_TRANSFERS_IN_WINDOW
    return nil unless repetido || estourou

    motivo = if repetido
               "#{alvo.name} já participou desta conversa na última hora"
             else
               "#{recentes.size} transferências entre agentes na última hora"
             end
    escalate_to_human(conversation, motivo)

    'NÃO transferi: esta conversa já trocou de agente vezes demais agora há pouco e outra ' \
      'transferência viraria vaivém. Um atendente humano foi acionado. Não tente transferir de ' \
      'novo — continue atendendo o cliente você mesmo até uma pessoa assumir.'
  end

  # Só as transferências dentro da janela. Entrada corrompida/sem timestamp é ignorada em vez
  # de derrubar a tool — histórico é telemetria, não pode bloquear atendimento.
  def recent_transfers(conversation)
    limite = TRANSFER_WINDOW.ago
    Array(conversation.custom_attributes&.dig(TRANSFER_HISTORY_KEY)).select do |t|
      t.is_a?(Hash) && t['t'].present? && Time.zone.parse(t['t'].to_s) > limite
    rescue StandardError
      false
    end
  end

  def escalate_to_human(conversation, motivo)
    Captain::Conversation::HumanHandoffService.new(
      conversation: conversation, assistant: @assistant,
      reason: "Transferência entre agentes bloqueada — #{motivo}. Conversa precisa de uma pessoa."
    ).perform
  rescue StandardError => e
    Rails.logger.warn("[TransferirParaAgenteTool] handoff conv=#{conversation.id}: #{e.message}")
  end

  # O time do setor acompanha a especialista (config['team_id'] do agente alvo),
  # então a conversa já chega organizada pro humano que assumir depois.
  # Registra a passagem (de -> para) no MESMO save: é o que a guarda lê na próxima chamada.
  def transfer_attributes(conversation, alvo, mirror)
    attrs = { assignee_agent_bot_id: mirror.id }
    team = conversation.account.teams.find_by(id: alvo.config['team_id']) if alvo.config['team_id'].present?
    attrs[:team_id] = team.id if team
    attrs[:custom_attributes] = (conversation.custom_attributes || {}).merge(
      TRANSFER_HISTORY_KEY => transfer_history(conversation, alvo)
    )
    attrs
  end

  def transfer_history(conversation, alvo)
    anterior = Array(conversation.custom_attributes&.dig(TRANSFER_HISTORY_KEY)).select { |t| t.is_a?(Hash) }
    (anterior + [{ 'de' => @assistant&.id, 'para' => alvo.id, 't' => Time.current.iso8601 }]).last(HISTORY_LIMIT)
  end

  def resolve_target(account_id, nome)
    candidatos = Captain::Assistant.where(account_id: account_id)
    normalizado = normalize(nome)
    candidatos.find { |a| normalize(a.name) == normalizado }
  end

  def normalize(str)
    str.to_s.strip.downcase.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
  end
end
