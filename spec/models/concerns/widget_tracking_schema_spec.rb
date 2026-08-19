require 'rails_helper'

# Bloco 5.01 — config PUBLICA de tracking por inbox, com recusa explicita de qualquer chave que
# pareca segredo.
#
# `widget_tracking` e publicado no HTML de toda pagina do site do cliente. Segredo que entra ali
# fica publico para sempre: cache, historico do navegador, view-source. Recusar na ESCRITA e a
# unica defesa que funciona — filtrar na leitura nao, porque o dado ja estaria gravado.
NOMES_COM_CARA_DE_SEGREDO = {
  'access_token' => 'EAAGm0PX4ZCpsBA0',
  'api_key' => 'chave',
  'apiKey' => 'chave',
  'password' => 'hunter2',
  'credential' => 'algo',
  'credentials' => 'algo',
  'private_key' => 'algo',
  'authorization' => 'Bearer abc',
  'auth' => 'abc',
  'access_token_v2' => 'EAAGm0PX4ZCpsBA0',
  'secretKey' => 'shhh',
  'signature' => 'abc',
  'salt' => 'abc',
  'passwd' => 'hunter2',
  'pwd' => 'hunter2',
  'client_secret' => 'shhh',
  'refresh_token' => 'abc',
  'webhook_secret' => 'shhh'
}.freeze

RSpec.describe WidgetTrackingSchema do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def grava(tracking)
    inbox.reload
    inbox.widget_tracking = tracking
    inbox
  end

  describe 'o buraco que este bloco fecha' do
    it 'recusa os 18 nomes com cara de segredo, um por um' do
      recusados = NOMES_COM_CARA_DE_SEGREDO.count do |chave, valor|
        grava({ 'meta_pixel_id' => '1234567890', chave => valor }).invalid?
      end

      expect(recusados).to eq(18)
    end

    it 'nomeia a chave ofensora e manda para a tela de credenciais' do
      registro = grava({ 'meta_pixel_id' => '1234567890', 'access_token' => 'EAAGm0PX4ZCpsBA0' })

      expect(registro).to be_invalid
      expect(registro.errors[:widget_tracking].join).to include('access_token')
      # O rails_helper envolve o exemplo em `with_locale(:en)`; o texto pt-BR que o admin ve na
      # tela e verificado no spec de request, que responde no locale da instalacao.
      expect(registro.errors[:widget_tracking].join).to include('credentials screen')
    end

    it 'pega o termo no MEIO do nome, nao so no fim' do
      # `access_token_v2` passava: o padrao de 3.01 exigia que o nome TERMINASSE em token.
      expect(grava({ 'access_token_v2' => 'x' })).to be_invalid
      expect(grava({ 'secret_key_id' => 'x' })).to be_invalid
    end

    it 'pega camelCase, porque apiKey e api_key sao o mesmo segredo' do
      expect(grava({ 'apiKey' => 'x' })).to be_invalid
      expect(grava({ 'privateKey' => 'x' })).to be_invalid
    end

    it 'pega segredo escondido em objeto aninhado e em array' do
      expect(grava({ 'event_map' => { 'nested' => { 'access_token' => 'x' } } })).to be_invalid
      expect(grava({ 'event_map' => [{ 'password' => 'x' }] })).to be_invalid
    end
  end

  describe 'o disfarce que sobra: nome inocente, VALOR de segredo' do
    {
      'JWT' => 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdefghijklmnop',
      'Meta' => 'EAAGm0PX4ZCpsBA0ZDZD1234567890abcdefghij',
      'Stripe' => 'sk_live_1234567890abcdefghijklmn',
      'Google API key' => 'AIzaSyD1234567890abcdefghijklmnopqrstuv',
      'GitHub' => 'ghp_1234567890abcdefghijklmnopqrstuvwx',
      'Slack' => 'xoxb-123456789012-abcdefghijkl',
      'cabecalho colado' => 'Bearer abcdefghijklmnop',
      'chave privada PEM' => "-----BEGIN RSA PRIVATE KEY-----\nMIIE"
    }.each do |formato, valor|
      it "recusa #{formato} mesmo sob a chave publica event_map" do
        registro = grava({ 'event_map' => { 'conversation_started' => valor } })

        expect(registro).to be_invalid
        expect(registro.errors[:widget_tracking].join).to include('looks like a credential')
      end
    end

    it 'a mensagem nomeia a CHAVE e nunca ecoa o valor — senao o erro publica o segredo de novo' do
      segredo = 'sk_live_1234567890abcdefghijklmn'
      registro = grava({ 'event_map' => { 'conversation_started' => segredo } })

      expect(registro).to be_invalid
      mensagem = registro.errors[:widget_tracking].join
      expect(mensagem).to include('conversation_started')
      expect(mensagem).not_to include(segredo)
      expect(mensagem).not_to include('sk_live')
    end
  end

  describe 'o outro lado: config publica legitima nao pode ser recusada' do
    # Falso positivo aqui impede o cliente que nao fez nada errado de salvar. Por isso a deteccao
    # por valor usa prefixos publicados pelas plataformas, nunca "string longa aleatoria".
    it 'aceita as seis chaves publicas, juntas, com os formatos reais' do
      registro = grava(
        'meta_pixel_id' => '1234567890',
        'ga4_measurement_id' => 'G-ABC1234567',
        'google_ads_send_to' => 'AW-123456789/AbC-D_efGh12',
        'event_map' => { 'conversation_started' => 'Lead', 'conversation_resolved' => 'Purchase' },
        'consent_mode' => 'advanced',
        'test_mode' => false
      )

      expect(registro).to be_valid
    end

    it 'google_ads_send_to comprido nao e confundido com token' do
      expect(grava({ 'google_ads_send_to' => 'AW-123456789/AbC-D_efGh12' })).to be_valid
    end

    it 'recusa formato errado do identificador, dizendo qual campo' do
      registro = grava({ 'ga4_measurement_id' => 'nao-e-um-measurement-id' })

      expect(registro).to be_invalid
      expect(registro.errors[:widget_tracking].join).to include('ga4_measurement_id')
    end

    it 'recusa consent_mode fora do vocabulario do Google' do
      expect(grava({ 'consent_mode' => 'talvez' })).to be_invalid
      expect(grava({ 'consent_mode' => 'advanced' })).to be_valid
    end
  end

  describe 'schema e projecao publica descrevem o MESMO conjunto' do
    # Se divergirem, uma chave e aceita na escrita e descartada na leitura: o cliente salva, a tela
    # confirma, e o dado some sem aviso. E a forma de mentira que esta onda existe para matar.
    it 'as chaves do schema sao exatamente as da projecao entregue ao widget' do
      expect(described_class::SCHEMA['properties'].keys).to match_array(WidgetTrackingProjection::PUBLIC_KEYS)
    end

    it 'chave nao declarada e recusada na escrita, em vez de gravada e descartada na leitura' do
      registro = grava({ 'meta_pixel_id' => '1234567890', 'chave_inventada' => 'valor' })

      expect(registro).to be_invalid
      expect(registro.errors[:widget_tracking].join).to include('chave_inventada')
    end
  end
end
