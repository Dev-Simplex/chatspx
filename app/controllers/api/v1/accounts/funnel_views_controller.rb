# frozen_string_literal: true

# Kanban v2 (Fase 3) — CRUD of saved board views (filters + view mode) per
# funnel. A view is private to its owner unless `is_shared` is set.
class Api::V1::Accounts::FunnelViewsController < Api::V1::Accounts::BaseController
  before_action :funnel_view, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    ensure_funnel_visible!(params[:funnel_id]) if params[:funnel_id].present?
    scope = Current.account.funnel_views.visible_to(Current.user).ordered
    scope = scope.where(funnel_id: params[:funnel_id]) if params[:funnel_id].present?
    @funnel_views = scope
  end

  def show; end

  def create
    ensure_funnel_visible!(funnel_view_params[:funnel_id])
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

  # A saved view is scoped to a funnel; a user must be able to see that funnel
  # (via FunnelPolicy) to list or create views for it. This closes the gap where
  # funnel_views is not policy_scoped(Funnel) — e.g. an agent building a view of
  # the "Geral" funnel they can no longer see. Raises RecordNotFound (404).
  def ensure_funnel_visible!(funnel_id)
    return if funnel_id.blank?

    policy_scope(Funnel).find(funnel_id)
  end

  def check_authorization
    authorize(@funnel_view || FunnelView)
  end

  def funnel_view_params
    params.require(:funnel_view).permit(:name, :funnel_id, :view_mode, :is_shared, :position, filters: {})
  end
end
