# D1 — "o pedido é o único caminho": com o modo ligado, conversa de dono HUMANO
# só troca de mãos via pedido aprovado ou por admin.
#
# POR QUE ISTO É UM PORO E NÃO UM GUARD NO AssignmentService OU NO MODELO:
#
# Existem 8+ caminhos que escrevem assignee_id (service, automação, round-robin,
# toggle_status, o próprio modelo, bulk job, update_all no destroy...). Guard no
# AssignmentService seria FALSA SEGURANÇA (a automação faz update! direto e
# passa por fora) e ainda quebraria 5 callers legítimos.
#
# Guard no modelo (AssignmentHandler) é pior: Macros::ExecutionService seta
# Current.user antes de rodar, então TODA macro com assign_agent quebraria em
# silêncio; update_all no agents/destroy_job pula callbacks; e throw :abort
# viraria RecordNotSaved em ~11 call sites que não tratam.
#
# Então o guard mora nas SUPERFÍCIES HUMANAS — e são três:
#   (a) assignments_controller#set_agent  → toda atribuição manual da UI/API
#   (b) bulk_actions_job                  → porta própria, aceita assignee_id
#   (c) toggle_status_service             → o "quem reabre, assume" do upstream
#
# Passam livres, sem precisar de bypass nenhum (é o ponto do desenho):
# automações, macros, round-robin, Captain/IA, kanban automation,
# conversation_builder, admin, self-assign de conversa sem dono, e a própria
# aprovação do pedido.
class Conversations::TakeoverGate
  def initialize(conversation:, actor:, new_assignee_id:)
    @conversation = conversation
    @actor = actor
    @new_assignee_id = new_assignee_id
  end

  # true = esta atribuição precisa de um pedido aprovado e deve ser barrada.
  def blocked?
    return false unless gate_enabled?
    return false unless human_takeover_attempt?

    !allowed_to_take_over?
  end

  def current_owner
    @conversation.assignee
  end

  private

  # "Tirar de um colega": só ISTO é o que o D1 regula. Conversa sem dono
  # (self-assign da fila) e conversa de IA/AgentBot não são takeover.
  def human_takeover_attempt?
    actor_is_human? && conversation_has_human_owner?
  end

  def allowed_to_take_over?
    admin? || approval_in_progress? || actor_is_the_owner? || no_op?
  end

  def gate_enabled?
    @conversation.account&.takeover_request_gate_enabled?
  end

  # AgentBot-token chega aqui com Current.user sendo um AgentBot; automação e
  # round-robin chegam com nil. Nenhum dos dois é "humano pegando a conversa".
  def actor_is_human?
    @actor.is_a?(User)
  end

  def admin?
    @conversation.account.account_users.exists?(user_id: @actor.id, role: :administrator)
  end

  # A própria aprovação do pedido atribui a conversa — se ela batesse no guard,
  # aprovar seria impossível (regressão clássica). Thread-local, sempre limpo
  # num ensure (Puma reusa threads).
  def approval_in_progress?
    Current.takeover_approval_in_progress.present?
  end

  # Conversa SEM dono (self-assign da fila) e conversa de IA/AgentBot não são
  # "tirar de um colega" — passam livres.
  def conversation_has_human_owner?
    @conversation.assignee_id.present?
  end

  def actor_is_the_owner?
    @conversation.assignee_id == @actor.id
  end

  def no_op?
    @new_assignee_id.present? && @conversation.assignee_id == @new_assignee_id.to_i
  end
end
