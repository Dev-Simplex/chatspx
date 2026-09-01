class Api::V1::Accounts::AgentsController < Api::V1::Accounts::BaseController
  before_action :fetch_agent, except: [:create, :index, :bulk_create]
  before_action :check_authorization
  before_action :authorize_supervision_change, only: [:update]
  before_action :authorize_supervisor_update, only: [:update]
  before_action :validate_limit, only: [:create]
  before_action :validate_limit_for_bulk_create, only: [:bulk_create]

  def index
    # Devolve a conta inteira para TODO MUNDO, como sempre foi (UserPolicy#index? é
    # `true` para qualquer agente — este endpoint nunca foi controle de segurança).
    # T4: não recorte aqui. Esta resposta alimenta a store `agents` do dashboard
    # inteiro (participantes da conversa, menções do chat interno, Kanban, filtro de
    # responsável da lista); estreitá-la para o supervisor tirava gente dessas telas,
    # e um supervisor de time sem membros ficava com a lista VAZIA em todas elas.
    # O recorte de "agentes dos meus times" é da TELA de Agentes e mora no front
    # (settings/agents/Index.vue), que cruza `team_ids` com os times supervisionados.
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
    @agent.current_account_user.update!(account_user_payload)
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

  # O papel vindo desta tela é escolha deliberada de cargo, então entra por
  # `console_role=` — que LIGA e DESLIGA a marca de supervisor. O writer cru
  # (`role=`) só liga, para que API de plataforma, SAML e scripts não rebaixem um
  # supervisor sem querer.
  def account_user_payload
    payload = agent_params.slice(*account_user_attributes).compact
    role = payload.delete(:role)
    payload[:console_role] = role if role.present?
    payload
  end

  # D7: marcar supervisor é exclusivo de admin. O endpoint já é admin-only pela
  # UserPolicy#update?, mas a guarda explícita impede que um afrouxamento futuro da
  # política (custom_role com agent_manage, p.ex.) deixe um agente se autopromover.
  # Roda como before_action para barrar ANTES de qualquer escrita no agente.
  def authorize_supervision_change
    return if supervised_team_ids_param.nil? && !supervisor_role_requested?

    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end

  # `role: supervisor` grava o CARGO (AccountUser#role=), então precisa da mesma guarda
  # que a lista de times: só administrador promove alguém a supervisor.
  def supervisor_role_requested?
    params.dig(:agent, :role).to_s == AccountUser::SUPERVISOR_ROLE
  end

  # T1: com a UserPolicy#update? afrouxada para deixar o supervisor entrar, TUDO o que
  # limita o que ele pode fazer mora aqui. Três recusas, todas antes de qualquer
  # escrita:
  #   1. chave diferente de `name` (role/availability/custom_role_id/...) → seria troca
  #      de função/disponibilidade, que ele não tem;
  #   2. alvo fora dos times supervisionados → renomear quem ele nem enxerga;
  #   3. alvo administrador → um supervisor jamais edita quem está acima dele.
  # Admin não passa por nada disso (caminho idêntico ao de antes).
  def authorize_supervisor_update
    return unless supervisor_scope?

    raise Pundit::NotAuthorizedError if forbidden_supervisor_keys.any?
    raise Pundit::NotAuthorizedError unless manageable_agent_ids.include?(@agent.id)
    raise Pundit::NotAuthorizedError if @agent.administrator?
  end

  # Whitelist de uma chave só. Olhamos o hash aninhado (o ParamsWrapper copia o corpo
  # inteiro para `agent`, porque não existe modelo `Agent`) e ainda o `custom_role_id`
  # de topo, que é de onde o módulo enterprise o lê.
  def forbidden_supervisor_keys
    submitted = params[:agent].present? ? params[:agent].keys.map(&:to_s) : []
    submitted |= ['custom_role_id'] if params.key?(:custom_role_id)

    submitted - ['name']
  end

  # "Este request é de um supervisor puro?" — admin e quem não supervisiona nada
  # respondem `false` e passam pelo caminho de sempre (D5: inerte enquanto ninguém
  # for marcado supervisor).
  def supervisor_scope?
    return false if Current.account_user&.administrator?

    TeamSupervision.supervisor?(current_user, Current.account)
  end

  def manageable_agent_ids
    @manageable_agent_ids ||= TeamSupervision.manageable_agent_ids(current_user, Current.account)
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
