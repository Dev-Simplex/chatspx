# frozen_string_literal: true

# A TRAVA DA DEFASAGEM (bloco 3.08).
#
# `spec/fixtures/widget_brand_tokens.json` é a ponte entre o servidor e o
# medidor de contraste da tela de aparência: o Ruby (`WidgetTokens`) gera, o
# spec do dashboard (`composables/specs/useContrast.spec.js`) lê e exige que
# `useContrast.js` chegue nos mesmos hexadecimais em 20 cores.
#
# Só que uma fixture commitada é um RETRATO. Ela não avisa quando envelhece, e
# foi isso que aconteceu: o bloco 2.03 corrigiu `SURFACE_DARK` de `#121213` (o
# fundo do painel) para `#2c2d36` (o balão do agente, que é onde o link
# realmente é pintado), ninguém regerou o arquivo, e o cruzamento das 20 cores
# continuou verde comparando a tela com um servidor que não existe mais.
# Medido ao regerar pelo gerador oficial: 20 de 20 cores divergiam e 13 tokens
# hex mudavam de valor.
#
# Este spec é o elo que faltava. Ele roda SEM Rails e SEM banco de propósito —
# é leitura de arquivo e aritmética sobre três inteiros, e um teste de fórmula
# que precisa de Postgres é um teste que ninguém roda.
require_relative '../../scripts/lib/widget_brand_tokens_fixture'

RSpec.describe WidgetBrandTokensFixture do
  # `toBeCloseTo(x, 2)` do lado JS é |recebido − esperado| < 0,005. Aqui vale o
  # mesmo: o valor sai de dois `**2.4` encadeados e o último bit depende da libm.
  let(:tol) { 0.005 }

  let(:arquivo) { File.read(described_class::PATH) }
  let(:commitada) { JSON.parse(arquivo) }
  let(:derivada) { JSON.parse(described_class.render) }

  describe 'a fixture commitada × o servidor de HOJE' do
    it 'declara as mesmas constantes que WidgetTokens' do
      expect(commitada.slice('limiar_on_brand', 'alvo_texto', 'surface_light', 'surface_dark')).to eq(
        'limiar_on_brand' => WidgetTokens::LUMINANCE_THRESHOLD,
        'alvo_texto' => WidgetTokens::READABLE_TARGET,
        'surface_light' => WidgetTokens::SURFACE_LIGHT,
        'surface_dark' => WidgetTokens::SURFACE_DARK
      )
    end

    it 'traz as 20 cores, cor a cor, com os mesmos tokens e as mesmas razões' do
      expect(commitada['cores'].map { |c| c['brand'] }).to eq(described_class::CORES)

      commitada['cores'].zip(derivada['cores']).each do |gravada, atual|
        # A comparação é por COR para a falha dizer qual delas envelheceu, em
        # vez de despejar 14 KB de JSON.
        expect(gravada).to eq(atual), "#{gravada['brand']} está defasada — rode `#{described_class::COMANDO}`"
      end
    end

    it 'é byte a byte o que o gerador escreve hoje' do
      # Depois das duas comparações acima, o que sobra aqui é deriva de
      # FORMATAÇÃO (indentação, ordem de chaves, quebra final). Ela não muda
      # número nenhum, mas suja o diff do próximo que regerar.
      expect(arquivo).to eq(described_class.render), "fixture defasada — rode `#{described_class::COMANDO}`"
    end
  end

  describe 'a superfície escura é a do BALÃO, não a do painel' do
    # Esta é a defasagem que existiu de verdade, escrita como teste: se alguém
    # devolver `SURFACE_DARK` para o fundo do painel, a fixture volta a
    # descrever um alvo que o balão não atinge — e este exemplo cai antes de a
    # tela voltar a mentir.
    it 'calibra o link contra #2c2d36, e é isso que faz #009CE0 e #1F93FF cruzarem 4,5:1' do
      balao = commitada.fetch('surface_dark')
      painel = '#121213'

      expect(balao).to eq('#2c2d36')

      # A condição RUIM, forçada: cor calibrada contra o painel, medida no balão.
      expect(WidgetTokens.contrast_ratio(WidgetTokens.readable_on('#009ce0', painel), balao))
        .to be_within(tol).of(4.4486)
      expect(WidgetTokens.contrast_ratio(WidgetTokens.readable_on('#1f93ff', painel), balao))
        .to be_within(tol).of(4.3470)

      # E a boa: calibrada contra o balão, que é o que a fixture grava.
      expect(WidgetTokens.contrast_ratio(WidgetTokens.readable_on('#009ce0', balao), balao))
        .to be_within(tol).of(4.6970)
      expect(WidgetTokens.contrast_ratio(WidgetTokens.readable_on('#1f93ff', balao), balao))
        .to be_within(tol).of(4.5801)
    end
  end

  describe 'o arquivo é coerente consigo mesmo' do
    # As duas comparações de cima medem fixture × código. Esta mede a fixture
    # SOZINHA: os números gravados têm de ser os das superfícies que ela própria
    # declara. É o que pega o retrato meio-editado à mão — metadado de uma
    # superfície, razões de outra —, que é a forma exata do defeito que o bloco
    # 3.08 encontrou.
    it 'as razões gravadas são as das superfícies que a própria fixture declara' do
      claro = commitada.fetch('surface_light')
      escuro = commitada.fetch('surface_dark')

      commitada['cores'].each do |cor|
        brand = cor['brand']

        expect(cor.dig('contrast', 'brand_as_text_light'))
          .to be_within(tol).of(WidgetTokens.contrast_ratio(brand, claro)), brand
        expect(cor.dig('contrast', 'brand_as_text_dark'))
          .to be_within(tol).of(WidgetTokens.contrast_ratio(brand, escuro)), brand
        expect(cor.dig('contrast', 'readable_dark_on_surface'))
          .to be_within(tol).of(
            WidgetTokens.contrast_ratio(cor.dig('tokens', '--w-brand-readable-dark'), escuro)
          ), brand
      end
    end

    it 'nenhuma das 20 cores fica sem saída: o ajuste alcança 4,5:1 nos dois temas' do
      commitada['cores'].each do |cor|
        expect(cor.dig('contrast', 'readable_light_on_surface'))
          .to be >= WidgetTokens::READABLE_TARGET - tol, cor['brand']
        expect(cor.dig('contrast', 'readable_dark_on_surface'))
          .to be >= WidgetTokens::READABLE_TARGET - tol, cor['brand']
      end
    end
  end
end
