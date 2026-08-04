# frozen_string_literal: true

class Api::V1::Accounts::FunnelStagesController < Api::V1::Accounts::BaseController
  before_action :funnel
  before_action :funnel_stage, except: [:index, :create]
  before_action :check_authorization, except: [:create]

  def index
    return render json: { error: 'Funnel not found' }, status: :not_found unless funnel

    authorize(FunnelStage.new(funnel: funnel), :index?)
    @funnel_stages = funnel.funnel_stages.order(:position, :created_at)
    render 'api/v1/accounts/funnels/funnel_stages/index', formats: [:json]
  end

  def show
    render 'api/v1/accounts/funnels/funnel_stages/show', formats: [:json]
  end

  def create
    return render json: { error: 'Funnel not found' }, status: :not_found unless funnel

    @funnel_stage = funnel.funnel_stages.build(funnel_stage_params)
    authorize(@funnel_stage)
    @funnel_stage.save!
    broadcast_stages_changed
    render 'api/v1/accounts/funnels/funnel_stages/create', formats: [:json], status: :created
  rescue Pundit::NotAuthorizedError
    render json: { error: 'Not authorized' }, status: :forbidden
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    @funnel_stage.update!(funnel_stage_params)
    broadcast_stages_changed
    render 'api/v1/accounts/funnels/funnel_stages/update', formats: [:json]
  end

  def destroy
    @funnel_stage.destroy!
    broadcast_stages_changed
    head :ok
  end

  private

  # Tempo real (Fase 4): um evento só, com a lista completa e ordenada montada
  # pelo listener. Antes, criar/renomear/recolorir/apagar coluna exigia F5 — e o
  # caso "A apaga a coluna, B arrasta card para ela" dava 404 sem explicação.
  def broadcast_stages_changed
    Kanban::Realtime.dispatch(Events::Types::FUNNEL_STAGES_CHANGED, funnel: funnel)
  end

  def funnel
    return @funnel if defined?(@funnel)

    funnel_id = params[:funnel_id]
    @funnel = policy_scope(Funnel).find_by(id: funnel_id)
    unless @funnel
      render json: { error: 'Funnel not found' }, status: :not_found
      return nil
    end
    @funnel
  end

  def funnel_stage
    @funnel_stage ||= funnel&.funnel_stages&.find(params[:id])
  end

  def funnel_stage_params
    params.require(:funnel_stage).permit(:name, :position, :color, :automation_type, settings: [:wip_limit, :sla_hours])
  end

  def check_authorization
    return if performed? || funnel.blank?

    authorize(@funnel_stage || FunnelStage.new(funnel: funnel))
  end
end
