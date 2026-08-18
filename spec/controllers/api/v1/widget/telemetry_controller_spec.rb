# frozen_string_literal: true

require 'rails_helper'

# Mecanismo de aceite do bloco 2.13 — a ponta HTTP.
#
# ACEITE (§2.2): «Erro forçado aparece no GlitchTip com PII removida; nada vaza
# para o `window.onerror` do site do cliente».
#
# ARMADILHA DESTE ARQUIVO, a mesma do bloco 1.12: o `Rack::Attack` tem safelist
# para 127.0.0.1 (`rack_attack.rb:28-31,49`), e request spec roda como 127.0.0.1
# por padrão — um teste ingênuo de throttle passa verde sem NUNCA exercitar a
# regra. Por isso todo request daqui carrega um `REMOTE_ADDR` fora da safelist.
RSpec.describe 'Api::V1::Widget::Telemetry', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:client_ip) { '203.0.113.91' }

  let(:payload) do
    {
      website_token: web_widget.website_token,
      name: 'TypeError',
      message: 'falha ao enviar',
      stack: 'at envia (widget.js:1:1)',
      url: 'https://loja.test/checkout',
      release: 'abc123',
      context: { origem: 'store/contacts' }
    }
  end

  def post_report(corpo, ip: client_ip)
    post '/api/v1/widget/telemetry', params: corpo, headers: { 'REMOTE_ADDR' => ip }, as: :json
    response.status
  end

  describe 'POST /api/v1/widget/telemetry' do
    it 'aceita um relatório válido' do
      expect(post_report(payload)).to eq(204)
    end

    it 'recusa website_token desconhecido' do
      expect(post_report(payload.merge(website_token: 'nao-existe'))).to eq(404)
    end

    it 'NÃO exige contato — o erro pode ser anterior a ele existir' do
      # Herdar de `Api::V1::Widget::BaseController` traria `set_contact`, que
      # levanta `RecordNotFound` sem `contact_inbox`. Boa parte dos erros que
      # queremos ver acontece antes de haver contato, inclusive erros NA criação
      # dele — a telemetria falharia exatamente nos casos mais interessantes.
      expect(web_widget.inbox.contact_inboxes).to be_empty
      expect(post_report(payload)).to eq(204)
    end

    it 'DESCARTA chaves fora da lista, em vez de rejeitar' do
      # A mensagem que o visitante digitou é o dado mais sensível que o widget
      # toca. Um cliente adulterado (ou um build antigo em cache) não pode
      # despejá-la aqui. Descartar e não rejeitar: um 4xx faria o widget tentar
      # de novo, e telemetria não pode virar tráfego de retentativa no site do
      # cliente.
      relatorio = nil
      allow(Widget::ErrorReport).to receive(:new) do |params, _widget|
        relatorio = params
        instance_double(Widget::ErrorReport, perform: true)
      end

      status = post_report(payload.merge(
                             content: 'meu cartão é 4111 1111 1111 1111',
                             mensagem_do_visitante: 'oi, sou a Maria'
                           ))

      expect(status).to eq(204)
      expect(relatorio.keys).to match_array(%w[website_token name message stack url release context])
      expect(relatorio.to_json).not_to include('4111')
      expect(relatorio.to_json).not_to include('sou a Maria')
    end

    it 'também descarta chaves extras DENTRO do contexto' do
      relatorio = nil
      allow(Widget::ErrorReport).to receive(:new) do |params, _widget|
        relatorio = params
        instance_double(Widget::ErrorReport, perform: true)
      end

      post_report(payload.merge(context: { origem: 'chat', email_do_visitante: 'maria@teste.com' }))

      expect(relatorio[:context].keys).to eq(['origem'])
    end
  end

  describe 'throttle do endpoint público' do
    around do |example|
      previous_store = Rack::Attack.cache.store
      previous_enabled = Rack::Attack.enabled
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.enabled = true
      example.run
    ensure
      Rack::Attack.enabled = previous_enabled
      Rack::Attack.cache.store = previous_store
    end

    it 'deixa passar as 20 primeiras e bloqueia a 21ª do mesmo IP' do
      statuses = Array.new(20) { post_report(payload) }

      expect(statuses.count(429)).to eq(0)
      expect(post_report(payload)).to eq(429)
    end

    it 'não bloqueia outro IP que ainda não gastou a cota' do
      21.times { post_report(payload) }
      expect(post_report(payload)).to eq(429)

      expect(post_report(payload, ip: '198.51.100.31')).not_to eq(429)
    end

    it 'o throttle é INVISÍVEL a partir de 127.0.0.1 — e é por isso que não validamos de lá' do
      # Asserção deliberadamente estranha: ela documenta a armadilha. Se um dia
      # a safelist de localhost sair, este exemplo falha e avisa que os outros
      # dois podem ser simplificados.
      statuses = Array.new(25) { post_report(payload, ip: '127.0.0.1') }

      expect(statuses.count(429)).to eq(0)
    end
  end
end
