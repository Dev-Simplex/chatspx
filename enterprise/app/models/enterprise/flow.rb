# frozen_string_literal: true

# Prepended no Flow via `Flow.prepend_mod_with('Flow')` (só no build enterprise). Espelha
# `Enterprise::AutomationRule#actions_attributes` (super + %w[add_sla assign_ai_agent]):
# no build enterprise, os nós de Flow também podem usar as ações enterprise, já que a base
# ActionService recebe o mixin Enterprise::ActionService (action_service.rb:113).
module Enterprise::Flow
  def allowed_action_names
    super + %w[add_sla assign_ai_agent]
  end
end
