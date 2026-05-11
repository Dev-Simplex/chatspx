class Api::V1::Accounts::Integrations::OpenaiController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  # POST /api/v1/accounts/:account_id/integrations/openai/test_key
  # Body: { api_key: "sk-..." } or empty (uses persisted setting / ENV)
  def test_key
    key = params[:api_key].to_s.strip.presence ||
          Copilot::OpenaiSettings.api_key(Current.account)

    return render json: { valid: false, error: 'missing_key' }, status: :unprocessable_entity if key.blank?

    OpenAI::Client.new(access_token: key).models.list
    render json: { valid: true }
  rescue StandardError => e
    Rails.logger.warn("[Integrations::OpenaiController#test_key] #{e.class}: #{e.message}")
    render json: { valid: false, error: e.message }, status: :unprocessable_entity
  end
end
