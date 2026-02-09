# frozen_string_literal: true

module PrivateChat
  class Config
    # Valores padrão (podem ser sobrescritos por variáveis de ambiente).
    # Após rodar `rake private_chat:setup`, preencha CONVERSATION_ID e INBOX_ID
    # com os IDs impressos no terminal.
    HARDCODED_PASSWORD = '090725'
    HARDCODED_ACCOUNT_ID = 6
    HARDCODED_CONVERSATION_ID = 19314
    HARDCODED_INBOX_ID = 93

    class << self
      def enabled?
        conversation_id.present? && password.present?
      end

      def conversation_id
        return @conversation_id if defined?(@conversation_id)

        env_val = ENV['PRIVATE_CHAT_CONVERSATION_ID']&.to_i
        hard_val = HARDCODED_CONVERSATION_ID&.to_i
        @conversation_id = env_val&.nonzero? || hard_val&.nonzero?
      end

      def inbox_id
        return @inbox_id if defined?(@inbox_id)

        env_val = ENV['PRIVATE_CHAT_INBOX_ID']&.to_i
        hard_val = HARDCODED_INBOX_ID&.to_i
        @inbox_id = env_val&.nonzero? || hard_val&.nonzero?
      end

      # Hardcoded tem prioridade; ENV só é usado se não houver valor no código
      def password
        HARDCODED_PASSWORD.presence || ENV['PRIVATE_CHAT_PASSWORD']
      end

      def account_id
        return @account_id if defined?(@account_id)

        env_val = ENV['PRIVATE_CHAT_ACCOUNT_ID']&.to_i
        hard_val = HARDCODED_ACCOUNT_ID&.to_i
        id = env_val&.nonzero? || hard_val&.nonzero?
        @account_id = id.presence
      end

      def valid_password?(input)
        return false if password.blank?

        ActiveSupport::SecurityUtils.secure_compare(input.to_s, password)
      end
    end
  end
end
