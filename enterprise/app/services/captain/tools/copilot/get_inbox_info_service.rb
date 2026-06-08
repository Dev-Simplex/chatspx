class Captain::Tools::Copilot::GetInboxInfoService < Captain::Tools::BaseTool
  def self.name
    'get_inbox_info'
  end
  description 'Get inbox configuration, assigned agents, and queue size'

  param :inbox_id, type: :integer, desc: 'ID of the inbox (optional - lists all if empty)'

  def execute(inbox_id: nil)
    account = @assistant.account

    if inbox_id.present?
      inbox = account.inboxes.find_by(id: inbox_id)
      return 'Inbox not found' if inbox.blank?

      format_inbox(inbox)
    else
      inboxes = account.inboxes.includes(:inbox_members).limit(20)
      return 'No inboxes found' if inboxes.empty?

      inboxes.map { |i| format_inbox(i) }.join("\n---\n")
    end
  end

  def active?
    user_has_permission('administrator')
  end

  private

  def format_inbox(inbox)
    queue = inbox.conversations.where(status: :open).count
    agents = inbox.inbox_members.includes(:user).map { |m| m.user.name }.join(', ')

    <<~INFO
      Inbox: #{inbox.name} (ID: #{inbox.id})
      Type: #{inbox.channel_type}
      Queue: #{queue} open conversations
      Agents: #{agents.presence || 'none'}
    INFO
  end
end
