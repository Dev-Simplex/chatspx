# A2d: a triagem é ASSÍNCRONA — o hook do 1º incoming roda ANTES da atribuição, então
# o gate por atribuição (A2) não vê dono e nada re-dispara a resposta. Quando o espelho
# captain é SETADO numa conversa com incoming pendente que o AGENTE ATUAL ainda não
# respondeu, este job re-executa o MESMO entry do pipeline (HookExecutionService) — router
# técnico + debounce respeitados. Cobre o 1º turno pós-triagem e a transferência IA->IA
# (inclusive quando o agente anterior já tinha mandado uma bolha antes de transferir).
class Captain::Conversation::AssignmentKickJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    return unless conversation.open? || conversation.pending?

    bot = conversation.assignee_agent_bot
    return unless bot&.captain? # re-check: dono pode ter mudado (humano que assume solta o espelho)

    last_incoming = conversation.messages.where(message_type: :incoming, private: false)
                                .order(:created_at).last
    return if last_incoming.nil?

    return if already_answered?(conversation, last_incoming, bot)

    # Mesmo entry do hook: o gate (re-keyado por atribuição) resolve o assistant pela
    # conversa e chama schedule_captain_response/debounce. Greeting/OOO não duplicam
    # (supressão por elegibilidade A2). Cota zerada -> perform_handoff (A8).
    ::MessageTemplates::HookExecutionService.new(message: last_incoming).perform
  end

  private

  # "Já respondido" = um HUMANO (ou o SISTEMA) respondeu, ou o PRÓPRIO agente atual já
  # respondeu, DEPOIS do último incoming. A resposta de OUTRO agente de IA NÃO conta: numa
  # transferência IA->IA, a saudação/ack do agente anterior (ex.: "Boa tarde!" da Clara antes
  # de passar pra Bruna) não pode calar o agente novo — ele ainda não engajou a pergunta
  # pendente. Sem isso, o guard antigo ("último visível é outgoing => respondido") deixava o
  # cliente no vácuo quando o agente que transferia tinha mandado qualquer bolha (bug conv 18633).
  def already_answered?(conversation, last_incoming, bot)
    conversation.messages.where(message_type: :outgoing, private: false)
                .where('messages.created_at > ?', last_incoming.created_at)
                .to_a.any? do |m|
      !(m.sender_type == 'Captain::Assistant' && m.sender_id != bot.captain_assistant_id)
    end
  end
end
