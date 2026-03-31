class Conversations::ToggleStatusService
  include DateRangeHelper

  pattr_initialize [:conversation!, :params!, :user!]

  def perform
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
end
