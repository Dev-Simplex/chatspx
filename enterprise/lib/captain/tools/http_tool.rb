require 'agents'

class Captain::Tools::HttpTool < Agents::Tool
  def initialize(assistant, custom_tool)
    @assistant = assistant
    @custom_tool = custom_tool
    super()
  end

  def active?
    @custom_tool.enabled?
  end

  def perform(tool_context, **params)
    url = @custom_tool.build_request_url(params)
    body = @custom_tool.build_request_body(params)

    response_body = execute_http_request(url, body, tool_context)
    @custom_tool.format_response(response_body)
  rescue StandardError => e
    Rails.logger.error("HttpTool execution error for #{@custom_tool.slug}: #{e.class} - #{e.message}")
    'An error occurred while executing the request'
  end

  # Additive helper for the custom-tool "test" endpoint (admin smoke test). Reuses the
  # same SSRF guard and request/auth building as #perform, but returns the raw HTTP
  # status/body instead of the LLM-formatted string. Does NOT alter #perform (the
  # LLM-facing entrypoint) — purely additive.
  def perform_test(**params)
    url = @custom_tool.build_request_url(params)
    body = @custom_tool.build_request_body(params)

    response = execute_http_request(url, body, nil)
    { ok: true, status: response.code.to_i, body: truncate_test_body(response.body) }
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  private

  # Limit response size to prevent memory exhaustion and match LLM token limits
  # 1MB of text ≈ 250K tokens, which exceeds most LLM context windows
  MAX_RESPONSE_SIZE = 1.megabyte

  # Route through SafeFetch so custom tool requests share the app's centralized HTTP
  # fetching (resolution, timeouts, response size limits, and redirect handling).
  def execute_http_request(url, body, tool_context)
    json_body = body if @custom_tool.http_method == 'POST'
    auth_headers = @custom_tool.build_auth_headers

    response_body = +''
    SafeFetch.fetch(
      url,
      method: @custom_tool.http_method == 'POST' ? :post : :get,
      body: json_body,
      headers: request_headers(tool_context, json_body, auth_headers),
      sensitive_headers: auth_headers.keys,
      http_basic_authentication: @custom_tool.build_basic_auth_credentials,
      max_bytes: MAX_RESPONSE_SIZE,
      validate_content_type: false
    ) { |result| response_body = result.tempfile.read }
    response_body
  end

  def request_headers(tool_context, json_body, auth_headers)
    headers = auth_headers.dup
    headers.merge!(@custom_tool.build_metadata_headers(tool_context&.state || {}))
    headers['Content-Type'] = 'application/json' if json_body.present?
    headers
  end

  def truncate_test_body(raw)
    raw.to_s.dup.force_encoding(Encoding::UTF_8).scrub('?')[0, 5000]
  end
end
