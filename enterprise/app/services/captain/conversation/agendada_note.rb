# A agendada pendente da IA nesta conversa, de volta ao contexto de cada turno (CHAT-165).
#
# A agendada não é `Message` enquanto não sai, então o agente não a enxergaria no histórico. Sem
# ela à vista, ele não tem como reagendar quando o cliente muda o combinado, nem cancelá-la quando
# ela perde o sentido.
#
# Só FATO: quando sai e o que diz. O que fazer com isso está na descrição da agendar_mensagem —
# mesma disciplina da ToolContextNote.
class Captain::Conversation::AgendadaNote
  def initialize(conversation:)
    @conversation = conversation
  end

  def text
    agendada = ScheduledMessage.pending.where(conversation_id: @conversation.id)
                               .where.not(captain_assistant_id: nil).order(:scheduled_at).last
    return if agendada.nil?

    '[Contexto do sistema: mensagem agendada pendente nesta conversa, feita com agendar_mensagem. ' \
      "Sai em #{I18n.l(agendada.scheduled_at.in_time_zone, format: '%d/%m %H:%M')} com o texto: \"#{agendada.message}\"]"
  end
end
