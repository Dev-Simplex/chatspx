# frozen_string_literal: true

class Api::V1::Accounts::FunnelStagesController < Api::V1::Accounts::BaseController
  before_action :funnel
  before_action :funnel_stage, except: [:index, :create]
  before_action :check_authorization, except: [:create]

  def index
    unless funnel
      return render json: { error: 'Funil não encontrado' }, status: :not_found
    end
    
    begin
      authorize(FunnelStage.new(funnel: funnel), :index?)

      stages = FunnelStage.uncached do
        funnel.funnel_stages.order(:position, :created_at)
      end

      stages_json = stages.map do |stage|
        {
          id: stage.id,
          name: stage.name,
          funnel_id: stage.funnel_id,
          position: stage.position,
          color: stage.color,
          automation_type: stage.automation_type,
          created_at: stage.created_at,
          updated_at: stage.updated_at
        }
      end

      render json: stages_json, status: :ok
    rescue StandardError => e
      Rails.logger.error "FunnelStagesController#index: Erro - #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: [], status: :ok
    end
  end

  def show; end

  def create
    Rails.logger.info "FunnelStagesController#create: Iniciando criação - Params: #{params.inspect}"
    
    unless funnel
      Rails.logger.error "FunnelStagesController#create: Funil não encontrado - ID: #{params[:funnel_id]}"
      return render json: { error: 'Funil não encontrado' }, status: :not_found
    end
    
    begin
      @funnel_stage = funnel.funnel_stages.build(funnel_stage_params)
      Rails.logger.info "FunnelStagesController#create: Objeto construído - #{@funnel_stage.inspect}"
      Rails.logger.info "FunnelStagesController#create: Válido? #{@funnel_stage.valid?}"
      Rails.logger.info "FunnelStagesController#create: Erros: #{@funnel_stage.errors.full_messages}" unless @funnel_stage.valid?
      
      # Autorizar após construir o objeto com os parâmetros
      authorize(@funnel_stage)
      Rails.logger.info "FunnelStagesController#create: Autorização OK"
      
      if @funnel_stage.save
        Rails.logger.info "FunnelStagesController#create: Etapa salva com sucesso - ID: #{@funnel_stage.id}"
        # Recarregar o objeto para garantir que tem todos os atributos
        @funnel_stage.reload
      render json: {
        id: @funnel_stage.id,
        name: @funnel_stage.name,
        funnel_id: @funnel_stage.funnel_id,
        position: @funnel_stage.position,
        color: @funnel_stage.color,
        automation_type: @funnel_stage.automation_type,
        created_at: @funnel_stage.created_at,
        updated_at: @funnel_stage.updated_at
      }, status: :created
      else
        Rails.logger.error "FunnelStagesController#create: Erro ao salvar - #{@funnel_stage.errors.full_messages.join(', ')}"
        render json: { errors: @funnel_stage.errors.full_messages }, status: :unprocessable_entity
      end
    rescue Pundit::NotAuthorizedError => e
      Rails.logger.error "FunnelStagesController#create: Não autorizado - #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      render json: { error: 'Não autorizado' }, status: :forbidden
    rescue ActionController::ParameterMissing => e
      Rails.logger.error "FunnelStagesController#create: Parâmetros faltando - #{e.message}"
      render json: { error: e.message }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error "FunnelStagesController#create: Erro inesperado - #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: e.message, class: e.class.name }, status: :internal_server_error
    end
  end

  def update
    begin
      Rails.logger.info "FunnelStagesController#update: Iniciando atualização - Stage ID: #{params[:id]}, Params: #{params.inspect}"
      
      if @funnel_stage.update(funnel_stage_params)
        Rails.logger.info "FunnelStagesController#update: Etapa atualizada com sucesso - ID: #{@funnel_stage.id}"
        @funnel_stage.reload
        render json: {
          id: @funnel_stage.id,
          name: @funnel_stage.name,
          funnel_id: @funnel_stage.funnel_id,
          position: @funnel_stage.position,
          color: @funnel_stage.color,
          automation_type: @funnel_stage.automation_type,
          created_at: @funnel_stage.created_at,
          updated_at: @funnel_stage.updated_at
        }, status: :ok
      else
        Rails.logger.error "FunnelStagesController#update: Erro ao atualizar - #{@funnel_stage.errors.full_messages.join(', ')}"
        render json: { errors: @funnel_stage.errors.full_messages }, status: :unprocessable_entity
      end
    rescue StandardError => e
      Rails.logger.error "FunnelStagesController#update: Erro inesperado - #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: e.message, class: e.class.name }, status: :internal_server_error
    end
  end

  def destroy
    @funnel_stage.destroy!
    head :ok
  end

  private

  def funnel
    return @funnel if defined?(@funnel)
    
    funnel_id = params[:funnel_id] || params[:id]
    # Usar policy_scope para garantir que apenas funis acessíveis sejam retornados
    @funnel = policy_scope(Funnel).find_by(id: funnel_id)
    unless @funnel
      Rails.logger.error "FunnelStagesController: Funil não encontrado ou não autorizado - ID: #{funnel_id}, Account: #{Current.account.id}"
      render json: { error: 'Funil não encontrado' }, status: :not_found
      return nil
    end
    Rails.logger.info "FunnelStagesController: Funil encontrado - ID: #{@funnel.id}, Nome: #{@funnel.name}"
    @funnel
  end

  def funnel_stage
    @funnel_stage ||= funnel.funnel_stages.find(params[:id])
  end

  def funnel_stage_params
    Rails.logger.info "FunnelStagesController: Params recebidos - #{params.inspect}"
    params.require(:funnel_stage).permit(:name, :position, :color, :automation_type)
  end

  def check_authorization
    return if performed? || funnel.blank?

    authorize(@funnel_stage || FunnelStage.new(funnel: funnel))
  rescue Pundit::NotAuthorizedError => e
    Rails.logger.error "FunnelStagesController#check_authorization: Não autorizado - #{e.message}"
    raise
  end
end
