# frozen_string_literal: true

class PrivateChat::Config
  # Configuration via environment variables only.
  # After running `rake private_chat:setup`, set these ENV vars:
  #   PRIVATE_CHAT_PASSWORD, PRIVATE_CHAT_ACCOUNT_ID,
  #   PRIVATE_CHAT_CONVERSATION_ID, PRIVATE_CHAT_INBOX_ID

  class << self
    def enabled?
      conversation_id.present? && password.present?
    end

    def conversation_id
      return @conversation_id if defined?(@conversation_id)

      @conversation_id = ENV['PRIVATE_CHAT_CONVERSATION_ID']&.to_i&.nonzero?
    end

    def inbox_id
      return @inbox_id if defined?(@inbox_id)

      @inbox_id = ENV['PRIVATE_CHAT_INBOX_ID']&.to_i&.nonzero?
    end

    def password
      ENV.fetch('PRIVATE_CHAT_PASSWORD', nil)
    end

    def account_id
      return @account_id if defined?(@account_id)

      @account_id = ENV['PRIVATE_CHAT_ACCOUNT_ID']&.to_i&.nonzero?
    end

    def valid_password?(input)
      return false if password.blank?

      ActiveSupport::SecurityUtils.secure_compare(input.to_s, password)
    end
  end
end
