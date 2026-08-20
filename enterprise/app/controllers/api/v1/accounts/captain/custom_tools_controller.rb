class Api::V1::Accounts::Captain::CustomToolsController < Api::V1::Accounts::BaseController
  before_action :ensure_custom_tools_enabled
  before_action -> { check_authorization(Captain::CustomTool) }
  before_action :set_custom_tool, only: [:show, :update, :destroy]
  before_action :set_custom_tool, only: :test, if: -> { params[:id].present? }

  def index
    # Return ALL tools (enabled + disabled) so the UI can reactivate disabled ones.
    @custom_tools = account_custom_tools
  end

  def show; end

  def create
    @custom_tool = account_custom_tools.create!(custom_tool_params)
  rescue Captain::CustomTool::LimitExceededError => e
    render_could_not_create_error(e.message)
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
    if @custom_tool
      assistant = Captain::Assistant.new(account: Current.account)
      tool = Captain::Tools::HttpTool.new(assistant, @custom_tool)
      return render json: tool.perform_test(**test_tool_params)
    end

    tool = account_custom_tools.new(custom_tool_params)
    body = execute_test_request(tool)
    render json: { status: 200, body: body.to_s.truncate(500) }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def ensure_custom_tools_enabled
    return if Current.account.feature_enabled?('custom_tools') || Current.account.feature_enabled?('captain_integration_v2')

    render json: { error: 'Custom tools are not enabled for this account' }, status: :forbidden
  end

  def set_custom_tool
    @custom_tool = account_custom_tools.find(params[:id])
  end

  def account_custom_tools
    @account_custom_tools ||= Current.account.captain_custom_tools
  end

  def execute_test_request(tool)
    http_tool = Captain::Tools::HttpTool.new(nil, tool)
    http_tool.send(:execute_http_request, tool.endpoint_url, nil, nil)
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
