# frozen_string_literal: true

# Este spec roda SEM Rails e SEM banco de propósito: `WidgetTokens` é Ruby puro
# (aritmética sobre três inteiros), e um teste de fórmula que precisa de
# Postgres é um teste que ninguém roda. `.rspec` já carrega `spec_helper`.
require_relative '../../app/services/widget_tokens'

# ── A TOLERÂNCIA, E POR QUE ELA É ESTA ─────────────────────────────────────
# O aceite do bloco 1.02 manda `toBeCloseTo(x, 2)` e proíbe igualdade exata.
# `toBeCloseTo(x, 2)` é, por definição do Jest/Vitest, `|recebido − esperado|
# < 0,5 × 10⁻²` = 0,005. O equivalente em RSpec é `be_within(0.005).of(x)`.
# Comparar razão de contraste por igualdade já custou meio dia nesta casa: o
# valor é o resultado de dois `**2.4` encadeados, e o último bit depende da
# libm da máquina.
TOL = 0.005

RSpec.describe WidgetTokens do
  describe 'a fórmula WCAG (o aceite numérico do bloco 1.02)' do
    it 'manda #009CE0 para preto puro, a 6,83:1' do
      tokens = described_class.new('#009CE0')

      expect(tokens.on_brand).to eq('#000000')
      expect(tokens.contrast_on_brand).to be_within(TOL).of(6.8318)
    end

    it 'manda #2DC46F para preto puro, a 9,24:1' do
      tokens = described_class.new('#2DC46F')

      expect(tokens.on_brand).to eq('#000000')
      expect(tokens.contrast_on_brand).to be_within(TOL).of(9.2371)
    end

    it 'entrega no mínimo 4,5:1 — o preto escolhido não é palpite, é o maior dos dois' do
      tokens = described_class.new('#009CE0')

      expect(described_class.contrast_ratio(tokens.brand, '#ffffff')).to be_within(TOL).of(3.0739)
      expect(tokens.contrast_on_brand).to be > described_class.contrast_ratio(tokens.brand, '#ffffff')
    end

    it 'vira branco quando a marca é escura — o limiar 0,17913 funciona nos dois sentidos' do
      # #1a1a1a tem L = 0,0103, muito abaixo do limiar.
      dark_brand = described_class.new('#1a1a1a')
      expect(described_class.relative_luminance('#1a1a1a')).to be < described_class::LUMINANCE_THRESHOLD
      expect(dark_brand.on_brand).to eq('#ffffff')

      # Uma marca logo ACIMA do limiar tem de escolher preto.
      light_brand = described_class.new('#767676')
      expect(described_class.relative_luminance('#767676')).to be > described_class::LUMINANCE_THRESHOLD
      expect(light_brand.on_brand).to eq('#000000')
    end

    it 'só altera a marca do cliente quando ela seria ilegível como texto' do
      # #2dc46f sobre branco dá 2,27:1 — falha. O readable tem de cruzar 4,5:1.
      readable = described_class.new('#2dc46f').brand_readable
      expect(described_class.contrast_ratio('#2dc46f', '#ffffff')).to be_within(TOL).of(2.2734)
      expect(described_class.contrast_ratio(readable, '#ffffff')).to be >= 4.5

      # Sobre o fundo escuro do widget ela já passa: volta INTACTA.
      expect(described_class.new('#2dc46f').brand_readable_dark).to eq('#2dc46f')
      expect(described_class.contrast_ratio('#2dc46f', described_class::SURFACE_DARK)).to be >= 4.5
    end
  end

  describe 'a cor inválida do banco não é interpolada no <style>' do
    # `channel_web_widgets.widget_color` é string livre. Estes são os payloads
    # que fecham o `}` do bloco e abrem regra própria.
    injections = [
      '#fff;} :root{--w-brand:red} .x{color:url(javascript:alert(1))',
      '</style><script>alert(1)</script>',
      'red',
      'rgb(0,156,224)',
      '#00zzff',
      '',
      nil
    ]

    injections.each do |payload|
      it "não deixa passar #{payload.inspect}" do
        css = described_class.new(payload).css

        expect(css).not_to include(payload.to_s) if payload.to_s.length > 3
        expect(css).to include("--w-brand:#{described_class::DEFAULT_BRAND}")
        # A saída inteira é só nome de token, `:`, `;`, `{`, `}`, hex e `var()`.
        expect(css).to match(/\A[-a-zA-Z0-9#:;{}.()]+\z/)
      end
    end

    it 'aceita o formato curto e normaliza para #rrggbb minúsculo' do
      expect(described_class.new('#0F0').brand).to eq('#00ff00')
      expect(described_class.new('#009CE0').brand).to eq('#009ce0')
    end
  end

  describe 'o bloco .dark sai do mesmo <style> — a armadilha do cascade' do
    # `_tokens.scss` declara os fallbacks dentro de `@layer base`. No cascade,
    # regra SEM camada vence regra EM camada, qualquer que seja a
    # especificidade. Se o servidor emitisse só `:root`, ele venceria o
    # `.dark { … }` de `_tokens.scss` e o tema escuro herdaria a variante clara.
    it 'emite :root e .dark' do
      css = described_class.new('#009ce0').css

      expect(css).to start_with(':root{')
      expect(css).to include('}.dark{')
      expect(css).to include('--w-brand-readable:var(--w-brand-readable-dark)')
    end
  end

  describe 'os fallbacks do SCSS são os mesmos que este serviço calcula' do
    # Fórmula duplicada é fórmula que diverge. Aqui o SCSS e o Ruby são
    # comparados: mexer num só quebra este teste.
    #
    # ⚠️ O CAMINHO MUDOU, e a guarda estava QUEBRADA — achado do bloco 2.03.
    # O bloco 3.10 recortou os valores de `_tokens.scss` para
    # `_tokens_values.scss` (para o preview do dashboard consumir os mesmos
    # mixins) e não moveu este caminho junto. Desde `ce5b47aa6e` os seis
    # exemplos abaixo liam um arquivo que já não declara token nenhum, a regex
    # devolvia `nil` e os seis falhavam. Uma guarda contra divergência que está
    # vermelha há semanas não guarda nada: ela vira ruído que se aprende a
    # ignorar, e foi exatamente sob ela que `SURFACE_DARK` pôde ficar calibrado
    # contra a superfície errada.
    let(:scss) { File.read(File.expand_path('../../app/javascript/widget/assets/scss/_tokens_values.scss', __dir__)) }
    let(:tokens) { described_class.new('#2dc46f') }

    {
      '--w-brand' => :brand,
      '--w-brand-hover' => :brand_hover,
      '--w-brand-active' => :brand_active,
      '--w-on-brand' => :on_brand,
      '--w-brand-readable' => :brand_readable,
      '--w-brand-readable-dark' => :brand_readable_dark
    }.each do |css_name, method|
      it "#{css_name} bate" do
        declared = scss[/^\s*#{Regexp.escape(css_name)}:\s*([^;]+);/, 1]
        expect(declared).to eq(tokens.public_send(method))
      end
    end

    it 'a regex acha ALGUMA coisa — a guarda não pode voltar a comparar nil' do
      # Sem esta linha, mover os valores de arquivo outra vez faria os seis
      # exemplos acima falharem com `nil`, e alguém poderia lê-los como
      # "divergiu" em vez de "a guarda perdeu o arquivo". Foi o que aconteceu.
      expect(scss).to include('--w-brand:')
    end
  end

  describe 'a superfície escura de referência é o BALÃO, não o painel' do
    # Achado do bloco 2.03, medido em Chromium: `--w-brand-readable-dark` pinta
    # o link dentro do balão do agente, e no tema escuro esse balão é
    # `bg-n-solid-3` (#2c2d36) — mais claro que o painel (#121213). Calibrando
    # contra o painel, o link chegava ao balão ABAIXO de 4,5:1.
    it 'é a mesma cor que `--solid-3` do tema escuro' do
      values = File.read(File.expand_path('../../app/javascript/widget/assets/scss/_tokens_values.scss', __dir__))
      dark = values[/@mixin widget-palette-dark.*?\n\}/m]
      channels = dark[/^\s*--solid-3:\s*([^;]+);/, 1].split.map(&:to_i)

      expect(described_class.hex(channels)).to eq(described_class::SURFACE_DARK)
    end

    it 'as duas cores de teste e o DEFAULT cruzam 4,5:1 sobre o balão escuro' do
      # `#1f93ff` é o default de `channel_web_widgets.widget_color`: antes do
      # ajuste ele media 4,3470:1, ou seja, a inbox que ninguém configurou
      # nascia reprovando o aceite 2 da §C.5.
      ['#009CE0', '#2DC46F', described_class::DEFAULT_BRAND].each do |brand|
        readable = described_class.new(brand).brand_readable_dark
        expect(described_class.contrast_ratio(readable, described_class::SURFACE_DARK)).to be >= 4.5
      end
    end

    it 'a marca que já passava volta INTACTA' do
      # O serviço só altera a marca do cliente quando ela seria ilegível. Mudar
      # a superfície de referência não pode transformar isso em "mexe sempre".
      expect(described_class.new('#2dc46f').brand_readable_dark).to eq('#2dc46f')
    end
  end

  describe 'o ERB emite os tokens ANTES do primeiro paint' do
    # O ganho do bloco é NÃO ter o flash de cor errada. Isso depende de posição
    # no arquivo, e posição no arquivo é verificável sem browser.
    let(:erb) { File.read(File.expand_path('../../app/views/widgets/show.html.erb', __dir__)).lines }
    let(:style_line) { erb.index { |l| l.include?('WidgetTokens') && l.include?('css') } }
    let(:vite_line) { erb.index { |l| l.include?("vite_javascript_tag 'widget'") } }

    it 'coloca o <style> dos tokens antes do vite_javascript_tag' do
      expect(style_line).not_to be_nil, 'show.html.erb não emite o <style> de WidgetTokens'
      expect(vite_line).not_to be_nil
      expect(style_line).to be < vite_line
    end

    it 'entrega os tokens ao canal, para o launcher que vive fora do iframe' do
      expect(erb.join).to include('tokens:')
    end
  end
end
