# frozen_string_literal: true

# Prepended no Flow via `Flow.prepend_mod_with('Flow')` (só no build enterprise). Espelha
# `Enterprise::AutomationRule#actions_attributes` (super + %w[add_sla assign_ai_agent]):
# no build enterprise, os nós de Flow também podem usar as ações enterprise, já que a base
# ActionService recebe o mixin Enterprise::ActionService (action_service.rb:113).
#
# Fase 3.2 — nós de IA: ai_classify (classifica a conversa em N categorias, alimenta um router)
# e ai_generate (gera texto → nota/atributo). Usam o Captain como motor via
# Captain::Llm::AssistantChatService (métodos em Flows::ActionService). São enterprise pela
# mesma razão do assign_ai_agent: dependem do Captain (assistants + LLM da conta).
module Enterprise::Flow
  def allowed_action_names
    super + %w[add_sla assign_ai_agent ai_classify ai_generate]
  end
end
