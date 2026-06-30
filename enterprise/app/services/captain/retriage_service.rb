# Devolução manual para a IA ("Devolver para a IA"): re-atribui a conversa ao
# assistente de TRIAGEM da conta (config['triage'] == true, ex.: Clara/recepção),
# se ele estiver elegível na inbox, e LIMPA o time + o assignee humano — para que
# a triagem releia o histórico, decida o assunto e re-roteie (dispara o kick A2d).
#
# É o gatilho MANUAL do que `Enterprise::MessageTemplates::HookExecutionService`
# já faz no automático (reattach_triage_assistant) — aqui sem depender do modo
# (vale em modo fila também, porque é uma ação intencional do agente, não a
# recaptura passiva F1.2 que precisa ficar desligada).
class Captain::RetriageService
  Result = Struct.new(:success, :assistant, :error, keyword_init: true)

  def initialize(conversation)
    @conversation = conversation
    @account = conversation.account
    @inbox = conversation.inbox
  end

  def call
    assistant = triage_assistant
    return failure('Nenhum assistente de triagem configurado nesta conta.') if assistant.nil?
    return failure('A triagem não está habilitada nesta caixa de entrada.') unless eligible?(assistant)

    mirror = AgentBot.captain.find_by(captain_assistant_id: assistant.id)
    return failure('Espelho da triagem não encontrado (rode captain:sync_mirrors).') if mirror.nil?

    # Time limpo + assignee humano limpo: a IA reassume a triagem e re-roteia.
    @conversation.update!(assignee_agent_bot_id: mirror.id, team_id: nil, assignee_id: nil)
    Result.new(success: true, assistant: assistant)
  rescue StandardError => e
    Rails.logger.warn("[Captain] retriage manual conv=#{@conversation.id}: #{e.message}")
    failure('Não foi possível devolver para a IA.')
  end

  private

  def triage_assistant
    Captain::Assistant.where(account_id: @account.id).detect { |a| (a.config || {})['triage'] == true }
  end

  def eligible?(assistant)
    ::CaptainInbox.exists?(inbox_id: @inbox.id, captain_assistant_id: assistant.id)
  end

  def failure(message)
    Result.new(success: false, error: message)
  end
end
