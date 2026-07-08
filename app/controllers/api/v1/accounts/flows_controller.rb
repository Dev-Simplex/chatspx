class Api::V1::Accounts::FlowsController < Api::V1::Accounts::BaseController
  before_action :fetch_flow, only: [:show, :update, :destroy, :execute, :simulate, :logs]
  before_action :check_authorization, only: [:show, :update, :destroy, :execute]

  # Máximo de step-logs por página no painel "Execuções" (GET #logs). Paginação simples via kaminari.
  LOGS_PER_PAGE = 50

  def index
    @flows = Current.account.flows.order(created_at: :desc)
    @flows = @flows.page(params[:page]).per(25) if params[:page].present?
  end

  def show; end

  def create
    @flow = Current.account.flows.new(flow_permit.merge(created_by_id: current_user.id, updated_by_id: current_user.id))
    assign_jsonb_attributes(@flow)

    return render_could_not_create_error(@flow.errors.messages) unless @flow.valid?

    @flow.save!
  end

  def update
    @flow.assign_attributes(flow_permit.merge(updated_by_id: current_user.id))
    assign_jsonb_attributes(@flow)

    return render_could_not_create_error(@flow.errors.messages) unless @flow.valid?

    @flow.save!
  end

  def destroy
    @flow.destroy!
    head :ok
  end

  # Disparo manual/bulk (trigger_type: manual) — espelha macros#execute.
  def execute
    ::Flows::ExecutionJob.perform_later(@flow.id, conversation_ids: params[:conversation_ids], user_id: current_user.id)
    head :ok
  end

  # SIMULAÇÃO (dry-run): percorre o grafo com uma conversa de exemplo e devolve os passos que o
  # fluxo SEGUIRIA — o nó, o que faria e o ramo tomado — SEM efetivar nada. O Flows::SimulationService
  # é inócuo por construção (não executa ação, não suspende, não persiste, não envia mensagem).
  # Autoriza como #show? (é uma leitura do que aconteceria, no mesmo espírito do #execute). Sem
  # conversa disponível devolve 422: o motor de condition/router precisa de uma conversa PERSISTIDA
  # da conta pra avaliar (roda uma query read-only sobre ela) — não dá pra simular sem uma amostra.
  def simulate
    authorize(@flow, :show?)
    @conversation = simulation_conversation
    return render_no_simulation_conversation if @conversation.nil?

    @simulation = ::Flows::SimulationService.new(flow: @flow, conversation: @conversation, actor: current_user).perform
  end

  # Painel "Execuções"/Logs: os últimos step-logs deste flow (mais recentes primeiro), paginados.
  # Trilha de auditoria por nó — o Flows::RunnerService grava um FlowStepLog por passo executado no
  # disparo REAL (status success/failed/skipped, ramo, error_code, duração). Autoriza como #show?.
  def logs
    authorize(@flow, :show?)
    @logs = FlowStepLog.for_flow(@flow).recent.page(params[:page]).per(LOGS_PER_PAGE)
  end

  # Importa as Macros e AutomationRules legadas da conta como Flows equivalentes, rodando o
  # Flows::BackfillService (idempotente via marcador trigger_config.backfill_source). Com
  # `dry_run: true` valida sem gravar. Autorização classe-nível na FlowPolicy#create? (importar
  # é criar em lote), no mesmo espírito do #execute. Devolve o resumo + os flows já importados.
  def import
    authorize(Flow.new(account: Current.account), :create?)
    @dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run]) || false
    @result = ::Flows::BackfillService.new(account: Current.account, dry_run: @dry_run).perform
    @flows = imported_flows
  end

  private

  # Todos os flows nascidos de um backfill (o service marca trigger_config.backfill_source).
  # Em dry_run nada foi gravado, então reflete só o que já existia de execuções anteriores.
  def imported_flows
    Current.account.flows.where("trigger_config->>'backfill_source' IS NOT NULL").order(created_at: :desc)
  end

  # `definition` (nodes+edges) e `trigger_config` são jsonb de forma variável — atribuídos
  # direto (como automation_rules faz com conditions/actions). O Flow#definition_shape/
  # definition_action_names validam o conteúdo antes do save.
  def assign_jsonb_attributes(flow)
    flow.definition = params[:definition].to_unsafe_h if params[:definition].respond_to?(:to_unsafe_h)
    flow.trigger_config = params[:trigger_config].to_unsafe_h if params[:trigger_config].respond_to?(:to_unsafe_h)
  end

  # Conversa de exemplo pra simular: a informada em `conversation_id` (aceita display_id ou id) ou,
  # na ausência, a mais recente da conta. O SimulationService avalia condition/router contra o estado
  # REAL dela (read-only) — por isso precisa de um registro PERSISTIDO, não um contexto sintético.
  def simulation_conversation
    scope = Current.account.conversations
    return scope.order(created_at: :desc).first if params[:conversation_id].blank?

    scope.find_by(display_id: params[:conversation_id]) || scope.find_by(id: params[:conversation_id])
  end

  # 422 com um código estável (não uma frase) — o front traduz pra a mensagem "escolha/crie uma
  # conversa pra simular" (AUTOMATION.CANVAS.SIMULATE.NO_CONVERSATION), nada hardcoded na UI.
  def render_no_simulation_conversation
    render json: { error: 'no_conversation' }, status: :unprocessable_entity
  end

  def flow_permit
    params.permit(:name, :description, :trigger_type, :active, :visibility)
  end

  def check_authorization
    authorize(@flow)
  end

  def fetch_flow
    @flow = Current.account.flows.find(params[:id])
  end
end
