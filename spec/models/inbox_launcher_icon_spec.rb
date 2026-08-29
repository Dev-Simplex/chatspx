require 'rails_helper'

# Bloco 3.19 — a METADE que faltava: o icone do lancador tinha modo e nao tinha byte.
#
# Ate esta base, `launcher_icon` era enum de string com `additionalProperties: false` no topo. Isso
# deixava o modo `image` GRAVAVEL e INALCANCAVEL: o servidor entregava a palavra "image" ao SDK, o
# SDK nao achava `src` nenhum e caia no balao — sem erro, sem log, sem ninguem saber.
#
# O que este spec cobra, e o numero de cada aceite do PLANO-MESTRE §2.2 esta ao lado:
#   (3) o teto de 20 KB e o tipo, RECUSADOS com motivo;
#   (4) o byte vem do NOSSO dominio, e uma CDN externa nao chega nem a ser gravada;
#   (6) `image` sem imagem degrada para o balao no SERVIDOR, antes de o navegador gastar um 404.
RSpec.describe Inbox, type: :model do
  # Um PNG 1x1 de verdade (67 bytes). Nao ha arquivo novo no repositorio de proposito: `*.png` esta
  # no `.gitignore` desta base e `git add` o pularia EM SILENCIO — ja custou um 404 de icone em
  # producao. O byte mora aqui, onde nenhum filtro de caminho alcanca.
  let(:tiny_png) do
    Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
  end

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def attach_icon(bytes: nil, content_type: 'image/png', filename: 'launcher.png')
    bytes ||= tiny_png
    # `identify: false` porque quem esta em teste e a NOSSA validacao de tipo, nao o farejador do
    # Marcel: sem isso, um byte de PNG rotulado 'image/gif' voltaria como 'image/png' e o exemplo
    # passaria medindo o Marcel.
    inbox.launcher_icon_image.attach(
      io: StringIO.new(bytes), filename: filename, content_type: content_type, identify: false
    )
  end

  describe 'o teto do byte (aceite 3)' do
    it 'aceita uma imagem dentro do teto de 20 KB' do
      attach_icon

      expect(inbox).to be_valid
      expect(inbox.launcher_icon_image).to be_attached
    end

    it 'recusa uma imagem acima do teto, dizendo o limite e o tamanho' do
      attach_icon(bytes: 'x' * (WidgetAppearanceSchema::MAX_LAUNCHER_ICON_BYTES + 1))

      expect(inbox).not_to be_valid
      expect(inbox.errors[:launcher_icon_image].join).to include('20480').and include('20481')
    end

    it 'o teto e 20 KB — o numero, e nao o que alguem lembrar dele' do
      expect(WidgetAppearanceSchema::MAX_LAUNCHER_ICON_BYTES).to eq(20 * 1024)
    end

    it 'aceita WebP, que e o formato do plano' do
      attach_icon(content_type: 'image/webp', filename: 'launcher.webp')

      expect(inbox).to be_valid
    end

    it 'recusa SVG, que e documento executavel servido do nosso proprio dominio' do
      attach_icon(bytes: '<svg onload="alert(1)"/>', content_type: 'image/svg+xml', filename: 'x.svg')

      expect(inbox).not_to be_valid
      expect(inbox.errors[:launcher_icon_image].join).to include('image/webp, image/png')
    end
  end

  describe 'o endereco do byte (aceite 4)' do
    before { attach_icon }

    it 'e absoluto e no NOSSO dominio — o `<img>` nasce no DOM do site do cliente' do
      inbox.save!

      expect(inbox.launcher_icon_image_url).to start_with("#{ENV.fetch('FRONTEND_URL', nil)}/rails/active_storage/blobs/proxy/")
    end

    it 'usa a rota de PROXY, e nao a de redirect' do
      inbox.save!

      # A rota de redirect devolve 302 para o servico (o bucket S3, na frota). Origem estranha: o
      # CSP do site do cliente (R18) barra a imagem e ninguem fica sabendo.
      expect(inbox.launcher_icon_image_path).to include('/proxy/')
      expect(inbox.launcher_icon_image_path).not_to include('/redirect/')
    end

    it 'recusa uma CDN externa na escrita, com o motivo — e nao aceita-e-ignora' do
      inbox.save!
      inbox.widget_appearance = { 'launcher_icon' => { 'mode' => 'image', 'url' => 'https://cdn.exemplo.com/x.png' } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_appearance].join).to include('served from our own domain')
    end

    it 'recusa a URL sem esquema (`//host/x.png`), que o navegador leria como externa' do
      inbox.save!
      inbox.widget_appearance = { 'launcher_icon' => { 'mode' => 'image', 'url' => '//cdn.exemplo.com/x.png' } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_appearance].join).to include('served from our own domain')
    end

    it 'recusa endereco escrito a mao, mesmo do nosso dominio: quem produz o endereco e o upload' do
      inbox.save!
      inbox.widget_appearance = { 'launcher_icon' => { 'mode' => 'image', 'url' => '/qualquer/coisa.png' } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_appearance].join).to include('handwritten launcher icon address')
    end

    it 'aceita o endereco que o proprio servidor produziu' do
      inbox.save!
      inbox.widget_appearance = { 'launcher_icon' => { 'mode' => 'image', 'url' => inbox.launcher_icon_image_path } }

      expect(inbox).to be_valid
    end
  end

  describe 'o schema aceita as DUAS formas' do
    it 'a string continua valendo — e o default de fabrica' do
      inbox.update!(widget_appearance: { 'launcher_icon' => 'agent_photo' })

      expect(inbox.reload.widget_appearance['launcher_icon']).to eq('agent_photo')
    end

    it 'o objeto `{mode}` vale, que e a forma que o widget recebe' do
      attach_icon
      inbox.widget_appearance = { 'launcher_icon' => { 'mode' => 'image' } }

      expect(inbox).to be_valid
    end

    it 'chave nova DENTRO do objeto e recusada: um segredo nao pode so mudar de endereco' do
      attach_icon
      inbox.widget_appearance = { 'launcher_icon' => { 'mode' => 'image', 'api_token' => 'sk-live-1' } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_appearance].join).to include('launcher_icon/api_token')
    end

    it 'modo desconhecido na forma de string continua recusado, nomeando os aceitos' do
      inbox.widget_appearance = { 'launcher_icon' => 'stock_photo' }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_appearance].join).to include('default, image, agent_photo')
    end

    it 'modo desconhecido DENTRO do objeto tambem e recusado' do
      inbox.widget_appearance = { 'launcher_icon' => { 'mode' => 'stock_photo' } }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_appearance].join).to include('default, image, agent_photo')
    end
  end

  describe 'modo `image` sem imagem' do
    it 'e recusado na escrita, para o administrador ouvir agora e nao descobrir no site' do
      inbox.widget_appearance = { 'launcher_icon' => 'image' }

      expect(inbox).not_to be_valid
      expect(inbox.errors[:widget_appearance].join).to include('without a photo')
    end

    it 'nao torna inatualizavel a inbox que JA estava assim' do
      # `update_column` de proposito: e a UNICA forma de fabricar a linha legada que existia
      # antes desta validacao — passar pelo modelo seria recusado por ela.
      inbox.update_column(:additional_attributes, { 'widget_appearance' => { 'launcher_icon' => 'image' } }) # rubocop:disable Rails/SkipsModelValidations
      inbox.reload

      expect(inbox.update(name: 'nome novo')).to be(true)
    end
  end

  describe '#resolved_widget_appearance' do
    it 'entrega `{mode, url}` quando ha imagem — que e a forma que o SDK sabe ler' do
      attach_icon
      inbox.widget_appearance = { 'launcher_icon' => { 'mode' => 'image' } }
      inbox.save!

      expect(inbox.resolved_widget_appearance['launcher_icon']).to eq(
        { 'mode' => 'image', 'url' => inbox.launcher_icon_image_url }
      )
    end

    it 'degrada para `default` quando o modo e `image` e a imagem sumiu (aceite 6, no servidor)' do
      inbox.update_column(:additional_attributes, { 'widget_appearance' => { 'launcher_icon' => 'image' } }) # rubocop:disable Rails/SkipsModelValidations

      expect(inbox.reload.resolved_widget_appearance['launcher_icon']).to eq('default')
    end

    it 'nao deixa vazar chave sobrando de DENTRO de `launcher_icon`' do
      attach_icon
      inbox.save!
      # Escrita direta no banco: e o unico caminho que sobra depois do `additionalProperties: false`,
      # e e justamente o que a projecao aninhada existe para conter.
      inbox.update_column( # rubocop:disable Rails/SkipsModelValidations
        :additional_attributes,
        { 'widget_appearance' => { 'launcher_icon' => { 'mode' => 'image', 'internal_note' => 'segredo' } } }
      )

      expect(inbox.reload.resolved_widget_appearance['launcher_icon'].keys).to eq(%w[mode url])
    end

    it 'a projecao de leitura cobre TODA chave que a escrita aceita' do
      # `resolved_widget_appearance` entrega por `slice(*DEFAULTS.keys)`. Uma chave declarada no
      # SCHEMA e ausente do DEFAULTS seria aceita na escrita e descartada na leitura — a mentira
      # que este bloco existe para matar, so que num campo futuro. E o gemeo, para a aparencia,
      # do que `widget_tracking_schema_spec.rb:291` ja cobra para o tracking.
      expect(WidgetAppearanceSchema::SCHEMA['properties'].keys)
        .to match_array(WidgetAppearanceSchema::DEFAULTS.keys)
    end

    it 'o nivel de DENTRO de `launcher_icon` tambem: o entregue e o declarado' do
      declared = WidgetAppearanceSchema::SCHEMA['properties']['launcher_icon']['else']['properties'].keys

      attach_icon
      inbox.widget_appearance = { 'launcher_icon' => { 'mode' => 'image' } }
      inbox.save!

      expect(inbox.resolved_widget_appearance['launcher_icon'].keys).to match_array(declared)
    end

    it 'inbox nova nasce com `default` — o balao na cor da marca (D5)' do
      expect(create(:inbox, account: account).resolved_widget_appearance['launcher_icon']).to eq('default')
    end
  end
end
