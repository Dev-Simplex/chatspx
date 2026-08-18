#!/usr/bin/env ruby
# frozen_string_literal: true

# Gera `spec/fixtures/widget_brand_tokens.json` — a referência canônica dos
# tokens de marca para 20 cores fixas.
#
# POR QUE O RUBY GERA, e não o JavaScript: a derivação canônica é a do
# SERVIDOR (23-plano §B.2.3). `useContrast.js` roda no navegador e existe para
# EXIBIR na tela o que o servidor vai fazer; se as duas contas divergirem, a
# tela mente para o cliente. A fixture sai daqui — de `WidgetTokens`, o mesmo
# objeto que escreve o `<style>` do widget em produção — e o spec do dashboard
# a lê. Assim o cruzamento é entre duas implementações independentes, em duas
# linguagens, e não entre uma função e ela mesma.
#
# Uso:  ruby scripts/gerar-fixture-tokens-marca.rb

require 'json'
require_relative '../app/services/widget_tokens'

# 20 cores: o verde do fork, o azul que a heurística YIQ erra, marcas escuras,
# marcas quase-brancas, amarelos (o caso difícil de escurecer) e cinzas.
CORES = %w[
  #2dc46f #009ce0 #e11d48 #007aff #0b2545
  #f5a623 #6b21a8 #14b8a6 #facc15 #1e293b
  #dc2626 #7c3aed #059669 #ea580c #0ea5e9
  #64748b #fde047 #831843 #ffffff #111111
].freeze

fixture = {
  gerado_por: 'scripts/gerar-fixture-tokens-marca.rb',
  fonte: 'WidgetTokens (app/services/widget_tokens.rb) — a derivação canônica, no servidor',
  limiar_on_brand: WidgetTokens::LUMINANCE_THRESHOLD,
  alvo_texto: WidgetTokens::READABLE_TARGET,
  surface_light: WidgetTokens::SURFACE_LIGHT,
  surface_dark: WidgetTokens::SURFACE_DARK,
  cores: CORES.map do |brand|
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
}

destino = File.expand_path('../spec/fixtures/widget_brand_tokens.json', __dir__)
File.write(destino, "#{JSON.pretty_generate(fixture)}\n")
puts "#{fixture[:cores].size} cores derivadas pelo servidor -> #{destino}"
