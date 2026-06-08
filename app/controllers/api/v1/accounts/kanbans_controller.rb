# frozen_string_literal: true

class Api::V1::Accounts::KanbansController < Api::V1::Accounts::BaseController
  before_action :kanban, except: [:index, :create]
  before_action :check_authorization, except: [:index]

  def index
    authorize(Kanban.new(account: Current.account), :index?)
    Kanban::EnsureDefaultKanbansService.new(account: Current.account).perform
    @kanbans = policy_scope(Kanban).order(:position, :created_at)
  end

  def show; end

  def create
    @kanban = Current.account.kanbans.create!(kanban_params)
  end

  def update
    @kanban.update!(kanban_params)
  end

  def destroy
    @kanban.destroy!
    head :ok
  end

  def reorder_stages
    stage_ids = Array(params[:stage_ids]).map { |id| id.to_s.to_i }.reject(&:zero?)
    Kanbans::ReorderStagesService.new(kanban: @kanban, stage_ids: stage_ids).perform
    head :ok
  rescue StandardError => e
    Rails.logger.error "KanbansController#reorder_stages: #{e.class} - #{e.message}"
    render json: { error: 'Error reordering stages', details: (Rails.env.development? ? e.message : nil) }, status: :internal_server_error
  end

  def metrics
    @metrics = Kanbans::MetricsService.call(kanban: @kanban)
    render json: @metrics
  end

  private

  def kanban
    @kanban ||= policy_scope(Kanban).find(params[:id])
  end

  def kanban_params
    # Accepts either :kanban or :funnel root key for backward-compat with frontend during P0-03.
    root = params[:kanban].present? ? :kanban : :funnel
    permitted = params.require(root).permit(:name, :position, :color, :team_id, inbox_ids: [])
    # P3-04 / P3-02: settings é JSONB (daily_summary, ai_triage_enabled, etc.).
    permitted = permitted.merge(settings: params[root][:settings].to_unsafe_h) if params[root][:settings].present?
    permitted
  end

  def check_authorization
    authorize(@kanban || Kanban.new(account: Current.account))
  end
end
