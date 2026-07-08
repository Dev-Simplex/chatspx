require 'rails_helper'

# Nó http_request + guarda SSRF (Flows::HttpAction / Flows::SafeHttpClient). TODAS as requisições
# externas são MOCKADAS via WebMock — NUNCA se faz uma chamada real. O WebMock roda com
# disable_net_connect!, então uma tentativa real de rede levantaria e o passo viraria `failed`
# (não `skipped`) — logo, cada asserção `skipped`+código já é prova de que nenhuma conexão vazou.
RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  after { Current.reset }

  def action(params)
    { 'type' => 'action', 'action_name' => 'http_request', 'action_params' => [params] }
  end

  def run(params)
    described_class.new(flow: flow, conversation: conversation).execute(action(params))
  end

  describe '#http_request — happy path (MOCKED)' do
    it 'POSTs to an external URL and stores the response body into a custom attribute' do
      stub = stub_request(:post, 'http://93.184.216.34/hook')
             .with(body: '{"id":"42"}', headers: { 'Content-Type' => 'application/json', 'X-Token' => 'abc' })
             .to_return(status: 200, body: 'OK-STORED')
      result = run('method' => 'post', 'url' => 'http://93.184.216.34/hook',
                   'headers' => [{ 'key' => 'X-Token', 'value' => 'abc' }],
                   'body' => '{"id":"42"}', 'target' => 'conversation', 'key' => 'webhook_reply')
      expect(result.status).to eq(:success)
      expect(stub).to have_been_requested
      expect(conversation.reload.custom_attributes['webhook_reply']).to eq('OK-STORED')
    end

    it 'does a GET with no body and no storage when no key is given' do
      stub = stub_request(:get, 'http://93.184.216.34/ping').to_return(status: 204, body: '')
      expect(run('method' => 'get', 'url' => 'http://93.184.216.34/ping').status).to eq(:success)
      expect(stub).to have_been_requested
    end

    it 'resolves Liquid in the URL, headers and body before sending' do
      conversation.contact.update!(name: 'Rae', email: 'rae@example.com')
      stub = stub_request(:post, 'http://93.184.216.34/u/Rae')
             .with(body: 'hello Rae', headers: { 'X-Email' => 'rae@example.com' }).to_return(status: 200, body: 'ok')
      run('method' => 'post', 'url' => 'http://93.184.216.34/u/{{contact.name}}',
          'headers' => [{ 'key' => 'X-Email', 'value' => '{{contact.email}}' }],
          'body' => 'hello {{contact.name}}')
      expect(stub).to have_been_requested
    end

    it 'stores into an additional attribute on the contact when configured' do
      stub_request(:get, 'http://93.184.216.34/c').to_return(status: 200, body: 'CVAL')
      run('method' => 'get', 'url' => 'http://93.184.216.34/c', 'target' => 'contact', 'store' => 'additional', 'key' => 'ext')
      expect(conversation.contact.reload.additional_attributes['ext']).to eq('CVAL')
    end

    it 'drops user-supplied hop-by-hop/sensitive headers (Host cannot be forged)' do
      stub = stub_request(:get, 'http://93.184.216.34/h').to_return(status: 200, body: 'ok')
      run('method' => 'get', 'url' => 'http://93.184.216.34/h',
          'headers' => [{ 'key' => 'Host', 'value' => 'evil.internal' }, { 'key' => 'X-Ok', 'value' => '1' }])
      expect(stub.with(headers: { 'X-Ok' => '1' })).to have_been_requested
      expect(a_request(:get, 'http://93.184.216.34/h').with(headers: { 'Host' => 'evil.internal' })).not_to have_been_made
    end
  end

  describe '#http_request — SSRF guard (internal targets blocked, no request made)' do
    %w[
      http://127.0.0.1/x
      http://169.254.169.254/latest/meta-data/
      http://10.0.0.5/internal
      http://192.168.1.10/router
      http://172.16.0.9/x
      http://[::1]/x
      http://100.64.0.1/cgnat
      http://0.0.0.0/x
    ].each do |internal_url|
      it "blocks #{internal_url} as a skipped step (ssrf_blocked)" do
        result = run('method' => 'get', 'url' => internal_url)
        expect(result.status).to eq(:skipped)
        expect(result.error).to be_a(Flows::StepSkip)
        expect(result.error.code).to eq('ssrf_blocked')
      end
    end

    it 'blocks a public hostname that RESOLVES to an internal IP (DNS-rebinding defense)' do
      allow(Resolv).to receive(:getaddresses).with('evil.example.com').and_return(['10.0.0.5'])
      result = run('method' => 'get', 'url' => 'http://evil.example.com/x')
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('ssrf_blocked')
    end

    it 'blocks a host resolving to a v4-mapped IPv6 metadata address' do
      allow(Resolv).to receive(:getaddresses).with('rebind.example.com').and_return(['::ffff:169.254.169.254'])
      expect(run('method' => 'get', 'url' => 'http://rebind.example.com/x').error.code).to eq('ssrf_blocked')
    end

    it 'blocks non-http(s) schemes as invalid_url' do
      %w[file:///etc/passwd gopher://127.0.0.1/ ftp://10.0.0.1/].each do |bad|
        result = run('method' => 'get', 'url' => bad)
        expect(result.status).to eq(:skipped)
        expect(result.error.code).to eq('invalid_url')
      end
    end
  end

  describe '#http_request — does not follow redirects (SSRF via 3xx)' do
    it 'returns the 3xx verbatim and never fetches the Location (even to an internal IP)' do
      redirect = stub_request(:get, 'http://93.184.216.34/r').to_return(status: 302, headers: { 'Location' => 'http://169.254.169.254/' })
      internal = stub_request(:get, 'http://169.254.169.254/')
      expect(run('method' => 'get', 'url' => 'http://93.184.216.34/r', 'key' => 'x').status).to eq(:success)
      expect(redirect).to have_been_requested
      expect(internal).not_to have_been_requested
    end
  end

  describe '#http_request — response cap (memory safety)' do
    # O cap é do CLIENTE (buffer ≤ 64KB), independente do limite do atributo. Uma resposta de
    # 80KB é cortada em exatamente 64KB no buffer — protege memória/DoS na leitura.
    it 'the safe client caps the fetched body at 64KB' do
      stub_request(:get, 'http://93.184.216.34/big').to_return(status: 200, body: 'a' * (80 * 1024))
      result = Flows::SafeHttpClient.new(method: 'get', url: 'http://93.184.216.34/big').perform
      expect(result.body.bytesize).to eq(64 * 1024)
    end

    # Gravar em custom_attributes respeita o limite do model (< 1500 chars): uma resposta grande
    # demais para o atributo vira passo `failed` observável, não uma gravação silenciosa.
    it 'stores a normal (small) response body into the attribute' do
      stub_request(:get, 'http://93.184.216.34/small').to_return(status: 200, body: 'tiny')
      run('method' => 'get', 'url' => 'http://93.184.216.34/small', 'key' => 'small')
      expect(conversation.reload.custom_attributes['small']).to eq('tiny')
    end
  end

  describe '#http_request — network errors are triable skips, not failures' do
    it 'maps a timeout to StepSkip http_error (no Sentry)' do
      stub_request(:get, 'http://93.184.216.34/slow').to_timeout
      result = run('method' => 'get', 'url' => 'http://93.184.216.34/slow')
      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('http_error')
    end
  end

  it 'is a no-op when the URL is blank' do
    expect(run('method' => 'get', 'url' => '').status).to eq(:success)
  end
end
