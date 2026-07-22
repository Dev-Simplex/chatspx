# Coloca uma conversa da IA na fila "Aguardando encerramento": marca
# `aguardando_encerramento_desde` para um humano JULGAR o fecho, SEM soltar o espelho captain
# (a IA segue dona e responde se o cliente voltar) e SEM fechar. A conversa some da aba "IA"
# e entra na fila. O concern (Enterprise::Concerns::Conversation#clear_awaiting_closure_marker)
# limpa o marcador quando um humano assume, o cliente volta a falar ou a conversa resolve.
#
# Gêmeo do Captain::Conversation::HumanHandoffService, mas para o eixo de ENCERRAMENTO: quem
# decide é o roteador de auto-resolve (conversa parada/encerrada), não a IA no meio do papo.
class Captain::Conversation::PendingClosureService
  def initialize(conversation:, assistant:, reason: nil)
    @conversation = conversation
    @assistant = assistant
    @reason = reason
  end

  def perform
    # Idempotente: já na fila -> não remarca (nem duplica dossiê nem reseta o desde).
    return if @conversation.custom_attributes&.dig('aguardando_encerramento_desde').present?

    create_note if @reason.present?

    # Visível na fila (a aba abre por status 'open') e fora do estado "bot atendendo" (pending),
    # mantendo o espelho captain — a IA continua dona e responde se o cliente voltar. Marca o
    # `desde` no MESMO save. NÃO resolve: quem julga o fecho é o humano.
    updates = { custom_attributes: (@conversation.custom_attributes || {}).merge('aguardando_encerramento_desde' => Time.current.iso8601) }
    updates[:status] = :open if @conversation.pending?
    @conversation.update!(updates)
  end

  private

  # dossiê privado pro humano que for julgar o fecho (auditabilidade)
  def create_note
    @conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: @assistant,
      account: @conversation.account,
      inbox: @conversation.inbox,
      content: @reason
    )
  end
end
