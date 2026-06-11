# A2d: a triagem é ASSÍNCRONA — o hook do 1º incoming roda ANTES da atribuição, então
# o gate por atribuição (A2) não vê dono e nada re-dispara a resposta. Quando o espelho
# captain é SETADO numa conversa cujo último visível é incoming sem resposta, este job
# re-executa o MESMO entry do pipeline (HookExecutionService) — router técnico + debounce
# respeitados. Cobre o 1º turno pós-triagem e a transferência IA->IA.
class Captain::Conversation::AssignmentKickJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    return unless conversation.open? || conversation.pending?
    return unless conversation.assignee_agent_bot&.captain? # re-check: dono pode ter mudado

    # Último visível (incoming OU outgoing público): se já é outgoing, alguém respondeu
    # -> não cutuca. Mensagem do próprio assistant também conta como resposta.
    last = conversation.messages.where(message_type: %i[incoming outgoing], private: false)
                       .order(:created_at).last
    return unless last&.incoming?

    # Mesmo entry do hook: o gate (re-keyado por atribuição) resolve o assistant pela
    # conversa e chama schedule_captain_response/debounce. Greeting/OOO não duplicam
    # (supressão por elegibilidade A2). Cota zerada -> perform_handoff (A8).
    ::MessageTemplates::HookExecutionService.new(message: last).perform
  end
end
