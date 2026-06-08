# frozen_string_literal: true

class Api::V1::Accounts::KanbanStagesController < Api::V1::Accounts::BaseController
  before_action :kanban
  before_action :kanban_stage, except: [:index, :create]
  before_action :check_authorization, except: [:create]

  def index
    return render json: { error: 'Kanban not found' }, status: :not_found unless kanban

    authorize(KanbanStage.new(kanban: kanban), :index?)
    @kanban_stages = kanban.kanban_stages.order(:position, :created_at)
    render 'api/v1/accounts/kanbans/kanban_stages/index', formats: [:json]
  end

  def show
    render 'api/v1/accounts/kanbans/kanban_stages/show', formats: [:json]
  end

  def create
    return render json: { error: 'Kanban not found' }, status: :not_found unless kanban

    @kanban_stage = kanban.kanban_stages.build(kanban_stage_params)
    authorize(@kanban_stage)
    @kanban_stage.save!
    render 'api/v1/accounts/kanbans/kanban_stages/create', formats: [:json], status: :created
  rescue Pundit::NotAuthorizedError
    render json: { error: 'Not authorized' }, status: :forbidden
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    @kanban_stage.update!(kanban_stage_params)
    render 'api/v1/accounts/kanbans/kanban_stages/update', formats: [:json]
  end

  def destroy
    @kanban_stage.destroy!
    head :ok
  end

  private

  def kanban
    return @kanban if defined?(@kanban)

    kanban_id = params[:kanban_id] || params[:funnel_id]
    @kanban = policy_scope(Kanban).find_by(id: kanban_id)
    unless @kanban
      render json: { error: 'Kanban not found' }, status: :not_found
      return nil
    end
    @kanban
  end

  def kanban_stage
    @kanban_stage ||= kanban&.kanban_stages&.find(params[:id])
  end

  def kanban_stage_params
    # Accepts either :kanban_stage or legacy :funnel_stage root key for frontend backward-compat.
    root = params[:kanban_stage].present? ? :kanban_stage : :funnel_stage
    params.require(root).permit(
      :name, :position, :color, :automation_type,
      # Phase 3 extras
      :probability, :wip_limit, :default_message_template_id, :rot_after_days,
      settings: {}
    )
  end

  def check_authorization
    return if performed? || kanban.blank?

    authorize(@kanban_stage || KanbanStage.new(kanban: kanban))
  end
end
