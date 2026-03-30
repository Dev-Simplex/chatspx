class MacrosExecutionJob < ApplicationJob
  queue_as :medium

  def perform(macro_id, conversation_ids:, user_id:)
    return unless (macro = Macro.find_by(id: macro_id))
    return unless (user = User.find_by(id: user_id))

    account = macro.account
    conversations = account.conversations.where(display_id: conversation_ids.to_a)

    return if conversations.blank?

    conversations.each do |conversation|
      ::Macros::ExecutionService.new(macro, conversation, user).perform
    end
  end
end
