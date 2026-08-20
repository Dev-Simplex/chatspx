class Api::V1::Accounts::Captain::CustomToolsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::CustomTool) }
  before_action :set_custom_tool, only: [:show, :update, :destroy, :test]

  def index
    # Return ALL tools (enabled + disabled) so the UI can reactivate disabled ones.
    @custom_tools = account_custom_tools
  end

  def show; end

  def create
    @custom_tool = account_custom_tools.create!(custom_tool_params)
  end

  def update
    @custom_tool.update!(custom_tool_params)
  end

  def destroy
    @custom_tool.destroy
    head :no_content
  end

  # Smoke-test this custom tool against its real endpoint, reusing HttpTool so the
  # SSRF guard and request/auth building are exercised. Returns { ok, status, body }
  # or { ok: false, error }. Admin-only (see Captain::CustomToolPolicy#test?).
  def test
    assistant = Captain::Assistant.new(account: Current.account)
    tool = Captain::Tools::HttpTool.new(assistant, @custom_tool)
    render json: tool.perform_test(**test_tool_params)
  end

  private

  def set_custom_tool
    @custom_tool = account_custom_tools.find(params[:id])
  end

  def account_custom_tools
    @account_custom_tools ||= Current.account.captain_custom_tools
  end

  def custom_tool_params
    params.require(:custom_tool).permit(
      :title,
      :description,
      :endpoint_url,
      :http_method,
      :request_template,
      :response_template,
      :auth_type,
      :enabled,
      :copilot_only,
      auth_config: {},
      param_schema: [:name, :type, :description, :required]
    )
  end

  # Dynamic tool params — keys depend on the tool's param_schema. This is an admin-only
  # action and the values are fed into the tool's strict Liquid templates, so permit! is
  # acceptable here.
  def test_tool_params
    raw = params[:params]
    return {} if raw.blank?

    raw = raw.permit! if raw.respond_to?(:permit!)
    raw.to_h.deep_symbolize_keys
  end
end
