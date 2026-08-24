# == Schema Information
#
# Table name: account_users
#
#  id                       :bigint           not null, primary key
#  active_at                :datetime
#  auto_offline             :boolean          default(TRUE), not null
#  availability             :integer          default("online"), not null
#  role                     :integer          default("agent")
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint
#  agent_capacity_policy_id :bigint
#  custom_role_id           :bigint
#  inviter_id               :bigint
#  user_id                  :bigint
#
# Indexes
#
#  index_account_users_on_account_id                (account_id)
#  index_account_users_on_agent_capacity_policy_id  (agent_capacity_policy_id)
#  index_account_users_on_custom_role_id            (custom_role_id)
#  index_account_users_on_user_id                   (user_id)
#  uniq_user_id_per_account_id                      (account_id,user_id) UNIQUE
#

class AccountUser < ApplicationRecord
  include AvailabilityStatusable

  belongs_to :account
  belongs_to :user
  belongs_to :inviter, class_name: 'User', optional: true

  enum role: { agent: 0, administrator: 1 }
  enum availability: { online: 0, offline: 1, busy: 2 }

  # "Supervisor" NÃO é um papel no banco: é AGENTE com linha em team_supervisors.
  # A tela de Agentes já expõe essa combinação como uma função só (EditAgent.vue);
  # o par console_role/supervised_team_ids dá a MESMA opção ao Console de Super
  # Admin. Um terceiro valor no enum faria `agent?` devolver false e derrubaria as
  # 37 checagens espalhadas por policies e controllers — por isso a opção vive na
  # camada de apresentação, não no enum.
  SUPERVISOR_ROLE = 'supervisor'.freeze
  CONSOLE_ROLES = (roles.keys + [SUPERVISOR_ROLE]).freeze

  accepts_nested_attributes_for :account

  after_create_commit :notify_creation, :create_notification_setting
  after_destroy :notify_deletion, :remove_user_from_account
  after_save :update_presence_in_redis, if: :saved_change_to_availability?
  after_save :sync_supervised_teams
  after_commit :invalidate_admin_tokens_cache, if: -> { saved_change_to_role? || destroyed? || previously_new_record? }
  # Virar administrador tira a pessoa da lista de participantes do isolamento (só agentes
  # entram lá), então a exceção que ela tinha some da tela e ninguém consegue mais removê-la.
  # A guarda de leitura (User#fetch_isolation_exempt_inbox_ids) já a torna inofensiva; isto
  # aqui apaga a linha para ela não voltar a valer calada numa eventual despromoção.
  after_commit :purge_isolation_exemptions, if: -> { saved_change_to_role? && administrator? }

  validates :user_id, uniqueness: { scope: :account_id }

  # Papel como o console mostra: 'supervisor' quando é agente que supervisiona time.
  def console_role
    agent? && supervised_team_ids.any? ? SUPERVISOR_ROLE : role
  end

  # Um ponto só entende "supervisor", e com isso TODA superfície que atribui papel
  # passa a aceitá-lo: Console de Super Admin, API de agentes (create e update),
  # API de plataforma, seeds e console do Rails. Antes, qualquer uma delas levantava
  # ArgumentError e virava 500 — este writer é aditivo, só transforma o que já
  # explodia em atribuição válida, sem tocar em 'agent'/'administrator'.
  #
  # Grava `agent`: supervisionar é ter linha em team_supervisors, e é `supervised_team_ids`
  # que diz quais times. Sem times informados, a supervisão passa a valer para todos
  # os da conta (ver sync_supervised_teams).
  def role=(value)
    if value.to_s == SUPERVISOR_ROLE
      @console_supervisor = true
      super(:agent)
    else
      super
    end
  end

  # O formulário do console posta este nome; a tradução é a mesma do writer acima.
  # Escolher "administrator" ou "agent" NÃO mexe na supervisão: quem quiser tirá-la
  # esvazia o campo de times, que é onde ela mora.
  def console_role=(value)
    self.role = value
  end

  # Times DESTA conta que o usuário supervisiona. Enquanto o formulário não gravar,
  # devolve o que está no banco; depois de atribuir, devolve o pendente.
  def supervised_team_ids
    return @supervised_team_ids if defined?(@supervised_team_ids)
    return [] if user_id.blank? || account_id.blank?

    TeamSupervisor.joins(:team).where(user_id: user_id, teams: { account_id: account_id }).pluck(:team_id)
  end

  def supervised_team_ids=(ids)
    @supervised_team_ids = Array(ids).reject(&:blank?).map(&:to_i)
  end

  def create_notification_setting
    setting = user.notification_settings.new(account_id: account.id)
    setting.selected_email_flags = [:email_conversation_assignment]
    setting.selected_push_flags = default_push_flags
    setting.save!
  end

  # D4: novos usuários nascem com push do takeover (conversation_unassignment) ligado SOMENTE quando
  # o gate da conta está ON. Em contas Clássico (flag OFF) o default permanece o histórico
  # ([:push_conversation_assignment]) — o novo default não vaza para fora da Fase D (AD-15/OQ-D2).
  def default_push_flags
    flags = [:push_conversation_assignment]
    flags << :push_conversation_unassignment if account.reply_assignment_gate_enabled?
    flags
  end

  def remove_user_from_account
    ::Agents::DestroyJob.perform_later(account_id, user_id)
  end

  def permissions
    (administrator? ? ['administrator'] : ['agent']) + supervision_permissions
  end

  # D6: supervisor de time vira uma permissão do front (reusa o `permissions:` das
  # rotas em vez de inventar um sistema paralelo). Inerte quando ninguém supervisiona
  # nada: uma consulta indexada que devolve [] e some.
  def supervision_permissions
    TeamSupervision.supervisor?(user, account_id) ? ['team_supervisor'] : []
  end

  def push_event_data
    {
      id: id,
      availability: availability,
      role: role,
      user_id: user_id
    }
  end

  private

  # Só roda quando o formulário mandou o campo — um save vindo de qualquer outro
  # lugar (availability, papel, convite) não encosta na supervisão. Usa destroy/create
  # em vez de delete_all porque TeamSupervisor invalida o cache de times num
  # after_commit: sem isso a tela do supervisor nasce vazia com a linha já gravada.
  def sync_supervised_teams
    # "supervisor" sem time escolhido acontece no formulário da página do USUÁRIO, onde a
    # conta só é conhecida no submit e a lista de times não existe para escolher. Nesse
    # caso a opção passa a valer para todos os times da conta — dito na tela, para não
    # ser uma concessão silenciosa. Refino por time: Configurações → Agentes.
    @supervised_team_ids = account.teams.pluck(:id) if @console_supervisor && supervised_team_ids.empty?
    return unless defined?(@supervised_team_ids)

    desired = account.teams.where(id: @supervised_team_ids).pluck(:id)
    current = TeamSupervisor.joins(:team).where(user_id: user_id, teams: { account_id: account_id }).pluck(:team_id)

    TeamSupervisor.where(user_id: user_id, team_id: current - desired).destroy_all
    (desired - current).each { |team_id| TeamSupervisor.create!(user_id: user_id, team_id: team_id) }

    remove_instance_variable(:@supervised_team_ids)
    @console_supervisor = false
  end

  def notify_creation
    Rails.configuration.dispatcher.dispatch(AGENT_ADDED, Time.zone.now, account: account)
  end

  def notify_deletion
    Rails.configuration.dispatcher.dispatch(AGENT_REMOVED, Time.zone.now, account: account)
  end

  def update_presence_in_redis
    OnlineStatusTracker.set_status(account.id, user.id, availability)
  end

  def invalidate_admin_tokens_cache
    Rails.cache.delete("account:#{account_id}:admin_pubsub_tokens")
  end

  # Só as caixas DESTA conta: o mesmo usuário pode ser agente isentado em outra conta,
  # e virar administrador aqui não pode mexer no que ele enxerga lá.
  def purge_isolation_exemptions
    InboxIsolationExemption.where(user_id: user_id, inbox_id: Inbox.where(account_id: account_id).select(:id)).destroy_all
  end
end

AccountUser.prepend_mod_with('AccountUser')
AccountUser.include_mod_with('Audit::AccountUser')
AccountUser.include_mod_with('Concerns::AccountUser')
