# frozen_string_literal: true

class Api::V1::Accounts::FunnelStagesController < Api::V1::Accounts::BaseController
  before_action :funnel
  before_action :funnel_stage, except: [:index, :create]
  before_action :check_authorization, except: [:create]

  def index
    return render json: { error: 'Funil não encontrado' }, status: :not_found unless funnel

    authorize(FunnelStage.new(funnel: funnel), :index?)
    @funnel_stages = funnel.funnel_stages.order(:position, :created_at)
    render 'api/v1/accounts/funnels/funnel_stages/index', formats: [:json]
  end

  def show
    render 'api/v1/accounts/funnels/funnel_stages/show', formats: [:json]
  end

  def create
    return render json: { error: 'Funil não encontrado' }, status: :not_found unless funnel

    @funnel_stage = funnel.funnel_stages.build(funnel_stage_params)
    authorize(@funnel_stage)
    @funnel_stage.save!
    render 'api/v1/accounts/funnels/funnel_stages/create', formats: [:json], status: :created
  rescue Pundit::NotAuthorizedError
    render json: { error: 'Não autorizado' }, status: :forbidden
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    @funnel_stage.update!(funnel_stage_params)
    render 'api/v1/accounts/funnels/funnel_stages/update', formats: [:json]
  end

  def destroy
    @funnel_stage.destroy!
    head :ok
  end

  private

  def funnel
    return @funnel if defined?(@funnel)

    funnel_id = params[:funnel_id]
    @funnel = policy_scope(Funnel).find_by(id: funnel_id)
    unless @funnel
      render json: { error: 'Funil não encontrado' }, status: :not_found
      return nil
    end
    @funnel
  end

  def funnel_stage
    @funnel_stage ||= funnel&.funnel_stages&.find(params[:id])
  end

  def funnel_stage_params
    params.require(:funnel_stage).permit(:name, :position, :color, :automation_type)
  end

  def check_authorization
    return if performed? || funnel.blank?

    authorize(@funnel_stage || FunnelStage.new(funnel: funnel))
  end
end
