# frozen_string_literal: true

# Kanban v2 (Fase 5) — CRUD of a funnel's declarative automations.
# Nested under funnels: /api/v1/accounts/:account_id/funnels/:funnel_id/automations
class Api::V1::Accounts::Funnels::AutomationsController < Api::V1::Accounts::BaseController
  before_action :funnel
  before_action :automation, except: [:index, :create]
  before_action :check_authorization

  def index
    @automations = funnel.funnel_automations.ordered
  end

  def show; end

  def create
    @automation = funnel.funnel_automations.build(automation_params)
    @automation.save!
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    @automation.update!(automation_params)
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    @automation.destroy!
    head :ok
  end

  private

  def funnel
    return @funnel if defined?(@funnel)

    @funnel = policy_scope(Funnel).find_by(id: params[:funnel_id])
    render json: { error: 'Funnel not found' }, status: :not_found unless @funnel
    @funnel
  end

  def automation
    @automation ||= funnel&.funnel_automations&.find(params[:id])
  end

  def automation_params
    params.require(:funnel_automation).permit(
      :name, :funnel_stage_id, :active,
      trigger: [:event, :hours],
      conditions: [:field, :op, :value],
      actions: [:type, :stage_id, :assignee_id, :url, { labels: [] }]
    )
  end

  def check_authorization
    return if performed? || funnel.blank?

    authorize(@automation || FunnelAutomation.new(funnel: funnel))
  end
end
