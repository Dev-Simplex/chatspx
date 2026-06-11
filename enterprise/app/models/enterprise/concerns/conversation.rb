module Enterprise::Concerns::Conversation
  extend ActiveSupport::Concern

  included do
    belongs_to :sla_policy, optional: true
    has_one :applied_sla, dependent: :destroy_async
    has_many :sla_events, dependent: :destroy_async
    has_many :captain_responses, class_name: 'Captain::AssistantResponse', dependent: :nullify, as: :documentable
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
  end

  private

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

  def validate_sla_policy
    # TODO: remove these validations once we figure out how to deal with these cases
    if sla_policy_id.nil? && changes[:sla_policy_id].first.present?
      errors.add(:sla_policy, 'cannot remove sla policy from conversation')
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
