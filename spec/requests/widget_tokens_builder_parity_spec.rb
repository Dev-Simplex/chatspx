require 'rails_helper'

# Paridade de CONTEÚDO dos tokens de marca entre os dois montadores de config.
#
# A suíte 0.6 (`widget_configuration_builder_parity_spec.rb`) compara as CHAVES
# dos dois montadores. Isso pega a ausência — foi ela que pegou `tokens` faltando
# no jbuilder — mas não pegaria o defeito seguinte, que é pior porque é mudo:
# os dois emitirem a chave `tokens` com valores DIFERENTES.
#
# É a mesma forma do defeito que o bloco 1.23 encontrou no `IFrameHelper`
# (`set-user` cru sem `identifier` de um lado, `{identifier, user}` do outro):
# duas pontas coerentes sozinhas, incompatíveis na junção, verdes nos dois lados.
# Uma suíte de chaves não vê isso. Esta vê.
RSpec.describe 'Widget brand tokens — parity of CONTENT between both builders', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account, widget_color: '#009CE0') }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  # A fonte única. Se um dos montadores divergir dela, divergiu do outro também.
  let(:expected_tokens) { WidgetTokens.for(web_widget).to_h }

  def erb_tokens
    get widget_url(website_token: web_widget.website_token, cw_conversation: token)
    expect(response).to have_http_status(:ok)

    match = response.body.match(/^\s*tokens:\s*(?<json>\{.*?\}),\s*$/m)
    raise 'show.html.erb did not render a `tokens:` entry' if match.nil?

    JSON.parse(match[:json])
  end

  def jbuilder_tokens
    post '/api/v1/widget/config',
         params: { website_token: web_widget.website_token },
         headers: { 'X-Auth-Token' => token },
         as: :json
    expect(response).to have_http_status(:ok)

    response.parsed_body.fetch('website_channel_config').fetch('tokens')
  end

  it 'both builders emit the SAME token values, not merely the same key' do
    expect(erb_tokens).to eq(jbuilder_tokens)
  end

  it 'both builders match the single source, WidgetTokens' do
    expect(erb_tokens).to eq(expected_tokens)
    expect(jbuilder_tokens).to eq(expected_tokens)
  end

  it 'the emitted contrast decision is the WCAG one, on both sides' do
    # `#009CE0` tem L = 0,2916 > 0,17913, então a cor legível sobre a marca é o
    # PRETO puro — 6,8318:1 contra 3,07:1 do branco que a heurística YIQ dava.
    # Este exemplo existe para que a paridade não possa ser satisfeita por dois
    # montadores igualmente errados.
    expect(erb_tokens['--w-on-brand']).to eq('#000000')
    expect(jbuilder_tokens['--w-on-brand']).to eq('#000000')
    expect(jbuilder_tokens['--w-brand']).to eq('#009ce0')
  end

  it 'an invalid colour in the database does not leak into either builder' do
    # `update_column` de propósito: o cenário que este exemplo reproduz é
    # exatamente o de um valor sujo JÁ GRAVADO no banco — vindo de importação,
    # de migração antiga ou de uma validação que ainda não existia. Passar pela
    # validação do modelo tornaria o teste impossível de escrever, porque ela é
    # justamente o que impede o dado de chegar lá pela via normal.
    # rubocop:disable Rails/SkipsModelValidations
    web_widget.update_column(:widget_color, '#fff;} :root{--w-brand:red}')
    # rubocop:enable Rails/SkipsModelValidations

    expect(erb_tokens).to eq(jbuilder_tokens)
    expect(jbuilder_tokens['--w-brand']).to eq('#1f93ff')
    expect(jbuilder_tokens.values.join).not_to include('red')
  end
end
