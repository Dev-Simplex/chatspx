# frozen_string_literal: true

module Api::V1::Accounts::PrivateChat
  class UnlockController < Api::V1::Accounts::BaseController
    before_action :ensure_private_chat_enabled

    def create
      input_password = params[:password].to_s.strip
      unless PrivateChat::Config.valid_password?(input_password)
        render json: { error: I18n.t('errors.private_chat.invalid_password') }, status: :unauthorized
        return
      end

      conversation_id = PrivateChat::Config.conversation_id
      if PrivateChat::Config.account_id.present? && Current.account.id != PrivateChat::Config.account_id
        render json: { error: 'Not found' }, status: :not_found
        return
      end

      token = PrivateChat::TokenService.encode(
        account_id: Current.account.id,
        user_id: Current.user.id,
        conversation_id: conversation_id
      )

      render json: {
        token: token,
        conversation_id: conversation_id,
        account_id: Current.account.id
      }
    end

    private

    def ensure_private_chat_enabled
      return if PrivateChat::Config.enabled?

      render json: { error: 'Not found' }, status: :not_found
    end
  end
end
