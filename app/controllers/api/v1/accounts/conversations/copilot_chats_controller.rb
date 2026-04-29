class Api::V1::Accounts::Conversations::CopilotChatsController < Api::V1::Accounts::Conversations::BaseController
  HISTORY_LIMIT = 50

  def show
    render json: { history: history }
  end

  def create
    user_messages = sanitize_messages(params[:messages] || [])
    detected_language = Copilot::LanguageDetectorService.new(
      conversation: @conversation, account: Current.account
    ).perform

    reply = Copilot::ChatService.new(
      conversation: @conversation,
      user_messages: user_messages,
      account: Current.account,
      language: detected_language
    ).perform

    persist_history(user_messages, reply) if reply.present?
    render json: { reply: reply, language: detected_language }
  end

  def destroy
    @conversation.additional_attributes['copilot_history'] = []
    @conversation.save!
    render json: { ok: true }
  end

  private

  def sanitize_messages(list)
    Array(list).map do |m|
      role = m['role'].to_s
      role = 'user' unless %w[user assistant].include?(role)
      { 'role' => role, 'content' => m['content'].to_s }
    end
  end

  def history
    Array(@conversation.additional_attributes['copilot_history'])
  end

  def persist_history(user_messages, reply)
    last_user = user_messages.last
    return if last_user.blank?

    new_history = (history + [last_user, { 'role' => 'assistant', 'content' => reply }]).last(HISTORY_LIMIT)
    @conversation.additional_attributes['copilot_history'] = new_history
    @conversation.save!
  end
end
