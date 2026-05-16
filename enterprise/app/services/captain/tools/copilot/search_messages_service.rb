class Captain::Tools::Copilot::SearchMessagesService < Captain::Tools::BaseTool
  def self.name
    'search_messages'
  end
  description 'Full-text search across messages in the account'

  param :query, type: :string, desc: 'Search query text', required: true
  param :limit, type: :integer, desc: 'Max results to return (default 20)'

  def execute(query:, limit: 20)
    account = @assistant.account
    messages = account.messages
                      .where('content ILIKE ?', "%#{query}%")
                      .order(created_at: :desc)
                      .limit([limit, 50].min)
                      .includes(:conversation)

    return "No messages found for '#{query}'" if messages.empty?

    lines = messages.map do |m|
      conv_id = m.conversation&.display_id
      "[Conv ##{conv_id}] #{m.message_type}: #{m.content.to_s.truncate(200)}"
    end

    "Found #{messages.size} messages for '#{query}':\n#{lines.join("\n")}"
  end

  def active?
    user_has_permission('conversation_manage')
  end
end
