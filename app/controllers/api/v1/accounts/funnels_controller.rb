# frozen_string_literal: true

class Api::V1::Accounts::FunnelsController < Api::V1::Accounts::BaseController
  before_action :funnel, except: [:index, :create]
  before_action :check_authorization, except: [:index]

  def index
    authorize(Funnel.new(account: Current.account), :index?)
    Kanban::EnsureDefaultFunnelsService.new(account: Current.account).perform
    @funnels = policy_scope(Funnel).includes(:funnel_custom_fields).order(:position, :created_at)
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
    stage_ids = Array(params[:stage_ids]).map { |id| id.to_s.to_i }.reject(&:zero?)
    Funnels::ReorderStagesService.new(funnel: @funnel, stage_ids: stage_ids).perform
    head :ok
  rescue StandardError => e
    Rails.logger.error "FunnelsController#reorder_stages: #{e.class} - #{e.message}"
    render json: { error: 'Error reordering stages', details: (Rails.env.development? ? e.message : nil) }, status: :internal_server_error
  end

  private

  def funnel
    @funnel ||= policy_scope(Funnel).find(params[:id])
  end

  def funnel_params
    params.require(:funnel).permit(:name, :position, :color, :team_id, inbox_ids: [], settings: [:deadline_mode, :default_view])
  end

  def check_authorization
    authorize(@funnel || Funnel.new(account: Current.account))
  end
end
