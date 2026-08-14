class MessageTemplates::Template::OutOfOffice
  pattr_initialize [:conversation!]

  # Gate usado pelos caminhos do Captain (handoff, response builder, resolução de pendentes) —
  # o pipeline normal passa por MessageTemplates::HookExecutionService#should_send_out_of_office_message?.
  # O guard de grupo precisa existir NOS DOIS: sem ele aqui, os 4 chamadores do Captain furariam
  # o freio e o texto de fora-de-horário voltaria a cair dentro do grupo (caso real: conv 12).
  def self.perform_if_applicable(conversation)
    inbox = conversation.inbox
    return unless inbox.out_of_office?
    return if inbox.out_of_office_message.blank?
    return if conversation.group?

    new(conversation: conversation).perform
  end

  def perform
    ActiveRecord::Base.transaction do
      conversation.messages.create!(out_of_office_message_params)
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    true
  end

  private

  delegate :contact, :account, to: :conversation
  delegate :inbox, to: :message

  def out_of_office_message_params
    content = @conversation.inbox&.out_of_office_message

    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :template,
      content: content
    }
  end
end
