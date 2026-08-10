# frozen_string_literal: true

# A flag `internal_chat` só existia no front (rota do dashboard). Desligá-la
# escondia o menu e nada mais: a API respondia normalmente para qualquer conta,
# então quem já tinha canal seguia conversando e recebendo em tempo real.
# Este guard faz a flag valer no servidor, que é onde ela precisa valer.
module InternalChatFeatureGuard
  extend ActiveSupport::Concern

  included do
    before_action :ensure_internal_chat_enabled
  end

  private

  def ensure_internal_chat_enabled
    return if Current.account&.feature_enabled?('internal_chat')

    render json: { error: 'Internal chat is not enabled for this account' }, status: :forbidden
  end
end
