class Api::V1::Accounts::TeamMembersController < Api::V1::Accounts::BaseController
  before_action :fetch_team
  before_action :check_authorization
  before_action :authorize_supervisor_membership_change, only: [:create, :update, :destroy]
  before_action :validate_member_id_params, only: [:create, :update, :destroy]

  def index
    @team_members = @team.team_members.includes(user: { avatar_attachment: :blob }).map(&:user)
  end

  def create
    ActiveRecord::Base.transaction do
      @team_members = @team.add_members(members_to_be_added_ids)
    end
  end

  def update
    ActiveRecord::Base.transaction do
      @team.add_members(members_to_be_added_ids)
      @team.remove_members(members_to_be_removed_ids)
    end
    @team_members = @team.members
    render action: 'create'
  end

  def destroy
    ActiveRecord::Base.transaction do
      @team.remove_members(params[:user_ids])
    end
    head :ok
  end

  private

  # T1: com a TeamMemberPolicy afrouxada para deixar o supervisor entrar, é aqui que o
  # alcance dele é fechado:
  #   1. só mexe na composição de time que ELE supervisiona — senão ele se adicionaria a
  #      qualquer time e passaria a enxergar as conversas dele;
  #   2. quem ENTRA tem que estar no pool (membros dos times supervisionados) — trazer
  #      alguém de fora é dar acesso novo a quem ele não gerencia.
  # Remover não tem restrição de pool: tirar do time supervisionado é sempre permitido.
  # Admin não passa por nada disso (caminho idêntico ao de antes).
  def authorize_supervisor_membership_change
    return if Current.account_user&.administrator?
    raise Pundit::NotAuthorizedError unless TeamSupervision.supervises?(current_user, @team.id, Current.account)

    return if action_name == 'destroy'

    pool = TeamSupervision.manageable_agent_ids(current_user, Current.account)
    raise Pundit::NotAuthorizedError if (incoming_member_ids - current_members_ids - pool).any?
  end

  # Os ids que este request quer ADICIONAR. Normalizado para inteiro porque o corpo pode
  # chegar com strings (form-encoded) e o pool vem do banco.
  def incoming_member_ids
    Array(params[:user_ids]).map(&:to_i)
  end

  def members_to_be_added_ids
    params[:user_ids] - current_members_ids
  end

  def members_to_be_removed_ids
    current_members_ids - params[:user_ids]
  end

  def current_members_ids
    @current_members_ids ||= @team.members.pluck(:id)
  end

  def fetch_team
    @team = Current.account.teams.find(params[:team_id])
  end

  def validate_member_id_params
    invalid_ids = params[:user_ids].map(&:to_i) - @team.account.user_ids

    render json: { error: 'Invalid User IDs' }, status: :unauthorized and return if invalid_ids.present?
  end
end
