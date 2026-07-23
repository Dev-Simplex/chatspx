class Conversations::ToggleStatusService
  include DateRangeHelper

  pattr_initialize [:conversation!, :params!, :user!]

  def perform
    validate_assignment_requirement!
    validate_team_requirement!

    if pending_to_open_by_bot?
      @conversation.bot_handoff!
    elsif @params[:status].present?
      set_conversation_status
      @conversation.save!
    else
      @conversation.toggle_status
    end

    assign_conversation if should_assign_conversation?
    @conversation
  end

  private

  def validate_team_requirement!
    return unless @params[:status] == 'resolved' && @conversation.team_id.blank?

    raise Conversations::ToggleStatusService::TeamRequiredError
  end

  # "Atribuição obrigatória" mode: a human can only resolve a conversation they are
  # assigned to. Automations, macros and bots bypass this (they never pass a User here
  # via this code path — only the controller's manual toggle_status does).
  def validate_assignment_requirement!
    return unless resolving?
    return unless @user.is_a?(User)
    return unless @conversation.account.resolve_assignment_gate_enabled?
    return if @conversation.assignee_id == @user.id

    raise Conversations::ToggleStatusService::ResolveAssignmentRequiredError, @conversation
  end

  # True when this call would land the conversation in `resolved`, covering both
  # the explicit `status: 'resolved'` path and the param-less toggle that flips an
  # open conversation to resolved (so the gate can't be bypassed via the API).
  def resolving?
    return true if @params[:status] == 'resolved'

    @params[:status].blank? && @conversation.open?
  end

  def pending_to_open_by_bot?
    return false unless @user.is_a?(AgentBot)

    @conversation.status == 'pending' && @params[:status] == 'open'
  end

  def should_assign_conversation?
    @conversation.status == 'open' && @user.is_a?(User) && @user.agent?
  end

  def set_conversation_status
    @conversation.status = @params[:status]
    @conversation.snoozed_until = parse_date_time(@params[:snoozed_until].to_s) if @params[:snoozed_until]
  end

  def assign_conversation
    @conversation.update!(assignee: @user)
  end

  class TeamRequiredError < StandardError
    def message
      I18n.t('conversations.errors.team_required_for_resolution')
    end
  end

  class ResolveAssignmentRequiredError < StandardError
    attr_reader :conversation

    def initialize(conversation)
      @conversation = conversation
      super(I18n.t('conversations.errors.resolve_assignment_required'))
    end

    # Metadata the frontend uses to render the right "Assign to you and resolve?" variant.
    def meta
      assignee = @conversation.assignee
      {
        current_assignee_id: assignee&.id,
        current_assignee_name: assignee&.available_name,
        team_id: @conversation.team_id
      }
    end
  end
end
