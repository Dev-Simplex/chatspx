# frozen_string_literal: true

class PrivateChat::TokenService < BaseTokenService
  EXPIRY_HOURS = 24

  class << self
    def encode(account_id:, user_id:, conversation_id:)
      payload = {
        account_id: account_id,
        user_id: user_id,
        conversation_id: conversation_id,
        exp: EXPIRY_HOURS.hours.from_now.to_i,
        iat: Time.zone.now.to_i
      }
      new(payload: payload).generate_token
    end

    def decode(token)
      return {} if token.blank?

      new(token: token).decode_token
    end
  end
end
