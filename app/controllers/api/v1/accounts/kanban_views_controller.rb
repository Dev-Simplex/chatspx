# frozen_string_literal: true

# KANBAN-P2-04: CRUD de KanbanView (saved views pessoais).
class Api::V1::Accounts::KanbanViewsController < Api::V1::Accounts::BaseController
  before_action :kanban
  before_action :kanban_view, only: [:show, :update, :destroy]

  def index
    @kanban_views = kanban.kanban_views.where(user_id: Current.user.id, is_shared: false).ordered
  end

  def show; end

  def create
    @kanban_view = kanban.kanban_views.build(view_params.merge(user_id: Current.user.id, is_shared: false))
    if @kanban_view.save
      render :show
    else
      render json: { errors: @kanban_view.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @kanban_view.update(view_params)
      render :show
    else
      render json: { errors: @kanban_view.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @kanban_view.destroy!
    head :ok
  end

  private

  def kanban
    @kanban ||= policy_scope(Kanban).find(params[:kanban_id])
  end

  def kanban_view
    @kanban_view ||= kanban.kanban_views.where(user_id: Current.user.id).find(params[:id])
  end

  def view_params
    params.require(:kanban_view).permit(:name, :position, filters: {}, sort: {}, settings: {})
  end
end
