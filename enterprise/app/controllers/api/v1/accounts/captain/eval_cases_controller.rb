# CRUD do conjunto de casos de um assistente (bloco 6.02).
class Api::V1::Accounts::Captain::EvalCasesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization
  before_action :set_assistant
  before_action :set_eval_case, only: [:update, :destroy]

  def index
    @eval_cases = @assistant.eval_cases.ordenados
  end

  def create
    @eval_case = @assistant.eval_cases.new(eval_case_params.merge(account_id: Current.account.id))
    @eval_case.save!
    render :show
  end

  def update
    @eval_case.update!(eval_case_params)
    render :show
  end

  def destroy
    @eval_case.destroy!
    head :no_content
  end

  private

  def set_assistant
    @assistant = Current.account.captain_assistants.find(params[:assistant_id])
  end

  def set_eval_case
    @eval_case = @assistant.eval_cases.find(params[:id])
  end

  def eval_case_params
    params.require(:eval_case).permit(
      :titulo, :ativo, :posicao, mensagens: [:role, :content], expectativas: {}
    )
  end

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.user&.administrator?
  end
end
