class Api::V1::Accounts::AgentsController < Api::V1::Accounts::BaseController
  before_action :fetch_agent, except: [:create, :index, :bulk_create]
  before_action :check_authorization
  before_action :authorize_supervision_change, only: [:update]
  before_action :validate_limit, only: [:create]
  before_action :validate_limit_for_bulk_create, only: [:bulk_create]

  def index
    @agents = agents
  end

  def create
    builder = AgentBuilder.new(
      email: new_agent_params['email'],
      name: new_agent_params['name'],
      role: new_agent_params['role'],
      availability: new_agent_params['availability'],
      auto_offline: new_agent_params['auto_offline'],
      inviter: current_user,
      account: Current.account
    )

    @agent = builder.perform
  end

  def update
    @agent.update!(agent_params.slice(:name).compact)
    @agent.current_account_user.update!(agent_params.slice(*account_user_attributes).compact)
    sync_supervised_teams
  end

  def destroy
    @agent.current_account_user.destroy!
    delete_user_record(@agent)
    head :ok
  end

  def bulk_create
    emails = params[:emails]

    emails.each do |email|
      builder = AgentBuilder.new(
        email: email,
        name: email.split('@').first,
        inviter: current_user,
        account: Current.account
      )
      begin
        builder.perform
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.info "[Agent#bulk_create] ignoring email #{email}, errors: #{e.record.errors}"
      end
    end

    # This endpoint is used to bulk create agents during onboarding
    # onboarding_step key in present in Current account custom attributes, since this is a one time operation
    Current.account.custom_attributes.delete('onboarding_step')
    Current.account.save!
    head :ok
  end

  private

  def check_authorization
    super(User)
  end

  def fetch_agent
    @agent = agents.find(params[:id])
  end

  def account_user_attributes
    [:role, :availability, :auto_offline]
  end

  # D7: marcar supervisor é exclusivo de admin. O endpoint já é admin-only pela
  # UserPolicy#update?, mas a guarda explícita impede que um afrouxamento futuro da
  # política (custom_role com agent_manage, p.ex.) deixe um agente se autopromover.
  # Roda como before_action para barrar ANTES de qualquer escrita no agente.
  def authorize_supervision_change
    return if supervised_team_ids_param.nil?

    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end

  # Marcação de supervisor (F1). Só no update — o create fica enxuto de propósito.
  # Substitui o conjunto inteiro (diff add/remove) numa transação; ausência da chave
  # significa "não mexa", array vazio significa "não supervisiona mais nada".
  def sync_supervised_teams
    requested_ids = supervised_team_ids_param
    return if requested_ids.nil?

    # ids de times de outra conta são ignorados em silêncio (nunca viram supervisão)
    target_ids = Current.account.teams.where(id: requested_ids).pluck(:id)
    current_ids = @agent.supervised_team_ids_for(Current.account.id)

    ActiveRecord::Base.transaction do
      @agent.team_supervisions.where(team_id: current_ids - target_ids).destroy_all
      (target_ids - current_ids).each { |team_id| @agent.team_supervisions.create!(team_id: team_id) }
    end

    # a resposta ainda vai serializar supervised_team_ids a partir deste mesmo objeto
    @agent.reset_supervised_team_ids_cache
    @agent.association(:supervised_teams).reset
  end

  def supervised_team_ids_param
    params.require(:agent).permit(supervised_team_ids: [])[:supervised_team_ids]
  end

  def allowed_agent_params
    [:name, :email, :role, :availability, :auto_offline]
  end

  def agent_params
    params.require(:agent).permit(allowed_agent_params)
  end

  def new_agent_params
    params.require(:agent).permit(:email, :name, :role, :availability, :auto_offline)
  end

  def agents
    # supervised_teams entra no includes pelo mesmo motivo de :teams — o partial do
    # agente serializa os ids e a listagem inteira viraria N+1 sem isso.
    @agents ||= Current.account.users.order_by_full_name.includes(:account_users, :teams, :supervised_teams, { avatar_attachment: [:blob] })
  end

  def validate_limit_for_bulk_create
    limit_available = params[:emails].count <= available_agent_count

    render_payment_required('Account limit exceeded. Please purchase more licenses') unless limit_available
  end

  def validate_limit
    render_payment_required('Account limit exceeded. Please purchase more licenses') unless can_add_agent?
  end

  def available_agent_count
    Current.account.usage_limits[:agents] - agents.count
  end

  def can_add_agent?
    available_agent_count.positive?
  end

  def delete_user_record(agent)
    DeleteObjectJob.perform_later(agent.class.name, agent.id) if agent.reload.account_users.blank?
  end
end

Api::V1::Accounts::AgentsController.prepend_mod_with('Api::V1::Accounts::AgentsController')
