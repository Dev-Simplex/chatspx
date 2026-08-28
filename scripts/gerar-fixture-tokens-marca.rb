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
# A receita mora em `scripts/lib/widget_brand_tokens_fixture.rb` porque
# `spec/services/widget_brand_tokens_fixture_spec.rb` confere o arquivo
# commitado contra ELA. Gerador e conferência têm de ser o mesmo código: foi
# uma fixture envelhecida em silêncio — retrato de um servidor anterior — que
# deixou o medidor da tela discordar do servidor com a suíte verde.
#
# Uso:  ruby scripts/gerar-fixture-tokens-marca.rb

require_relative 'lib/widget_brand_tokens_fixture'

destino = WidgetBrandTokensFixture.write!
puts "#{WidgetBrandTokensFixture::CORES.size} cores derivadas pelo servidor -> #{destino}"
