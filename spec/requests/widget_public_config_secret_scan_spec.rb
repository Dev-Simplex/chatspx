require 'rails_helper'

# Bloco 5.01 — assercao NEGATIVA sobre a config publica do widget.
#
# Testar que algo NAO existe e o que impede de reaparecer por conveniencia depois. Aqui o "algo" e
# segredo: `widget_tracking` sai no HTML de toda pagina do site do cliente e no JSON do endpoint de
# config. Um token que chegue a qualquer um dos dois esta publico para sempre.
#
# A varredura roda nas DUAS pontas de proposito. O pior defeito desta execucao foi de JUNCAO — cada
# lado certo sozinho, errado em conjunto — e config do widget tem exatamente duas pontas.
NOMES_SUSPEITOS = /(\A|[_"])(access_token|api_key|apikey|client_secret|password|private_key|refresh_token|webhook_secret)([_"]|\z)/i
VALORES_SUSPEITOS = [
  /ey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\./,
  /EAA[A-Za-z0-9]{20,}/,
  /(sk|rk)_(live|test)_[A-Za-z0-9]{16,}/,
  /AIza[A-Za-z0-9_-]{30,}/,
  /gh[pousr]_[A-Za-z0-9]{20,}/,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/
].freeze

RSpec.describe 'Varredura de segredo na config publica do widget (5.01)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  before do
    inbox.update!(
      widget_tracking: {
        'meta_pixel_id' => '1234567890',
        'ga4_measurement_id' => 'G-ABC1234567',
        'google_ads_send_to' => 'AW-123456789/AbC-D_efGh12',
        'event_map' => { 'conversation_started' => 'Lead' },
        'consent_mode' => 'advanced',
        'test_mode' => false
      }
    )
  end

  def corpo_do_html
    get widget_url(website_token: web_widget.website_token, cw_conversation: token)
    expect(response).to have_http_status(:ok)
    aplicar_sabotagem(response.body, 'erb')
  end

  def corpo_do_json
    post '/api/v1/widget/config',
         params: { website_token: web_widget.website_token },
         headers: { 'X-Auth-Token' => token },
         as: :json
    expect(response).to have_http_status(:ok)
    aplicar_sabotagem(response.body, 'jbuilder')
  end

  def aplicar_sabotagem(corpo, ponta)
    return corpo unless ENV['WIDGET_SECRET_SCAN_SABOTAGE'] == ponta

    "#{corpo}\n\"access_token\":\"EAAGm0PX4ZCpsBA0ZDZD1234567890abcdefghij\""
  end

  # EXCECAO DECLARADA, e uma so: o token de sessao do widget. Ele e um JWT e vai no HTML de
  # proposito — sem ele o visitante nao tem sessao. E publico por desenho: o payload e
  # `{source_id, inbox_id, exp, iat}`, escopado aquele visitante naquela inbox, e nao da acesso a
  # nada em nome do cliente.
  #
  # A excecao e pelo VALOR EXATO que este teste gerou, nunca por "ignore JWTs": qualquer outro JWT
  # que aparecer no corpo continua sendo achado. Excecao larga aqui transformaria a varredura em
  # decoracao — que e como um vazamento passaria despercebido.
  # Tokens de sessao do widget conhecidos: o que este teste gerou, e o que a propria resposta
  # emitiu (o endpoint de config REGENERA o token — `configs/create.json.jbuilder:4`). Sao valores
  # exatos, colhidos da corrida; nao um padrao que perdoaria qualquer JWT.
  def tokens_de_sessao(corpo)
    emitido = corpo.match(/"auth_token"\s*:\s*"([^"]+)"/)&.captures&.first
    [token, emitido].compact
  end

  def achados(corpo)
    limpo = tokens_de_sessao(corpo).reduce(corpo) { |texto, t| texto.gsub(t, '<token-de-sessao-do-widget>') }
    nomes = limpo.scan(NOMES_SUSPEITOS).map { |m| m[1] }
    valores = VALORES_SUSPEITOS.flat_map { |padrao| limpo.scan(padrao) }.map { |v| v.is_a?(Array) ? v.join : v }
    (nomes + valores).uniq
  end

  it 'o HTML servido ao visitante nao carrega nome nem valor com cara de credencial' do
    corpo = corpo_do_html

    # a config legitima ESTA la — senao a varredura passaria por vazio, que e o falso verde
    expect(corpo).to include('1234567890')
    expect(achados(corpo)).to eq([])
  end

  it 'o JSON do endpoint de config idem' do
    corpo = corpo_do_json

    expect(corpo).to include('1234567890')
    expect(achados(corpo)).to eq([])
  end

  it 'segredo gravado POR FORA do modelo nao chega a nenhuma das duas pontas' do
    # O cenario que a projecao por lista branca existe para cobrir: console, import, migration de
    # terceiro, bug futuro. A validacao de escrita e contornada de proposito aqui.
    atributos = inbox.additional_attributes.deep_dup
    atributos['widget_tracking']['access_token'] = 'EAAGm0PX4ZCpsBA0ZDZD1234567890abcdefghij'
    # `update_column` de proposito: o cenario e justamente o segredo que entrou SEM passar pela
    # validacao (console, import, migration de terceiro, bug futuro). Usar o caminho validado aqui
    # testaria a validacao de novo, e nao a projecao — que e o que este exemplo existe para provar.
    inbox.update_column(:additional_attributes, atributos) # rubocop:disable Rails/SkipsModelValidations

    expect(inbox.reload.additional_attributes['widget_tracking']).to have_key('access_token')
    expect(achados(corpo_do_html)).to eq([])
    expect(achados(corpo_do_json)).to eq([])
  end

  # Teste que nunca viu vermelho nao prova nada (licao do caso da paridade 0.6): a sabotagem injeta
  # um segredo em cada ponta e exige que a varredura o encontre.
  it 'a varredura reprova quando ha o que reprovar, nas duas pontas' do
    with_modified_env WIDGET_SECRET_SCAN_SABOTAGE: 'erb' do
      expect(achados(corpo_do_html)).not_to eq([])
    end

    with_modified_env WIDGET_SECRET_SCAN_SABOTAGE: 'jbuilder' do
      expect(achados(corpo_do_json)).not_to eq([])
    end
  end
end
