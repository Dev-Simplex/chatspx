# frozen_string_literal: true

# KANBAN-P3-05: CRUD de automations + listing de receitas pré-prontas.
class Api::V1::Accounts::KanbanAutomationsController < Api::V1::Accounts::BaseController
  before_action :kanban
  before_action :automation, only: [:show, :update, :destroy]
  before_action :check_authorization, except: [:recipes, :send_summary_now]
  before_action :check_kanban_authorization, only: [:recipes, :send_summary_now]

  def index
    @automations = kanban.kanban_automations.order(created_at: :desc)
    render json: @automations.map { |a| serialize(a) }
  end

  def show
    render json: serialize(@automation)
  end

  def create
    @automation = kanban.kanban_automations.new(automation_params)
    if @automation.save
      render json: serialize(@automation), status: :created
    else
      render json: { errors: @automation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @automation.update(automation_params)
      render json: serialize(@automation)
    else
      render json: { errors: @automation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @automation.destroy
    head :no_content
  end

  def recipes
    file = Rails.root.join('config/kanban_automation_recipes.yml')
    data = YAML.load_file(file) if File.exist?(file)
    render json: data&.dig('recipes') || []
  rescue StandardError => e
    Rails.logger.error("recipes load failed: #{e.message}")
    render json: []
  end

  def send_summary_now
    result = Kanbans::DailySummaryService.call(kanban: kanban, user: Current.user)
    render json: result
  end

  private

  def check_kanban_authorization
    authorize(kanban, :show?)
  end

  def serialize(automation)
    {
      id: automation.id,
      name: automation.name,
      trigger: automation.trigger,
      conditions: automation.conditions,
      actions: automation.actions,
      enabled: automation.enabled,
      kanban_stage_id: automation.kanban_stage_id,
      kanban_id: automation.kanban_id,
      created_at: automation.created_at,
      updated_at: automation.updated_at
    }
  end

  def kanban
    @kanban ||= policy_scope(Kanban).find(params[:kanban_id])
  end

  def automation
    @automation ||= kanban.kanban_automations.find(params[:id])
  end

  def automation_params
    params.require(:kanban_automation).permit(
      :name, :trigger, :kanban_stage_id, :enabled,
      conditions: {},
      actions: [:type, :template_id, :template_slug, :agent_id, :label_id, :title, :stage_id, { variables: {} }]
    )
  end

  def check_authorization
    authorize(@automation || KanbanAutomation.new(kanban: kanban))
  end
end
