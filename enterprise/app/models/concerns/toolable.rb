module Concerns::Toolable
  extend ActiveSupport::Concern

  # Isolated namespace for user-defined custom tool classes.
  # Keeps them separate from built-in classes in Captain::Tools (e.g., HttpTool, CustomHttpTool).
  module CustomTools; end

  def tool(assistant, base_class: Captain::Tools::HttpTool, **)
    custom_tool_record = self
    class_name = custom_tool_record.slug.underscore.camelize

    # Always create a fresh class to reflect current metadata
    tool_slug = custom_tool_record.slug
    tool_class = Class.new(base_class) do
      description custom_tool_record.description

      # Override name to use the slug directly, avoiding the namespace prefix
      # that RubyLLM's default normalization would produce (e.g., "captain--tools--custom_dog_facts").
      define_method(:name) { tool_slug }

      custom_tool_record.param_schema.each do |param_def|
        param param_def['name'].to_sym,
              type: param_def['type'],
              desc: param_def['description'],
              required: param_def.fetch('required', true)
      end
    end

    # Register as a constant so the class gets a proper name (Class#name).
    # Anonymous classes return nil for #name, which causes "Invalid 'tools[].function.name':
    # empty string" errors from the LLM API. We use CustomTools as the namespace to avoid
    # collisions with real classes in Captain::Tools.
    CustomTools.send(:remove_const, class_name) if CustomTools.const_defined?(class_name, false)
    CustomTools.const_set(class_name, tool_class)

    tool_class.new(assistant, self, **)
  end

  def build_request_url(params)
    return endpoint_url if endpoint_url.blank? || endpoint_url.exclude?('{{')

    render_template(endpoint_url, render_context(params))
  end

  def build_request_body(params)
    return nil if request_template.blank?

    render_template(request_template, render_context(params))
  end

  def build_auth_headers
    return {} if auth_none?

    case auth_type
    when 'bearer'
      { 'Authorization' => "Bearer #{auth_config['token']}" }
    when 'api_key'
      { auth_config['name'] => auth_config['key'] }
    else
      {}
    end
  end

  def build_basic_auth_credentials
    return nil unless auth_type == 'basic'

    [auth_config['username'], auth_config['password']]
  end

  def build_metadata_headers(state)
    {}.tap do |headers|
      add_base_headers(headers, state)
      add_conversation_headers(headers, state[:conversation]) if state[:conversation]
      add_contact_headers(headers, state[:contact]) if state[:contact]
      add_contact_inbox_headers(headers, state[:contact_inbox])
    end
  end

  def add_base_headers(headers, state)
    headers['X-Chatwoot-Account-Id'] = state[:account_id].to_s if state[:account_id]
    headers['X-Chatwoot-Assistant-Id'] = state[:assistant_id].to_s if state[:assistant_id]
    headers['X-Chatwoot-Tool-Slug'] = slug if slug.present?
  end

  def add_conversation_headers(headers, conversation)
    headers['X-Chatwoot-Conversation-Id'] = conversation[:id].to_s if conversation[:id]
    headers['X-Chatwoot-Conversation-Display-Id'] = conversation[:display_id].to_s if conversation[:display_id]
  end

  def add_contact_headers(headers, contact)
    headers['X-Chatwoot-Contact-Id'] = contact[:id].to_s if contact[:id]
    headers['X-Chatwoot-Contact-Email'] = contact[:email].to_s if contact[:email].present?
    headers['X-Chatwoot-Contact-Phone'] = contact[:phone_number].to_s if contact[:phone_number].present?
  end

  def add_contact_inbox_headers(headers, contact_inbox)
    headers['X-Chatwoot-Contact-Inbox-Id'] = contact_inbox[:id].to_s if contact_inbox&.[](:id)
    headers['X-Chatwoot-Contact-Inbox-Verified'] = (contact_inbox&.[](:hmac_verified) || false).to_s
  end

  def format_response(raw_response_body)
    return raw_response_body if response_template.blank?

    response_data = parse_response_body(raw_response_body)
    render_template(response_template, { 'response' => response_data, 'r' => response_data })
  end

  private

  # Render context for endpoint_url / request_template. Exposes the LLM-provided
  # params PLUS `secrets.*` — the account's integration credentials (Vista/Google)
  # from AccountIntegration. Lets a custom tool reference e.g.
  # `{{ secrets.google_maps_key }}` in its URL instead of hardcoding the API key,
  # so secrets live in account_integrations (one place, per account) and never sit
  # in the tool's endpoint_url. `secrets` wins on a key collision with a tool param.
  def render_context(params)
    (params || {}).merge('secrets' => integration_secrets)
  end

  # Account integration credentials as a flat Hash (Vista + Google merged), string
  # keys — empty Hash when the account has none. Never raises: a credential lookup
  # failure must not take down the tool call.
  def integration_secrets
    acc = account
    return {} unless acc

    AccountIntegration.settings_for(acc, 'vista')
                      .merge(AccountIntegration.settings_for(acc, 'google'))
  rescue StandardError => e
    Rails.logger.error("[Toolable] integration_secrets failed: #{e.message}")
    {}
  end

  def render_template(template, context)
    liquid_template = Liquid::Template.parse(template, error_mode: :strict)
    liquid_template.render(context.deep_stringify_keys, registers: {}, strict_variables: true, strict_filters: true)
  rescue Liquid::SyntaxError, Liquid::UndefinedVariable, Liquid::UndefinedFilter => e
    Rails.logger.error("Liquid template error: #{e.message}")
    raise "Template rendering failed: #{e.message}"
  end

  def parse_response_body(body)
    JSON.parse(body)
  rescue JSON::ParserError
    body
  end
end
