module Enterprise::Concerns::Conversation
  extend ActiveSupport::Concern

  included do
    belongs_to :sla_policy, optional: true
    has_one :applied_sla, dependent: :destroy_async
    has_many :sla_events, dependent: :destroy_async
    has_many :captain_responses, class_name: 'Captain::AssistantResponse', dependent: :nullify, as: :documentable
    has_many :captain_faq_observations, class_name: 'Captain::FaqObservation', dependent: :delete_all
    scope :with_sla_applicable_contact, -> { left_joins(:contact).where(contacts: { blocked: [false, nil] }) }

    before_validation :validate_sla_policy, if: -> { sla_policy_id_changed? }
    around_save :ensure_applied_sla_is_created, if: -> { sla_policy_id_changed? }
    # A2e: resolver a conversa LIMPA o dono-espelho captain (reopen nasce sem dono ->
    # triagem re-atribui). Snooze NÃO limpa; bot webhook e assignee humano preservam
    # a regra atual do Chatwoot.
    before_save :release_captain_mirror_on_resolve, if: -> { status_changed? && resolved? }
    # A2d: quando o espelho captain é SETADO (nil/humano/outro espelho -> este espelho),
    # cutuca o pipeline para que a IA responda o incoming pendente já no 1º turno
    # (triagem assíncrona) e na transferência IA->IA. Desatribuição não dispara
    # (valor ausente); a resposta da IA não muda o dono -> sem loop.
    after_commit :kick_captain_pipeline_after_mirror_assignment
    # E4 (DD-11): trilha de auditoria da virada no AssistantLog. O assistant do release é
    # capturado pelo valor ANTIGO do saved_change (captain_assistant_id é NOT NULL no espelho);
    # after_commit para nunca logar transação que sofre rollback. A2c sinaliza o motivo via
    # captain_release_reason ('human_reply') antes do update!.
    attr_accessor :captain_release_reason

    after_commit :log_captain_mirror_transition, if: -> { saved_change_to_assignee_agent_bot_id? }
    # Modelo A (D-12): o "aguardando humano" do handoff termina quando um humano se
    # engaja DE FATO — assumiu a conversa (atribuição limpa o espelho), respondeu sem
    # assumir (A2c, reason human_reply) — ou quando a conversa resolve (saiu da fila).
    after_commit :clear_awaiting_human_marker, if: -> { awaiting_human_clearable? }
    # Gêmeo do awaiting_human para a fila "Aguardando encerramento": some da fila quando um
    # humano assume, o CLIENTE volta a falar (waiting_since repopulado no incoming) ou a
    # conversa resolve. Não limpa quando a própria IA responde (a nota de encerramento não
    # tira a conversa da fila).
    after_commit :clear_awaiting_closure_marker, if: -> { awaiting_closure_clearable? }
  end

  def sla_applicable?
    !contact&.blocked?
  end

  private

  def awaiting_human_clearable?
    return false unless (custom_attributes || {}).key?('aguardando_humano_desde')

    awaiting_human_assumed? || awaiting_human_replied? || (saved_change_to_status? && resolved?)
  end

  def awaiting_human_assumed?
    saved_change_to_assignee_id? && assignee_id.present?
  end

  def awaiting_human_replied?
    saved_change_to_assignee_agent_bot_id? && assignee_agent_bot_id.blank? && captain_release_reason == 'human_reply'
  end

  def clear_awaiting_human_marker
    # update_columns: um update! aqui resetaria o saved_changes DENTRO do mesmo ciclo de
    # after_commit e engoliria o log de auditoria da transição (log_captain_mirror_transition).
    update_columns(custom_attributes: (custom_attributes || {}).except('aguardando_humano_desde')) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn("[Captain] limpa aguardando_humano conv=#{id}: #{e.message}")
  end

  def awaiting_closure_clearable?
    attrs = custom_attributes || {}
    return false unless attrs.key?('aguardando_encerramento_desde') || attrs.key?('encerramento_avisado_em')

    awaiting_human_assumed? || awaiting_closure_customer_returned? || (saved_change_to_status? && resolved?)
  end

  # Cliente voltou a falar: o incoming repopula waiting_since (nil -> presente) na conversa
  # que estava parada (a IA havia respondido por último). A IA retoma via pipeline normal.
  def awaiting_closure_customer_returned?
    saved_change_to_waiting_since? && waiting_since.present?
  end

  def clear_awaiting_closure_marker
    keys = %w[aguardando_encerramento_desde encerramento_avisado_em encerramento_classe]
    update_columns(custom_attributes: (custom_attributes || {}).except(*keys)) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn("[Captain] limpa aguardando_encerramento conv=#{id}: #{e.message}")
  end

  def kick_captain_pipeline_after_mirror_assignment
    return unless saved_change_to_assignee_agent_bot_id? && assignee_agent_bot_id.present?
    return unless assignee_agent_bot&.captain? # espelho->humano/bot webhook não cutuca

    Captain::Conversation::AssignmentKickJob.perform_later(self)
  end

  def release_captain_mirror_on_resolve
    return if assignee_agent_bot_id.blank?
    return unless assignee_agent_bot&.captain? # bot webhook preserva comportamento atual

    self.assignee_agent_bot_id = nil
  end

  # E4: trilha de auditoria da virada — quem (IA) assumiu/soltou cada conversa e por quê.
  def log_captain_mirror_transition
    old_id, new_id = saved_change_to_assignee_agent_bot_id
    log_mirror_event(new_id, 'mirror_assigned', { previous_agent_bot_id: old_id }) if new_id.present?
    return unless old_id.present? && new_id.blank?

    event, reason = captain_release_event_and_reason
    log_mirror_event(old_id, event, { reason: reason, new_assignee_id: assignee_id })
  end

  def captain_release_event_and_reason
    return %w[mirror_released resolve] if saved_change_to_status? && resolved?   # A2e
    return %w[human_takeover assignment] if assignee_id.present?                 # reset core / dialog D2
    return %w[human_takeover reply] if captain_release_reason == 'human_reply'   # A2c

    %w[mirror_released unassigned]                                               # automação/None
  end

  def log_mirror_event(agent_bot_id, event_type, payload)
    assistant = AgentBot.find_by(id: agent_bot_id)&.captain_assistant
    return if assistant.blank? # bot webhook / espelho órfão: fora da telemetria captain

    Captain::AssistantLog.create!(captain_assistant: assistant, conversation: self,
                                  event_type: event_type, payload: payload)
  rescue StandardError => e
    Rails.logger.warn("[Captain] assistant_log de atribuição falhou: #{e.message}")
  end

  def validate_sla_policy
    # TODO: remove these validations once we figure out how to deal with these cases
    if sla_policy_id.nil? && changes[:sla_policy_id].first.present?
      errors.add(:sla_policy, 'cannot remove sla policy from conversation')
      return
    end

    unless sla_applicable?
      errors.add(:sla_policy, 'cannot be assigned to conversations with blocked contacts')
      return
    end

    if changes[:sla_policy_id].first.present?
      errors.add(:sla_policy, 'conversation already has a different sla')
      return
    end

    errors.add(:sla_policy, 'sla policy account mismatch') if sla_policy&.account_id != account_id
  end

  # handling inside a transaction to ensure applied sla record is also created
  def ensure_applied_sla_is_created
    ActiveRecord::Base.transaction do
      yield
      create_applied_sla(sla_policy_id: sla_policy_id) if applied_sla.blank?
    end
  rescue ActiveRecord::RecordInvalid
    raise ActiveRecord::Rollback
  end
end
