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
  # Bloco 4.08 — o numero que a inbox grava, e que os dois montadores tem de publicar IGUAL.
  let(:stored_whatsapp_number) { '5565999998888' }

  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  # Bloco 4.08 — paridade de VALOR, e nao so de chave.
  #
  # A paridade de chave abaixo ja falha quando um montador esquece a chave. O que ela NAO ve e o
  # caso que este bloco existe para fechar: os dois montadores publicando `whatsAppExitNumber` /
  # `whatsapp_exit_number`, e um deles publicando VAZIO — a chave existe, a paridade fica verde, e
  # o botao de saida some no site do cliente sem nada ficar vermelho. Foi assim que `teaserText`
  # ficou so no ERB, e e assim que uma leitura escrita a mao em cada montador diverge.
  #
  # E UM exemplo, e nao um por montador, de proposito: o que se afirma aqui e a IGUALDADE entre os
  # dois, com a origem gravavel no meio. Dois exemplos separados passam os dois com valores
  # diferentes — cada um comparando com a sua propria expectativa.
  it 'publishes the same stored WhatsApp exit number in both builders' do
    web_widget.inbox.update!(widget_exit: { 'whatsapp_number' => stored_whatsapp_number })

    published = {
      erb_template => erb_whatsapp_exit_number,
      jbuilder_template => jbuilder_whatsapp_exit_number
    }

    expect(published.values.uniq).to eq([stored_whatsapp_number]), exit_number_failure_message(published)
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

  # O valor publicado pelo ERB. LANCA quando a chave nao esta la: devolver `nil` faria a paridade
  # com um jbuilder tambem quebrado passar como "iguais" — que e a forma da assercao negativa que
  # passa porque o sujeito nunca existiu.
  def erb_whatsapp_exit_number
    get widget_url(website_token: web_widget.website_token, cw_conversation: token)
    expect(response).to have_http_status(:ok)

    raw = response.body[/^\s*whatsAppExitNumber:\s*'(?<value>[^']*)'/, :value]
    raise "whatsAppExitNumber not found in the payload rendered by #{erb_template}" if raw.nil?

    sabotage_value(raw, 'erb')
  end

  def jbuilder_whatsapp_exit_number
    post '/api/v1/widget/config',
         params: { website_token: web_widget.website_token },
         headers: { 'X-Auth-Token' => token },
         as: :json
    expect(response).to have_http_status(:ok)

    sabotage_value(response.parsed_body.fetch('website_channel_config').fetch('whatsapp_exit_number'), 'jbuilder')
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

  # A alavanca do VERMELHO: `WIDGET_CONFIG_PARITY_VALUE_SABOTAGE=erb` (ou `jbuilder`) faz aquele
  # montador publicar vazio, que e exatamente a divergencia calada que este exemplo caca. Sem a
  # alavanca, "os dois iguais" e uma afirmacao que ninguem viu falhar.
  def sabotage_value(value, builder)
    return value unless ENV['WIDGET_CONFIG_PARITY_VALUE_SABOTAGE'] == builder

    ''
  end

  def exit_number_failure_message(published)
    <<~MESSAGE
      The WhatsApp exit number drifted between the two widget configuration builders.
      Stored on the inbox (additional_attributes.widget_exit.whatsapp_number): #{stored_whatsapp_number.inspect}
      Published by each builder: #{published.inspect}
      Both builders must read Inbox#whatsapp_exit_number, never widget_exit['whatsapp_number'] by hand.
    MESSAGE
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
