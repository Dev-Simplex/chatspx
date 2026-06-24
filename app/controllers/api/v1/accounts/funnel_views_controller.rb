# frozen_string_literal: true

# Kanban v2 (Fase 3) — CRUD of saved board views (filters + view mode) per
# funnel. A view is private to its owner unless `is_shared` is set.
class Api::V1::Accounts::FunnelViewsController < Api::V1::Accounts::BaseController
  before_action :funnel_view, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    scope = Current.account.funnel_views.visible_to(Current.user).ordered
    scope = scope.where(funnel_id: params[:funnel_id]) if params[:funnel_id].present?
    @funnel_views = scope
  end

  def show; end

  def create
    @funnel_view = Current.account.funnel_views.new(funnel_view_params)
    @funnel_view.user = Current.user
    @funnel_view.save!
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    @funnel_view.update!(funnel_view_params)
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    @funnel_view.destroy!
    head :ok
  end

  private

  def funnel_view
    @funnel_view ||= Current.account.funnel_views.find(params[:id])
  end

  def check_authorization
    authorize(@funnel_view || FunnelView)
  end

  def funnel_view_params
    params.require(:funnel_view).permit(:name, :funnel_id, :view_mode, :is_shared, :position, filters: {})
  end
end
