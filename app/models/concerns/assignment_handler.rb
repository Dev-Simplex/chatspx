module AssignmentHandler
  extend ActiveSupport::Concern
  include Events::Types

  included do
    before_save :ensure_assignee_is_from_team
    before_save :set_assignee_last_changed_at
    after_update :record_assignment_change_for_notify
    after_commit :notify_assignment_change, :process_assignment_changes, :mark_conversation_unread_on_assignment_change
  end

  private

  def ensure_assignee_is_from_team
    if team_id_changed?
      validate_current_assignee_team
      # NÃO auto-atribuir humano do time quando o espelho captain é dono (A2b, triagem D-6:
      # team + espelho na mesma automação — preserva a invariante de exclusividade).
      # F1 (modo FILA): handoff "pull" da IA solta a conversa na fila do time — não pode
      # auto-atribuir humano nesta troca de time (skip_auto_assignment setado pelo HandoffTool).
      self.assignee ||= find_assignee_from_team if assignee_agent_bot_id.blank? && !skip_auto_assignment
    elsif will_save_change_to_assignee_id? && assignee_id.present?
      sync_team_from_assignee
    end
  end

  def sync_team_from_assignee
    agent = User.find_by(id: assignee_id)
    return unless agent

    agent_teams = agent.teams.where(account_id: account_id)
    count = agent_teams.count

    return if count.zero?

    if count == 1
      self.team_id = agent_teams.first.id
    elsif agent_teams.where(id: team_id).none?
      self.team_id = nil
    end
  end

  def set_assignee_last_changed_at
    return unless will_save_change_to_assignee_id? || will_save_change_to_assignee_agent_bot_id?

    self.assignee_last_changed_at = (Time.current if assignee_id.present? && assignee_agent_bot_id.blank?)
  end

  def validate_current_assignee_team
    self.assignee_id = nil if team&.members&.exclude?(assignee)
  end

  def find_assignee_from_team
    return if team&.allow_auto_assign.blank?

    team_members_with_capacity = inbox.member_ids_with_assignment_capacity & team.members.ids
    ::AutoAssignment::AgentAssignmentService.new(conversation: self, allowed_agent_ids: team_members_with_capacity).find_assignee
  end

  # ADITIVO: mantem o predicado original E aceita o flag, entao nenhum evento que ja disparava deixa
  # de disparar — so acrescenta o caso que se perdia. saved_change_to_* roda aqui no after_COMMIT, que
  # reflete apenas o ULTIMO save da transacao: o flow troca o time e salva a conversa de novo na mesma
  # transacao, o 2o save zera saved_change_to_team_id? e TEAM_CHANGED nunca era despachado — a UI do
  # agente ficava no time antigo ate dar F5. Mesma armadilha documentada em #update_messages_team_id.
  def notify_assignment_change
    {
      ASSIGNEE_CHANGED => -> { saved_change_to_assignee_id? || @assignee_changed_for_notify },
      TEAM_CHANGED => -> { saved_change_to_team_id? || @team_changed_for_notify }
    }.each do |event, condition|
      condition.call && dispatcher_dispatch(event, previous_changes, assignment_change_event_data(event))
    end
  ensure
    # Uso unico: o flag nao pode sobreviver para um proximo commit da mesma instancia.
    @assignee_changed_for_notify = false
    @team_changed_for_notify = false
  end

  # Captura no after_UPDATE (roda a cada save) e sobrevive ate o commit. Flags proprios, para nao
  # interferir no @team_id_changed_for_retag que o Conversation ja consome no seu after_commit.
  def record_assignment_change_for_notify
    @assignee_changed_for_notify = true if saved_change_to_assignee_id?
    @team_changed_for_notify = true if saved_change_to_team_id?
  end

  # D4 (D-9): NotificationListener roda no async dispatcher (EventDispatcherJob/Sidekiq), onde
  # Current.user é NIL — não há server_middleware que rehidrate Current. A identidade do ator que
  # executou a (re)atribuição precisa ser CAPTURADA aqui, no contexto sync (Current.user presente),
  # e propagada pelo event data. Sem isso o guard "auto-desatribuição não notifica" morre no worker.
  # Gated pela flag (AD-15/OQ-D2): contas Clássico não pagam o custo nem mudam de comportamento.
  # `assignee_changed_by` NAO e mais gated pela reply_assignment_gate: alem da notificacao de
  # takeover (que tem portao PROPRIO em NotificationListener#notify_previous_assignee), este ator e
  # o UNICO sinal que prova "um humano de carne e osso reatribuiu" para o
  # AutomationRuleListener#human_assignment_takeover?, que decide se cancela o menu do bot em
  # espera. `performed_by` (= Current.executed_by) nao serve: so a automacao o preenche, entao
  # prova AUTOMACAO e nunca prova HUMANO. Com o gate aqui, as contas que rodam o motor de flows
  # (Catatau e AGN, ambas com a flag DESLIGADA) nunca veriam ator nenhum e a atribuicao humana
  # deixaria de encerrar o menu — perdendo o proposito da guarda. Fora do ASSIGNEE_CHANGED segue {}.
  def assignment_change_event_data(event)
    return {} unless event == ASSIGNEE_CHANGED

    { assignee_changed_by: Current.user }
  end

  def process_assignment_changes
    process_assignment_activities
    # Rastreio estruturado de "quem atribuiu pra quem" (Relatório de Atribuições).
    # Best-effort: o service tem rescue próprio e nunca quebra a atribuição.
    Conversations::AssignmentHistoryService.new(self).record_change! if saved_change_to_assignee_id?
  end

  def mark_conversation_unread_on_assignment_change
    return unless saved_change_to_assignee_id? || saved_change_to_team_id?

    mark_as_unread!
  end

  def process_assignment_activities
    user_name = Current.user.name if Current.user.present?
    if saved_change_to_team_id?
      create_team_change_activity(user_name)
    elsif saved_change_to_assignee_id?
      create_assignee_change_activity(user_name)
    end
  end

  def self_assign?(assignee_id)
    assignee_id.present? && Current.user&.id == assignee_id
  end
end
