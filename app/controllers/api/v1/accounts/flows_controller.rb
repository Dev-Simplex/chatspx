class Api::V1::Accounts::FlowsController < Api::V1::Accounts::BaseController
  before_action :fetch_flow, only: [:show, :update, :destroy, :execute]
  before_action :check_authorization, only: [:show, :update, :destroy, :execute]

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

  private

  # `definition` (nodes+edges) e `trigger_config` são jsonb de forma variável — atribuídos
  # direto (como automation_rules faz com conditions/actions). O Flow#definition_shape/
  # definition_action_names validam o conteúdo antes do save.
  def assign_jsonb_attributes(flow)
    flow.definition = params[:definition].to_unsafe_h if params[:definition].respond_to?(:to_unsafe_h)
    flow.trigger_config = params[:trigger_config].to_unsafe_h if params[:trigger_config].respond_to?(:to_unsafe_h)
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
