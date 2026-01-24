# frozen_string_literal: true

class Api::V1::Accounts::FunnelsController < Api::V1::Accounts::BaseController
  before_action :funnel, except: [:index, :create]
  before_action :check_authorization, except: [:index]

  def index
    begin
      # Verificar autorização
      authorize(Funnel.new(account: Current.account), :index?)
      
      # Usar policy_scope para garantir que apenas funis acessíveis sejam retornados
      @funnels = policy_scope(Funnel).order(:position, :created_at)
    rescue Pundit::NotAuthorizedError => e
      Rails.logger.error "FunnelsController#index: Não autorizado - #{e.message}"
      render json: { error: 'Não autorizado', details: e.message }, status: :forbidden
    rescue StandardError => e
      Rails.logger.error "FunnelsController#index: Erro - #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { 
        error: e.message, 
        class: e.class.name,
        backtrace: Rails.env.development? ? e.backtrace.first(5) : nil
      }, status: :internal_server_error
    end
  end

  def show; end

  def create
    @funnel = Current.account.funnels.create!(funnel_params)
  end

  def update
    @funnel.update!(funnel_params)
  end

  def destroy
    @funnel.destroy!
    head :ok
  end

  def reorder_stages
    stage_ids = params[:stage_ids] || []
    Funnels::ReorderStagesService.new(funnel: @funnel, stage_ids: stage_ids).perform
    head :ok
  end

  private

  def funnel
    @funnel ||= policy_scope(Funnel).find(params[:id])
  end

  def funnel_params
    params.require(:funnel).permit(:name, :position, :color, inbox_ids: [])
  end

  def check_authorization
    authorize(@funnel || Funnel.new(account: Current.account))
  rescue Pundit::NotAuthorizedError => e
    Rails.logger.error "FunnelsController#check_authorization: Não autorizado - #{e.message}"
    raise
  end
end

