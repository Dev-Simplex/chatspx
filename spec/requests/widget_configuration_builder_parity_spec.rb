require 'rails_helper'

RSpec.describe 'Widget configuration builder parity', type: :request do
  let(:erb_template) { 'app/views/widgets/show.html.erb' }
  let(:jbuilder_template) { 'app/views/api/v1/widget/configs/create.json.jbuilder' }
  let(:directional_allowlist) do
    {
      erb_template => %w[hasAConnectedAgentBot],
      jbuilder_template => %w[api_host]
    }
  end
  let(:sabotage_keys) do
    {
      'erb' => 'paritySabotageKey',
      'jbuilder' => 'parity_sabotage_key'
    }
  end

  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  it 'keeps the rendered public configuration keys aligned with only the two directional exceptions' do
    erb_keys = rendered_erb_keys
    jbuilder_keys = rendered_jbuilder_keys
    actual_differences = directional_differences(erb_keys, jbuilder_keys)

    expect(actual_differences).to eq(directional_allowlist), parity_failure_message(actual_differences)
  end

  def rendered_erb_keys
    get widget_url(website_token: web_widget.website_token, cw_conversation: token)
    expect(response).to have_http_status(:ok)

    config_match = response.body.match(
      /window\.chatwootWebChannel\s*=\s*\{(?<config>.*?)^\s*\}\s*window\.chatwootPubsubToken/m
    )
    raise "Could not find window.chatwootWebChannel rendered by #{erb_template}" if config_match.nil?

    keys = config_match[:config].scan(/^\s*([A-Za-z]\w*):/).flatten
    keys.concat(response.body.scan(/^\s*window\.(authToken)\s*=/).flatten)
    sabotage(keys, 'erb')
  end

  def rendered_jbuilder_keys
    post '/api/v1/widget/config',
         params: { website_token: web_widget.website_token },
         headers: { 'X-Auth-Token' => token },
         as: :json
    expect(response).to have_http_status(:ok)

    keys = response.parsed_body.fetch('website_channel_config').keys
    sabotage(keys, 'jbuilder')
  end

  def directional_differences(erb_keys, jbuilder_keys)
    erb_by_canonical_key = keys_by_canonical_name(erb_keys)
    jbuilder_by_canonical_key = keys_by_canonical_name(jbuilder_keys)

    {
      erb_template => difference(erb_by_canonical_key, jbuilder_by_canonical_key),
      jbuilder_template => difference(jbuilder_by_canonical_key, erb_by_canonical_key)
    }
  end

  def keys_by_canonical_name(keys)
    keys.index_by { |key| key.delete('_').downcase }
  end

  def difference(source_keys, comparison_keys)
    (source_keys.keys - comparison_keys.keys).map { |key| source_keys.fetch(key) }.sort
  end

  def sabotage(keys, builder)
    sabotage_key = sabotage_keys[ENV.fetch('WIDGET_CONFIG_PARITY_SABOTAGE', nil)]
    return keys unless ENV['WIDGET_CONFIG_PARITY_SABOTAGE'] == builder

    keys + [sabotage_key]
  end

  def parity_failure_message(actual_differences)
    erb_only = actual_differences.fetch(erb_template) - directional_allowlist.fetch(erb_template)
    jbuilder_only = actual_differences.fetch(jbuilder_template) - directional_allowlist.fetch(jbuilder_template)

    <<~MESSAGE
      Widget configuration key parity drifted.
      Missing from #{jbuilder_template}: #{erb_only.inspect}
      Missing from #{erb_template}: #{jbuilder_only.inspect}
      Expected directional differences: #{directional_allowlist.inspect}
      Actual directional differences: #{actual_differences.inspect}
    MESSAGE
  end
end
