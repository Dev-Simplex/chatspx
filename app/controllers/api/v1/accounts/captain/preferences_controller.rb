class Api::V1::Accounts::Captain::PreferencesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :authorize_account_update, only: [:update]

  def show
    render json: preferences_payload
  end

  def update
    params_to_update = captain_params
    @current_account.captain_models = params_to_update[:captain_models] if params_to_update[:captain_models]
    @current_account.captain_features = params_to_update[:captain_features] if params_to_update[:captain_features]
    @current_account.save! if @current_account.changed?

    update_llm_connection(params_to_update[:llm_connection]) if params_to_update[:llm_connection]
    return if performed?

    render json: preferences_payload
  end

  private

  def preferences_payload
    {
      providers: Llm::Models.providers,
      models: Llm::Models.models,
      features: features_with_account_preferences,
      llm_connection: openai_hook_service.connection_payload,
      anthropic_connection: anthropic_hook_service.connection_payload
    }
  end

  def authorize_account_update
    authorize @current_account, :update?
  end

  def captain_params
    permitted = {}
    permitted[:captain_models] = merged_captain_models if params[:captain_models].present?
    permitted[:captain_features] = merged_captain_features if params[:captain_features].present?
    permitted[:llm_connection] = permitted_llm_connection if params[:llm_connection].present?
    permitted
  end

  def merged_captain_models
    existing_models = @current_account.captain_models || {}
    existing_models.merge(permitted_captain_models)
  end

  def merged_captain_features
    existing_features = @current_account.captain_features || {}
    existing_features.merge(permitted_captain_features)
  end

  def permitted_captain_models
    params.require(:captain_models).permit(
      :editor, :assistant, :copilot, :label_suggestion,
      :audio_transcription, :help_center_search
    ).to_h.stringify_keys
  end

  def permitted_captain_features
    params.require(:captain_features).permit(
      :editor, :assistant, :copilot, :label_suggestion,
      :audio_transcription, :help_center_search
    ).to_h.stringify_keys
  end

  def features_with_account_preferences
    preferences = Current.account.captain_preferences
    account_features = preferences[:features] || {}
    account_models = preferences[:models] || {}

    Llm::Models.feature_keys.index_with do |feature_key|
      config = Llm::Models.feature_config(feature_key)
      config.merge(
        enabled: account_features[feature_key] == true,
        selected: account_models[feature_key] || config[:default]
      )
    end
  end

  def update_llm_connection(llm_connection)
    connection = llm_connection.with_indifferent_access
    return process_key_removal(connection) if key_removal_requested?(connection)

    update_openai_key(connection[:openai_api_key]) if connection[:openai_api_key].present?
    update_anthropic_key(connection[:anthropic_api_key]) if connection[:anthropic_api_key].present?
  rescue Captain::OpenaiHookService::InvalidApiKeyError,
         Captain::AnthropicHookService::InvalidApiKeyError => e
    render_api_key_error('captain_api_key_invalid', e.message)
  rescue Captain::OpenaiHookService::ApiConnectionError,
         Captain::AnthropicHookService::ApiConnectionError => e
    render_api_key_error('captain_api_key_validation_failed', e.message)
  end

  def key_removal_requested?(connection)
    ActiveModel::Type::Boolean.new.cast(connection[:remove_api_key]) ||
      ActiveModel::Type::Boolean.new.cast(connection[:remove_anthropic_key])
  end

  def process_key_removal(connection)
    openai_hook_service.remove_api_key! if ActiveModel::Type::Boolean.new.cast(connection[:remove_api_key])
    anthropic_hook_service.remove_api_key! if ActiveModel::Type::Boolean.new.cast(connection[:remove_anthropic_key])
  end

  def render_api_key_error(code, message)
    render json: { code: code, message: message }, status: :unprocessable_entity
  end

  def update_openai_key(api_key)
    openai_hook_service.validate_and_upsert_api_key!(api_key)
  end

  def update_anthropic_key(api_key)
    anthropic_hook_service.validate_and_upsert_api_key!(api_key)
  end

  def permitted_llm_connection
    params.require(:llm_connection).permit(:openai_api_key, :anthropic_api_key, :remove_api_key, :remove_anthropic_key).to_h.stringify_keys
  end

  def openai_hook_service
    @openai_hook_service ||= Captain::OpenaiHookService.new(account: @current_account)
  end

  def anthropic_hook_service
    @anthropic_hook_service ||= Captain::AnthropicHookService.new(account: @current_account)
  end
end
