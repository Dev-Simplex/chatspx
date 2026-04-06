# frozen_string_literal: true

class PrivateChat::Config
  HARDCODED_PASSWORD = '090725'
  HARDCODED_ACCOUNT_ID = 6
  HARDCODED_CONVERSATION_ID = 19_314
  HARDCODED_INBOX_ID = 93

  class << self
    def enabled?
      conversation_id.present? && password.present?
    end

    def conversation_id
      HARDCODED_CONVERSATION_ID
    end

    def inbox_id
      HARDCODED_INBOX_ID
    end

    def password
      HARDCODED_PASSWORD
    end

    def account_id
      HARDCODED_ACCOUNT_ID
    end

    def valid_password?(input)
      return false if password.blank?

      ActiveSupport::SecurityUtils.secure_compare(input.to_s, password)
    end
  end
end
