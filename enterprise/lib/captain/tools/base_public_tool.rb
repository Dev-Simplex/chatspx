require 'agents'

class Captain::Tools::BasePublicTool < Agents::Tool
  # Per-account credential resolution (Vista/Google/office/site) with ENV fallback.
  include Captain::Tools::IntegrationCredentials

  # Trace de tool calls (Eval 2.0 F2): prepend na SUBCLASSE (prepend aqui não
  # interceptaria o perform definido nelas).
  def self.inherited(subclass)
    super
    subclass.prepend(Captain::Tools::TraceRecorder)
  end

  def initialize(assistant)
    @assistant = assistant
    super()
  end

  def active?
    # Public tools are always active
    true
  end

  def permissions
    # Override in subclasses to specify required permissions
    # Returns empty array for public tools (no permissions required)
    []
  end

  private

  def account_scoped(model_class)
    model_class.where(account_id: @assistant.account_id)
  end

  def find_conversation(state)
    conversation_id = state&.dig(:conversation, :id)
    return nil unless conversation_id

    account_scoped(::Conversation).find_by(id: conversation_id)
  end

  def find_contact(state)
    contact_id = state&.dig(:contact, :id)
    return nil unless contact_id

    account_scoped(::Contact).find_by(id: contact_id)
  end

  def log_tool_usage(action, details = {})
    Rails.logger.info do
      "#{self.class.name}: #{action} for assistant #{@assistant&.id} - #{details.inspect}"
    end
  end
end
