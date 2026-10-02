class Api::V1::Accounts::Conversations::UserSettingsController < Api::V1::Accounts::Conversations::BaseController
  def update
    settings = service.perform
    render json: {
      conversation_id: @conversation.display_id,
      user_id: Current.user.id,
      user_settings: settings
    }
  rescue Conversations::UserSettingUpdateService::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    Conversations::UserSettingUpdateService.new(
      conversation: @conversation,
      user_id: Current.user.id,
      patch: {}
    ).destroy

    head :no_content
  end

  private

  def service
    Conversations::UserSettingUpdateService.new(
      conversation: @conversation,
      user_id: Current.user.id,
      patch: user_setting_params
    )
  end

  # `.to_h` é obrigatório: o UserSettingUpdateService só aceita Hash e trata o resto como `{}`.
  # Com `permit(...).fetch` saía um ActionController::Parameters, então TODO PATCH (fixar, arquivar,
  # silenciar, tema) respondia 422 "patch must contain at least one allowed key" desde maio — o app
  # mostrava o estado otimista e perdia no próximo fetch. Medido em 18/09/2026 com a conta sup@.
  def user_setting_params
    params.fetch(:user_setting, {}).permit(:pinned, :archived_at, :muted_until, :theme_key).to_h
  end
end
