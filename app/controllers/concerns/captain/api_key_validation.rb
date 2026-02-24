module Captain::ApiKeyValidation
  private

  def ensure_captain_api_key!
    return if captain_openai_hook_service.configured?

    render json: {
      code: 'captain_api_key_missing',
      message: I18n.t('captain.errors.missing_api_key')
    }, status: :unprocessable_entity and return
  end

  def captain_openai_hook_service
    @captain_openai_hook_service ||= Captain::OpenaiHookService.new(account: Current.account)
  end
end
