module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  # F1.4 (modo FILA): quando ligado, a action assign_ai_agent vira no-op. Usado pela
  # re-triagem de órfãs (OrphanRetriageJob) no modo fila pra NÃO reanexar a IA e quebrar
  # a fila — a triagem inicial NUNCA seta isto (a IA atende normalmente na 1ª passada).
  thread_mattr_accessor :skip_ai_agent_assignment
  # Kanban v2 (Fase 5): reentrancy guard for the funnel automation engine. A
  # 'move' action re-triggers MoveService → the engine again; this depth counter
  # caps the chain so a misconfigured rule can never loop forever.
  thread_mattr_accessor :funnel_automation_depth
  # F1 (motor Flow): depth-guard para re-entrada SÍNCRONA inline de flows (ex.: um futuro
  # nó call_flow que invoque outro flow na mesma thread). NÃO cobre o re-trigger via
  # evento: o AutomationRuleListener despacha async (Sidekiq) e cada job nasce em thread
  # nova com este thread-local zerado, então loops cross-flow por evento são barrados pelo
  # anti-loop de mensagem (content_attributes.flow_id, lido na F4) + marcador idempotente
  # (F2), não por este contador. funnel_automation_depth acima só funciona por o Kanban
  # re-entrar inline (síncrono). Ver Flows::RunnerService::MAX_DEPTH.
  thread_mattr_accessor :flow_depth
  # D1 (Fase 3): a própria aprovação de um pedido atribui a conversa. Sem isto o
  # Conversations::TakeoverGate barraria o caminho de aprovação — ou seja, o gate
  # impediria justamente a única forma legítima de trocar de dono. Thread-local +
  # Puma reusa threads → quem setar TEM que limpar num `ensure` (precedente:
  # Macros::ExecutionService).
  thread_mattr_accessor :takeover_approval_in_progress
  thread_mattr_accessor :inbox
  # 6.01 (guardrail de pré-envio): janela de tool calls DESTA resposta, em memória.
  # O trace persistido (captain_tool_calls) só existe quando a conta tem eval_enabled,
  # e o guardrail precisa valer para toda conta — então quem gera a resposta abre a
  # janela, o TraceRecorder empurra pra dentro e o guardrail lê. Thread-local + Puma
  # reusa threads => quem abre TEM que fechar num `ensure` (Captain::ToolTraceWindow).
  thread_mattr_accessor :captain_tool_traces
  # 6.03 (citação de fonte): as fontes recuperadas DESTA resposta, em memória, para
  # virarem metadado da mensagem. Mesma disciplina do de cima (Captain::CitationWindow).
  thread_mattr_accessor :captain_citations

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.skip_ai_agent_assignment = nil
    Current.funnel_automation_depth = nil
    Current.flow_depth = nil
    Current.takeover_approval_in_progress = nil
    Current.inbox = nil
    Current.captain_tool_traces = nil
    Current.captain_citations = nil
  end
end
