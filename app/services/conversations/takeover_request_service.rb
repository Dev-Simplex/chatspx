# D1 (Fase 3) — criar e resolver pedidos de atendimento.
#
# A aprovação é o ÚNICO lugar do fork que troca o dono "por fora" do gate, e por
# isso é a mais delicada do desenho:
#   - with_lock + reload: dois donos respondendo ao mesmo tempo, ou a conversa
#     trocando de mãos entre o pedido e a aprovação (→ `stale`).
#   - Current.takeover_approval_in_progress num `ensure`: sem isto o próprio
#     caminho de aprovação bateria no guard (o gate impediria a única forma
#     legítima de trocar de dono). Thread-local + Puma reusa threads → vazar isto
#     entre requests é o bug que ninguém acha.
#   - Aprovar SUPERSEDE os pedidos irmãos na MESMA transação.
class Conversations::TakeoverRequestService
  class Error < StandardError
    attr_reader :error_code

    def initialize(error_code, message = nil)
      @error_code = error_code
      super(message || error_code.to_s)
    end
  end

  def initialize(actor:, conversation: nil, request: nil)
    @conversation = conversation
    @request = request
    @actor = actor
  end

  def create!(reason: nil)
    # O pedido é uma superfície da Fase 3: sem o modo ligado ele não deve existir.
    # A UI já gateia (can_request?, compose, dropdown), mas um POST direto na API
    # furava isso — criava o pedido e notificava o dono mesmo com o modo DESLIGADO.
    # Guard de backend espelhando o front.
    raise Error.new(:takeover_gate_disabled, 'O modo de pedido de atendimento está desligado') unless
      @conversation.account.takeover_request_gate_enabled?

    # Ordem importa: a conversa de IA tem assignee_id NULO, então a checagem de
    # bot precisa vir ANTES da de "sem dono" — senão pedir conversa de bot
    # devolveria `conversation_unassigned`, que é o erro errado.
    raise Error.new(:conversation_owned_by_bot, 'Conversa atendida por IA') if @conversation.assignee_agent_bot_id.present?
    raise Error.new(:conversation_unassigned, 'Conversa sem dono — é só assumir') if @conversation.assignee_id.blank?
    raise Error.new(:takeover_request_self, 'Você já é o dono') if @conversation.assignee_id == @actor.id

    ConversationTakeoverRequest.create!(
      account_id: @conversation.account_id,
      conversation: @conversation,
      requester: @actor,
      # SNAPSHOT: se a conversa trocar de mãos depois, precisamos saber contra
      # QUEM o pedido foi feito.
      owner_id: @conversation.assignee_id,
      reason: reason.presence,
      status: :pending
    )
  rescue ActiveRecord::RecordNotUnique
    raise Error.new(:takeover_request_exists, 'Você já tem um pedido pendente nesta conversa')
  end

  def approve!(note: nil)
    resolve_with_lock do
      conversation = @request.conversation
      raise Error.new(:takeover_request_stale, 'A conversa trocou de dono desde o pedido') if
        conversation.assignee_id != @request.owner_id

      assign_to_requester!(conversation)
      @request.close!(status: :approved, source: resolution_source, responder: @actor, note: note)
      supersede_siblings!
      @request
    end
  end

  def deny!(note: nil)
    resolve_with_lock do
      @request.close!(status: :denied, source: resolution_source, responder: @actor, note: note)
      @request
    end
  end

  def cancel!
    resolve_with_lock do
      # Cancelar NÃO notifica o dono: ruído puro. Só o evento realtime some com
      # o banner.
      @request.close!(status: :cancelled, source: resolution_source, responder: @actor)
      @request
    end
  end

  private

  def resolve_with_lock
    @request.with_lock do
      @request.reload
      raise Error.new(:takeover_request_closed, 'Este pedido já foi respondido') unless @request.pending?

      yield
    end
  end

  def assign_to_requester!(conversation)
    # O flag que deixa a aprovação passar pelo TakeoverGate. `ensure` obrigatório.
    Current.takeover_approval_in_progress = true
    conversation.update!(assignee_id: @request.requester_id)
  ensure
    Current.takeover_approval_in_progress = nil
  end

  # Dois agentes podem pedir a mesma conversa (o dono escolhe). Aprovar um
  # encerra os outros — na mesma transação do with_lock.
  def supersede_siblings!
    ConversationTakeoverRequest
      .where(conversation_id: @request.conversation_id, status: :pending)
      .where.not(id: @request.id)
      .find_each { |sibling| sibling.close!(status: :superseded, source: :system) }
  end

  # Os três juntos importam: responded_by_id sozinho não distingue "o dono
  # aprovou" de "um admin que por acaso é o dono".
  def resolution_source
    return :owner if @request.owner_id == @actor.id

    admin? ? :admin : :system
  end

  def admin?
    @request.account.account_users.exists?(user_id: @actor.id, role: :administrator)
  end
end
