class Api::V1::Accounts::LabelsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_label, except: [:index, :create]
  before_action :check_authorization, only: [:show, :update, :destroy]
  before_action :validate_team_membership, only: [:create, :update]

  def index
    @labels = Label.with_visibility(current_user)
  end

  def show; end

  def create
    @label = Current.account.labels.create!(permitted_params.merge(created_by: current_user))
  end

  def update
    @label.update!(permitted_params)
  end

  def destroy
    @label.destroy!
    head :ok
  end

  private

  def fetch_label
    @label = Current.account.labels.find(params[:id])
  end

  # Instância, NÃO a classe — senão a policy quebra ao ler @record.created_by_id.
  def check_authorization
    authorize(@label)
  end

  # Só membros do time (ou admin) podem criar/editar etiqueta de-time.
  # Lê o valor EFETIVO (params têm prioridade; update parcial cai no valor atual do @label).
  def validate_team_membership
    return unless effective_visibility.to_s == 'team'
    return if Current.account_user.administrator?

    head :forbidden unless Current.user.teams.exists?(id: effective_team_id)
  end

  def effective_visibility
    params.dig(:label, :visibility) || @label&.visibility
  end

  def effective_team_id
    params.dig(:label, :team_id) || @label&.team_id
  end

  def permitted_params
    params.require(:label).permit(:title, :description, :color, :show_on_sidebar, :visibility, :team_id)
  end
end
