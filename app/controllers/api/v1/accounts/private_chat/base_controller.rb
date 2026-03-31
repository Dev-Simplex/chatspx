# frozen_string_literal: true

class Api::V1::Accounts::PrivateChat::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_private_chat_enabled
  before_action :authenticate_private_chat_token
  before_action :set_private_chat_conversation

  private

  def ensure_private_chat_enabled
    return if PrivateChat::Config.enabled?

    render json: { error: 'Not found' }, status: :not_found
  end

  def authenticate_private_chat_token
    token = request.headers['Authorization']&.sub(/\ABearer\s+/i, '')
    payload = PrivateChat::TokenService.decode(token)

    if payload.blank? || payload[:conversation_id].to_i != PrivateChat::Config.conversation_id
      render json: { error: 'Unauthorized' }, status: :unauthorized
      return
    end

    # Optional: ensure account_id in token matches current account
    if PrivateChat::Config.account_id.present? && payload[:account_id].to_i != Current.account.id
      render json: { error: 'Not found' }, status: :not_found
      return
    end

    @private_chat_payload = payload
  end

  def set_private_chat_conversation
    @conversation = Current.account.conversations.find(PrivateChat::Config.conversation_id)
  end
end
