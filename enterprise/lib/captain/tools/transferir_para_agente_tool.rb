# Transferência IA->IA (C6 do modelo IA-como-agente): troca o dono-espelho da conversa.
# O AssignmentKickJob (callback de assignee_agent_bot_id) cutuca o agente novo, e o
# re-check do ResponseBuilderJob silencia o agente antigo — a passagem é invisível
# pro cliente e não duplica resposta.
class Captain::Tools::TransferirParaAgenteTool < Captain::Tools::BasePublicTool
  description 'Transfere a conversa para outro agente de IA da equipe (especialista do assunto). ' \
              'Use quando o assunto da conversa pertence a outro agente. A transferência é invisível ' \
              'para o cliente: o novo agente assume e continua a conversa.'

  param :agente, type: 'string', desc: 'Nome exato do agente de destino, conforme as regras de transferência das instruções.', required: true

  def perform(tool_context, agente:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa.' unless conversation

    alvo = resolve_target(conversation.account_id, agente)
    return "Não encontrei o agente #{agente} na equipe." if alvo.nil?
    return 'A conversa já está com este agente.' if conversation.assignee_agent_bot&.captain_assistant_id == alvo.id

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

  # O time do setor acompanha a especialista (config['team_id'] do agente alvo),
  # então a conversa já chega organizada pro humano que assumir depois.
  def transfer_attributes(conversation, alvo, mirror)
    attrs = { assignee_agent_bot_id: mirror.id }
    team = conversation.account.teams.find_by(id: alvo.config['team_id']) if alvo.config['team_id'].present?
    attrs[:team_id] = team.id if team
    attrs
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
