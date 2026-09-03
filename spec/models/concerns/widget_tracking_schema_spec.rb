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

  # T-C4.3 (bloco 5.10) — o interruptor de "instalar a tag que falta".
  #
  # O objeto `install_tags` e o primeiro sub-objeto de `widget_tracking` com FORMA declarada, e
  # por isso ele e o primeiro lugar onde a defesa da raiz nao alcanca sozinha:
  # `additionalProperties: false` no topo recusa `chave_inventada` ao lado de `meta_pixel_id`,
  # e NAO recusa `chave_inventada` DENTRO de `install_tags`. Como o objeto inteiro e publicado
  # no HTML de toda pagina do site do cliente, um saco aberto ali e um segredo publicado.
  describe 'install_tags: o opt-in de instalar a tag faltante (T-C4.3)' do
    it 'aceita os dois alvos, ligados e desligados' do
      expect(grava({ 'install_tags' => { 'meta' => true, 'google' => false } })).to be_valid
      expect(grava({ 'install_tags' => { 'meta' => false, 'google' => true } })).to be_valid
      expect(grava({ 'install_tags' => {} })).to be_valid
    end

    it 'o default e a AUSENCIA da chave, e ausencia e valido (decisao Q5: nunca por padrao)' do
      # Nao ha backfill e nao ha valor gravado: quem nunca marcou nada nao tem `install_tags`,
      # e quem nao tem `install_tags` nao tem tag nossa instalada. A regra A4 em uma linha.
      expect(grava({ 'meta_pixel_id' => '1234567890' })).to be_valid
      expect(inbox.widget_tracking['install_tags']).to be_nil
    end

    # ESTE e o exemplo que a linha `additionalProperties: false` de `install_tags` existe para
    # fazer passar. `install_now` nao parece segredo: a lista negativa de nomes o deixa entrar,
    # e o `additionalProperties` da RAIZ nao desce um nivel. Tire aquela linha do schema e este
    # exemplo fica VERMELHO — foi assim que ele foi conferido.
    it 'recusa sub-chave desconhecida que a lista negativa de nomes NAO pegaria' do
      registro = grava({ 'install_tags' => { 'meta' => true, 'install_now' => true } })

      expect(registro).to be_invalid
      expect(registro.errors[:widget_tracking].join).to include('install_tags')
    end

    it 'recusa segredo escondido DENTRO do objeto novo' do
      expect(grava({ 'install_tags' => { 'meta' => true, 'access_token' => 'EAAGm0PX4ZCpsBA0' } })).to be_invalid
    end

    it 'recusa alvo que nao e booleano — "sim" nao e um opt-in' do
      expect(grava({ 'install_tags' => { 'meta' => 'sim' } })).to be_invalid
      expect(grava({ 'install_tags' => { 'google' => 1 } })).to be_invalid
    end

    it 'recusa install_tags que nao e objeto' do
      expect(grava({ 'install_tags' => true })).to be_invalid
    end

    it 'a chave publica nova nao afrouxou a raiz: access_token no topo continua 422' do
      # A guarda que o briefing desta trilha pediu por escrito. Acrescentar propriedade a um
      # schema com `additionalProperties: false` e o momento classico de a defesa cair junto.
      registro = grava({ 'install_tags' => { 'meta' => true }, 'access_token' => 'EAAGm0PX4ZCpsBA0' })

      expect(registro).to be_invalid
      expect(registro.errors[:widget_tracking].join).to include('access_token')
    end
  end

  # ═══ O DEFEITO QUE NENHUM DOS DOIS LADOS PEGAVA ═══════════════════════════════════════
  #
  # Ate aqui, a Tela 4 devolvia 422 em TODO salvamento: ela grava OBJETO em `event_map`, em
  # `test_mode` e em `lead_value`, e o schema declarava string, booleano e nada.
  #
  # E passou despercebido porque CADA LADO TESTAVA O SEU FORMATO. O spec deste arquivo
  # gravava `{ 'conversation_started' => 'Lead' }` e ficava verde. O spec da tela montava o
  # objeto e ficava verde. Ninguem rodava o payload da TELA contra o VALIDADOR — e o vao
  # entre dois testes verdes e onde o defeito morava.
  #
  # Este bloco e a ponte que faltava, e ele LE o contrato do front: se alguem acrescentar um
  # evento em `widgetTrackingContract.js`, o payload daqui cresce junto e continua sendo o que
  # a tela manda de verdade, nao uma copia que envelhece em silencio.
  describe 'a Tela 4 salva: o payload REAL da tela contra o validador REAL' do
    contrato_js = Rails.root.join('app/javascript/dashboard/routes/dashboard/settings/inbox/widget/composables/widgetTrackingContract.js').read

    # Os doze eventos, lidos do bloco `DEFAULT_EVENT_MAP` do arquivo do front.
    mapa_de_fabrica = contrato_js[/DEFAULT_EVENT_MAP = Object\.freeze\(\{(.+?)\n\}\);/m, 1].to_s
    eventos_da_tela = mapa_de_fabrica.scan(/^\s{2}(chatspx_[a-z_]+):/).flatten
    subchaves_da_tela = mapa_de_fabrica.scan(/\b(enabled|meta|ga4):/).flatten.uniq.sort

    # O payload como a `TrackingPage.vue` o monta: mapa completo em forma de objeto, modo
    # teste com codigo e data, valor do lead, e o interruptor de instalacao.
    let(:payload_da_tela) do
      {
        'meta_pixel_id' => '123456789012345',
        'ga4_measurement_id' => 'G-ABC1234567',
        'google_ads_send_to' => 'AW-123456789/AbC-D_efGh12',
        'consent_mode' => 'basic',
        'event_map' => eventos_da_tela.index_with { |_| { 'enabled' => true, 'meta' => 'Lead', 'ga4' => 'generate_lead' } },
        'test_mode' => { 'enabled' => true, 'code' => 'TEST12345', 'started_at' => Time.current.iso8601 },
        'lead_value' => { 'mode' => 'fixed', 'amount' => 250 },
        'install_tags' => { 'meta' => false, 'google' => false }
      }
    end

    it 'o contrato do front foi mesmo lido — senao os exemplos abaixo medem uma string vazia' do
      expect(eventos_da_tela.size).to eq(12)
      expect(subchaves_da_tela).to eq(%w[enabled ga4 meta])
    end

    it 'as subchaves que a tela escreve sao EXATAMENTE as que o schema declara' do
      expect(described_class::EVENT_MAP_OBJECT['properties'].keys.sort).to eq(subchaves_da_tela)
    end

    it 'o payload inteiro da tela e ACEITO — este exemplo reprova a arvore de ontem' do
      expect(grava(payload_da_tela)).to be_valid
    end

    it 'e cada campo dele isolado tambem, para nomear o culpado quando quebrar' do
      recusados = payload_da_tela.keys.reject { |chave| grava(payload_da_tela.slice(chave)).valid? }

      expect(recusados).to eq([])
    end

    it '`meta`/`ga4` nulos sao o dado, e nao um campo esquecido' do
      # `{ enabled: false, meta: nil, ga4: "widget_open" }` = "so ao GA4, com este nome,
      # desligado". Onze das doze entradas de fabrica usam `nil` em pelo menos um destino;
      # recusa-lo devolveria a tela ao 422.
      expect(grava({ 'event_map' => { 'chatspx_widget_opened' => { 'enabled' => false, 'meta' => nil, 'ga4' => 'widget_open' } } })).to be_valid
    end

    it 'a forma STRING continua aceita — inbox gravada por API nao pode quebrar' do
      expect(grava({ 'event_map' => { 'chatspx_lead' => 'Lead' } })).to be_valid
    end

    it 'mas o objeto do mapa nao virou saco aberto: subchave desconhecida e recusada' do
      registro = grava({ 'event_map' => { 'chatspx_lead' => { 'enabled' => true, 'tiktok' => 'Lead' } } })

      expect(registro).to be_invalid
    end

    it 'nem o de `test_mode`, nem o de `lead_value`' do
      expect(grava({ 'test_mode' => { 'enabled' => true, 'inventado' => 1 } })).to be_invalid
      expect(grava({ 'lead_value' => { 'mode' => 'fixed', 'inventado' => 1 } })).to be_invalid
    end

    it '`lead_value.mode` fora do vocabulario da tela e recusado' do
      expect(grava({ 'lead_value' => { 'mode' => 'talvez' } })).to be_invalid
      described_class::LEAD_VALUE_MODES.each do |modo|
        expect(grava({ 'lead_value' => { 'mode' => modo } })).to be_valid
      end
    end

    it 'segredo escondido no objeto do mapa continua sendo recusado' do
      # A forma nova nao abriu porta para a lista negativa: `additionalProperties: false` no
      # nivel do objeto ja recusa, e o varredor de segredo recusa de novo pelo VALOR.
      expect(grava({ 'event_map' => { 'chatspx_lead' => { 'enabled' => true,
                                                          'meta' => 'EAAGm0PX4ZCpsBA0ZDZD1234567890abcdefghij' } } })).to be_invalid
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
