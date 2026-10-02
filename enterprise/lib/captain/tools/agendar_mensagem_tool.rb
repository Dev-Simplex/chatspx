# AGENDADA (CHAT-165; engrenagem 2 do docs/contratos/eixo-followup.md): o cliente combina um
# momento para ser procurado e a IA deixa a mensagem PRONTA, agendada para ele. A cada turno a IA
# vê a agendada pendente no contexto (Captain::Conversation::AgendadaNote) e pode reescrevê-la,
# mudar o horário ou cancelá-la conforme a conversa muda.
#
# Uma agendada da IA por conversa: agendar de novo substitui a anterior — é assim que "ele só chega
# mais tarde" vira reagendamento sem acumular mensagens. O disparo é do
# ScheduledMessages::AssistantDeliveryService, que sai mesmo com a conversa num humano.
#
# Opt-in por agente: só existe para quem tem 'agendar_mensagem' em config['tools'].
class Captain::Tools::AgendarMensagemTool < Captain::Tools::BasePublicTool
  include Captain::Tools::MomentoDoCliente

  description 'Agenda, reescreve, reagenda ou cancela a mensagem que você vai mandar ao cliente no momento que ELE combinou ' \
              'para ser procurado. Use quando o cliente disser quando quer que você volte a falar com ele. ' \
              'A mensagem é escrita agora e sai sozinha no horário, mesmo que a conversa tenha passado para uma pessoa do time. ' \
              'Existe no máximo uma agendada por conversa: agendar de novo substitui a anterior, com o texto e o momento novos. ' \
              'Se a conversa mudar o combinado, agende de novo; se deixar de fazer sentido, cancele.'

  param :acao, type: 'string', desc: '`agendar` para criar ou substituir a agendada; `cancelar` para desfazê-la.', required: true
  param :quando,
        type: 'string',
        desc: 'O momento que o PRÓPRIO cliente disse para ser procurado, com as palavras dele nesta conversa. ' \
              'Obrigatório para agendar. Se ele não disse, pergunte antes; nunca deduza nem invente.',
        required: false
  param :texto,
        type: 'string',
        desc: 'A mensagem que vai ser enviada no horário, escrita agora para retomar exatamente o que ficou pendente nesta ' \
              'conversa. Obrigatório para agendar.',
        required: false

  # Mesmo teto do compromisso da programar_followup: além disso quem retoma é o time, não um lembrete.
  MAX_MINUTOS = 10_080

  def perform(tool_context, acao:, quando: nil, texto: nil)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa.' unless conversation

    case acao.to_s.strip.downcase
    when 'agendar' then agendar(conversation, quando, texto)
    when 'cancelar' then cancelar(conversation)
    else 'Ação desconhecida: use `agendar` ou `cancelar`.'
    end
  rescue StandardError => e
    Rails.logger.warn("[AgendarMensagemTool] #{e.message}")
    'Não consegui mexer na mensagem agendada agora.'
  end

  private

  def agendar(conversation, quando, texto)
    return 'Para agendar, preciso de `quando` (o momento nas palavras do cliente) e de `texto`.' if quando.blank? || texto.blank?

    minutos = minutos_ate(quando)
    if minutos.nil?
      return "Não entendi \"#{quando}\" como dia ou horário, então NÃO agendei. Confirme com o cliente o dia e o horário e agende de novo."
    end
    return "\"#{quando}\" passa de #{MAX_MINUTOS / 1440} dias, então NÃO agendei. Deixe esse retorno combinado com o time." if minutos > MAX_MINUTOS

    momento = minutos.minutes.from_now
    agendada = substituir(conversation, texto, momento)
    ScheduledMessages::SendJob.set(wait_until: momento).perform_later(agendada.id)
    "Mensagem agendada para #{I18n.l(momento, format: '%d/%m %H:%M')}. Ela sai sozinha nesse horário."
  end

  def substituir(conversation, texto, momento)
    ScheduledMessage.transaction do
      pendentes(conversation).find_each { |antiga| antiga.update!(status: :cancelled) }
      ScheduledMessage.create!(conversation: conversation, inbox: conversation.inbox, message: texto.to_s.strip,
                               scheduled_at: momento, status: :pending, captain_assistant_id: @assistant.id)
    end
  end

  def cancelar(conversation)
    canceladas = pendentes(conversation).find_each.count { |agendada| agendada.update!(status: :cancelled) }
    canceladas.positive? ? 'Mensagem agendada cancelada.' : 'Não havia mensagem agendada para cancelar.'
  end

  def pendentes(conversation)
    ScheduledMessage.pending.where(conversation_id: conversation.id).where.not(captain_assistant_id: nil)
  end
end
