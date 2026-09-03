# Execuções do conjunto de casos: histórico, disparo e comparação (bloco 6.02).
class Api::V1::Accounts::Captain::EvalRunsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization
  before_action :set_assistant

  def index
    @eval_runs = @assistant.eval_runs.recentes.page(params[:page]).per(25)
  end

  def show
    @eval_run = @assistant.eval_runs.find(params[:id])
    @results = @eval_run.results.includes(:eval_case).order(:eval_case_id)
  end

  # O custo ANTES de rodar. É um GET próprio de propósito: a tela precisa poder mostrar
  # o número sem ter disparado nada.
  def estimate
    @estimativa = Captain::Eval::CostEstimatorService.new(assistant: @assistant).perform
    render json: { data: @estimativa }
  end

  def create
    @eval_run = Captain::Eval::RunService.new(assistant: @assistant).enqueue
    @results = []
    render :show, status: :created
  end

  def compare
    base = @assistant.eval_runs.find(params[:base_id])
    comparada = @assistant.eval_runs.find(params[:comparada_id])
    render json: { data: Captain::Eval::ComparisonService.new(base: base, comparada: comparada).perform }
  end

  private

  def set_assistant
    @assistant = Current.account.captain_assistants.find(params[:assistant_id])
  end

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.user&.administrator?
  end
end
