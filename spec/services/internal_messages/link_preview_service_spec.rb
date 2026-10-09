# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalMessages::LinkPreviewService do
  let(:html) do
    <<~HTML
      <html><head>
        <title>Título da aba</title>
        <meta property="og:title" content="Proposta Residencial Jardim">
        <meta property="og:description" content="Apartamento de 2 dormitórios com vaga.">
        <meta property="og:image" content="/img/capa.jpg">
        <meta property="og:site_name" content="Imobiliária Exemplo">
      </head><body>oi</body></html>
    HTML
  end

  def resolve(host, ip)
    allow(Resolv).to receive(:getaddresses).with(host).and_return([ip])
  end

  it 'reads the Open Graph of a public https page' do
    resolve('www.exemplo.com.br', '93.184.216.34')
    stub_request(:get, 'https://www.exemplo.com.br/imovel/1')
      .to_return(status: 200, body: html, headers: { 'Content-Type' => 'text/html; charset=utf-8' })

    preview = described_class.new('https://www.exemplo.com.br/imovel/1').perform

    expect(preview).to include(
      'title' => 'Proposta Residencial Jardim', 'description' => 'Apartamento de 2 dormitórios com vaga.',
      'image' => 'https://www.exemplo.com.br/img/capa.jpg', 'domain' => 'exemplo.com.br', 'site_name' => 'Imobiliária Exemplo'
    )
  end

  describe 'SSRF' do
    {
      'localhost' => '127.0.0.1', 'metadata' => '169.254.169.254', 'rede interna' => '10.0.0.5',
      'rede 192.168' => '192.168.1.10', 'IPv6 loopback' => '::1', 'IPv4 mapeado em IPv6' => '::ffff:127.0.0.1'
    }.each do |label, ip|
      it "never connects to #{label} (#{ip})" do
        resolve('interno.exemplo.com', ip)

        expect(described_class.new('http://interno.exemplo.com/admin').perform).to be_nil
        expect(a_request(:get, /interno\.exemplo\.com/)).not_to have_been_made
      end
    end

    it 'refuses a redirect that points to a private address' do
      resolve('publico.com', '93.184.216.34')
      resolve('127.0.0.1', '127.0.0.1')
      stub_request(:get, 'http://publico.com/').to_return(status: 302, headers: { 'Location' => 'http://127.0.0.1/segredo' })

      expect(described_class.new('http://publico.com/').perform).to be_nil
      expect(a_request(:get, 'http://127.0.0.1/segredo')).not_to have_been_made
    end

    it 'only accepts http and https' do
      expect(described_class.new('ftp://exemplo.com/arquivo').perform).to be_nil
      expect(described_class.new('file:///etc/passwd').perform).to be_nil
    end
  end

  it 'returns nil (no card, no error) when the page is not html or fails' do
    resolve('arquivo.com', '93.184.216.34')
    stub_request(:get, 'https://arquivo.com/video.mp4').to_return(status: 200, body: 'x', headers: { 'Content-Type' => 'video/mp4' })
    resolve('fora.com', '93.184.216.34')
    stub_request(:get, 'https://fora.com/').to_timeout

    expect(described_class.new('https://arquivo.com/video.mp4').perform).to be_nil
    expect(described_class.new('https://fora.com/').perform).to be_nil
  end
end
