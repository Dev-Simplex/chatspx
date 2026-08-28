# frozen_string_literal: true

require 'json'
require_relative '../../app/services/widget_tokens'

# A RECEITA da fixture `spec/fixtures/widget_brand_tokens.json`, num lugar só.
#
# Por que um módulo e não tudo dentro do script: quem gera e quem CONFERE têm de
# ser o mesmo código. `scripts/gerar-fixture-tokens-marca.rb` chama `write!`;
# `spec/services/widget_brand_tokens_fixture_spec.rb` chama `render` e compara
# com o arquivo commitado. Se a conferência tivesse a receita copiada, ela
# passaria a medir a cópia — e a fixture voltaria a envelhecer em silêncio, que
# é exatamente o defeito que este bloco (3.08) conserta:
#
#   `useContrast.js` usava `SURFACE.dark = '#121213'` (o fundo do PAINEL)
#   enquanto `WidgetTokens::SURFACE_DARK` já era `'#2c2d36'` (o balão do
#   agente, corrigido pelo bloco 2.03). A fixture commitada era um retrato do
#   servidor ANTERIOR, então o spec do dashboard cruzava a tela com um servidor
#   que não existe mais e ficava verde. Regenerando pelo gerador oficial,
#   20 de 20 cores divergiam e 13 tokens hex mudavam.
#
# A trava tem dois elos, e os dois precisam existir:
#   1. este spec Ruby quebra quando a fixture não é mais o que o servidor deriva;
#   2. `specs/useContrast.spec.js` quebra quando o medidor não bate com a fixture.
# Mudar `WidgetTokens` sem regenerar deixa (1) vermelho; regenerar sem alinhar o
# JS deixa (2) vermelho. Não há caminho em que os dois lados divirjam em verde.
module WidgetBrandTokensFixture
  # 20 cores: o verde do fork, o azul que a heurística YIQ erra, marcas escuras,
  # marcas quase-brancas, amarelos (o caso difícil de escurecer) e cinzas.
  CORES = %w[
    #2dc46f #009ce0 #e11d48 #007aff #0b2545
    #f5a623 #6b21a8 #14b8a6 #facc15 #1e293b
    #dc2626 #7c3aed #059669 #ea580c #0ea5e9
    #64748b #fde047 #831843 #ffffff #111111
  ].freeze

  PATH = File.expand_path('../../spec/fixtures/widget_brand_tokens.json', __dir__)

  # O comando que conserta a fixture quando ela envelhece. Fica aqui para a
  # mensagem de falha do spec dizer o que fazer, em vez de só dizer que falhou.
  COMANDO = 'ruby scripts/gerar-fixture-tokens-marca.rb'

  module_function

  def build
    {
      gerado_por: 'scripts/gerar-fixture-tokens-marca.rb',
      fonte: 'WidgetTokens (app/services/widget_tokens.rb) — a derivação canônica, no servidor',
      limiar_on_brand: WidgetTokens::LUMINANCE_THRESHOLD,
      alvo_texto: WidgetTokens::READABLE_TARGET,
      surface_light: WidgetTokens::SURFACE_LIGHT,
      surface_dark: WidgetTokens::SURFACE_DARK,
      cores: CORES.map { |brand| entrada(brand) }
    }
  end

  def entrada(brand)
    tokens = WidgetTokens.new(brand)
    {
      brand: brand,
      luminance: WidgetTokens.relative_luminance(brand),
      on_brand: tokens.on_brand,
      contrast: {
        # 1. texto sobre a cor da marca — alvo 4,5:1
        text_on_brand: tokens.contrast_on_brand,
        # 2. a marca COMO TEXTO em fundo claro — alvo 4,5:1
        brand_as_text_light: WidgetTokens.contrast_ratio(brand, WidgetTokens::SURFACE_LIGHT),
        # 3. a marca COMO TEXTO em fundo escuro — alvo 4,5:1
        brand_as_text_dark: WidgetTokens.contrast_ratio(brand, WidgetTokens::SURFACE_DARK),
        # e o que sobra DEPOIS do ajuste, que é o que o visitante realmente vê
        readable_light_on_surface: WidgetTokens.contrast_ratio(
          tokens.brand_readable, WidgetTokens::SURFACE_LIGHT
        ),
        readable_dark_on_surface: WidgetTokens.contrast_ratio(
          tokens.brand_readable_dark, WidgetTokens::SURFACE_DARK
        )
      },
      tokens: tokens.root_tokens
    }
  end

  # O CONTEÚDO exato do arquivo — byte a byte, com a quebra de linha final.
  # Comparar o texto renderizado (e não o JSON já parseado) faz a conferência
  # pegar também deriva de formatação, que é o que produz diff sujo depois.
  def render
    "#{JSON.pretty_generate(build)}\n"
  end

  def write!
    File.write(PATH, render)
    PATH
  end
end
