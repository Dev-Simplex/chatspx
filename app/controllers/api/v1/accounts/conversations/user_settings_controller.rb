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

  def user_setting_params
    params.permit(user_setting: [:pinned, :archived_at, :muted_until, :theme_key]).fetch(:user_setting, {})
  end
end
