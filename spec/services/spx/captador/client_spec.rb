require 'rails_helper'

# Destino das chamadas ao Captador (SSRF, A-2 da revisão de segurança): só https, na 443, para os hosts
# de CAPTADOR_HOSTS_PERMITIDOS, pelo Flows::SafeHttpClient. Nos casos recusados nada pode abrir
# conexão: o WebMock levantaria NetConnectNotAllowedError, que não é StandardError e derruba o exemplo.
RSpec.describe Spx::Captador::Client do
  include CaptadorSigningHelpers

  let(:account) { create(:account) }
  let(:hook) { captador_hook_for(account) }

  # Troca o captador_url só em memória: testa o Client também com o que o schema do hook já recusa.
  def lead_from(url)
    hook.settings['captador_url'] = url
    described_class.new(hook, instance_double(User, id: 42)).lead(conversation_id: 1, contact_id: 2)
  end

  %w[https://127.0.0.1 https://169.254.169.254 https://10.0.0.5 https://192.168.8.229 http://captador.spx.ia.br
     https://captador.spx.ia.br:8443 https://evil.example.com https://captador.spx.ia.br@10.0.0.5].each do |url|
    it "recusa #{url} sem abrir conexão" do
      expect { lead_from(url) }.to raise_error(described_class::Unavailable)
      expect(a_request(:any, /./)).not_to have_been_made
    end
  end

  it 'recusa IP interno mesmo com o host na lista (DNS apontando para dentro ou lista mal configurada)' do
    with_modified_env(CAPTADOR_HOSTS_PERMITIDOS: 'captador.spx.ia.br,127.0.0.1,169.254.169.254,10.0.0.5,192.168.8.229') do
      stub_captador_dns('10.0.0.5')
      %w[https://captador.spx.ia.br https://127.0.0.1 https://169.254.169.254 https://10.0.0.5 https://192.168.8.229].each do |url|
        expect { lead_from(url) }.to raise_error(described_class::Unavailable, /blocked address/)
      end
    end
    expect(a_request(:any, /./)).not_to have_been_made
  end

  it 'não segue redirecionamento' do
    stub_captador_dns
    stub_request(:get, %r{\Ahttps://captador\.spx\.ia\.br/}).to_return(status: 302, headers: { 'Location' => 'http://169.254.169.254/' })
    internal = stub_request(:get, 'http://169.254.169.254/')

    expect(lead_from('https://captador.spx.ia.br').status).to eq(302)
    expect(internal).not_to have_been_requested
  end

  it 'chama https://captador.spx.ia.br' do
    stub_captador_dns
    stub = stub_request(:get, 'https://captador.spx.ia.br/integracao/chatspx/v1/leads?contact_id=2&conversation_id=1')
           .to_return(status: 200, body: '{"lead":null}')

    expect(lead_from('https://captador.spx.ia.br/').body).to eq('lead' => nil)
    expect(stub).to have_been_requested
  end

  it 'o hook só aceita captador_url https e instance_key sem caracteres de caminho' do
    expect(hook.update(settings: hook.settings.merge('captador_url' => 'http://captador.spx.ia.br'))).to be(false)
    expect(hook.reload.update(settings: hook.settings.merge('instance_key' => '../x?y'))).to be(false)
  end
end
