# frozen_string_literal: true

require 'rails_helper'

# 5.07 (T-C2.0) — ACEITE: "uma versao nova do `sdk.js` chega a um navegador que ja tinha a
# antiga EM MINUTOS".
#
# O que torna isso verdade e o par (janela curta + validador): sem janela curta o navegador
# nao volta a perguntar; sem validador, quando ele perguntar, a resposta vem com o corpo
# inteiro em vez de um 304. Os dois sao medidos aqui.
RSpec.describe SdkCachePolicy do
  # App de baixo que devolve o que o `ActionDispatch::Static` devolveria hoje: o ano de
  # cache que sai de `config.public_file_server.headers`.
  let(:ano) { "public, max-age=#{1.year.to_i}" }
  let(:downstream) { ->(_env) { [200, { 'Cache-Control' => ano, 'ETag' => 'W/"abc"' }, ['sdk']] } }
  let(:middleware) { described_class.new(downstream) }

  def get(path, method: 'GET')
    middleware.call('PATH_INFO' => path, 'REQUEST_METHOD' => method)
  end

  describe 'no caminho do SDK' do
    it 'troca o ano por uma janela de minutos, com revalidacao' do
      _status, headers, _body = get('/packs/js/sdk.js')

      expect(headers['Cache-Control']).to eq('public, max-age=300, must-revalidate')
      expect(described_class::MAX_AGE).to be <= 15.minutes.to_i
    end

    it 'PRESERVA o validador — sem ele a revalidacao devolveria o arquivo inteiro, nao um 304' do
      _status, headers, _body = get('/packs/js/sdk.js')

      expect(headers['ETag']).to eq('W/"abc"')
    end

    it 'vale tambem para HEAD, que e o que um proxy usa para revalidar' do
      _status, headers, _body = get('/packs/js/sdk.js', method: 'HEAD')

      expect(headers['Cache-Control']).to eq(described_class::CACHE_CONTROL)
    end

    it 'cobre tambem o coletor de origem, que e artefato do SDK com o mesmo problema' do
      _status, headers, _body = get('/packs/js/tracking.js')

      expect(headers['Cache-Control']).to eq(described_class::CACHE_CONTROL)
    end

    it 'nao mexe no corpo nem no status' do
      status, _headers, body = get('/packs/js/sdk.js')

      expect(status).to eq(200)
      expect(body).to eq(['sdk'])
    end
  end

  describe 'fora do caminho do SDK' do
    # Caminho com fingerprint DEVE continuar com o ano: trocar isso seria pagar banda para
    # resolver um problema que o fingerprint ja resolve.
    it 'deixa o asset com hash no cache longo' do
      _status, headers, _body = get('/vite/assets/widget-abc123.js')

      expect(headers['Cache-Control']).to eq(ano)
    end

    it 'deixa qualquer outro arquivo de /packs/js intacto — a lista e de caminhos exatos' do
      _status, headers, _body = get('/packs/js/outro.js')

      expect(headers['Cache-Control']).to eq(ano)
    end

    it 'nao toca em requisicao que nao seja de leitura' do
      _status, headers, _body = get('/packs/js/sdk.js', method: 'POST')

      expect(headers['Cache-Control']).to eq(ano)
    end
  end

  # A instalacao e metade do bloco: um middleware correto fora da pilha nao muda nada, e
  # ficaria verde no spec de unidade acima.
  describe 'instalacao na pilha' do
    it 'esta na pilha do Rails' do
      expect(Rails.application.middleware.map(&:name)).to include('SdkCachePolicy')
    end

    it 'embrulha o ActionDispatch::Static — precisa VER a resposta pronta na volta' do
      nomes = Rails.application.middleware.map(&:name)
      estatico = nomes.index('ActionDispatch::Static')

      # Sem `ActionDispatch::Static` na pilha (RAILS_SERVE_STATIC_FILES desligado) nao ha
      # ordem a conferir — e o arquivo sai pelo nginx, caso declarado no cabecalho do
      # middleware.
      skip('ActionDispatch::Static fora da pilha neste ambiente') if estatico.nil?

      expect(nomes.index('SdkCachePolicy')).to be < estatico
    end
  end
end
