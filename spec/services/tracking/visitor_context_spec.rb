require 'rails_helper'

# Bloco 5.11 — T-C5.8 / RC10: IP e user-agent DO VISITANTE, nunca do servidor.
#
# O exemplo que carrega este arquivo e o da AUSENCIA. Quando a base nao tem o IP do visitante, a
# saida tentadora — e silenciosa — e mandar o IP da maquina que rodou o job: a Meta responde 200 e
# o EMQ da conta inteira desaba, porque todo evento passa a vir do mesmo endereco. Aqui, ausente e
# ausente.
RSpec.describe Tracking::VisitorContext do
  subject(:visitor) { described_class.for(event) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) do
    create(:contact, account: account,
                     additional_attributes: { 'created_at_ip' => '198.51.100.9' })
  end
  let(:conversation) do
    conv = create(:conversation, account: account, inbox: inbox, contact: contact)
    conv.update!(additional_attributes: conv.additional_attributes.merge(
      'browser' => { 'user_agent' => 'Mozilla/5.0 (Macintosh) Chrome/126' },
      'referer' => 'https://cliente.com.br/planos?utm_source=google'
    ))
    conv
  end
  let(:event) do
    Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                    conversation: conversation, contact: contact,
                                    dedup_key: 'v1', deliver: false)
  end

  describe 'IP e user-agent' do
    it 'le o IP que o widget gravou no contato' do
      expect(visitor.ip).to eq('198.51.100.9')
    end

    it 'prefere o IP mais recente quando existe' do
      contact.update!(additional_attributes: contact.additional_attributes.merge('updated_at_ip' => '203.0.113.5'))

      expect(described_class.for(event.reload).ip).to eq('203.0.113.5')
    end

    it 'le o user-agent do navegador do visitante' do
      expect(visitor.user_agent).to eq('Mozilla/5.0 (Macintosh) Chrome/126')
    end
  end

  describe 'quando a base NAO tem o dado — o exemplo que importa' do
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'devolve nil, e nao o IP do servidor' do
      expect(visitor.ip).to be_nil
      expect(visitor.user_agent).to be_nil
    end

    it 'e o payload sai SEM os campos, em vez de sair com o endereco errado' do
      settings = Tracking::CredentialResolver::Settings.new(meta_pixel_id: '1', meta_access_token: 't')
      client = Class.new do
        attr_reader :body

        def post_json(_url, body:, query: {}, headers: {}) # rubocop:disable Lint/UnusedMethodArgument
          @body = body
          Tracking::HttpClient::Response.new(status: 200, body: {})
        end
      end.new

      Tracking::Destinations::MetaCapi.new(event: event, settings: settings, http_client: client).deliver!

      user_data = client.body[:data].first[:user_data]
      expect(user_data).not_to have_key(:client_ip_address)
      expect(user_data).not_to have_key(:client_user_agent)
      # e ainda assim ha identidade: o teste nao passa por o payload estar vazio
      expect(user_data).to have_key(:external_id)
    end
  end

  describe 'click ids' do
    before do
      conversation.update!(custom_attributes: conversation.custom_attributes.merge(
        'last_fbclid' => 'IwAR0abc', 'last_gclid' => 'Cj0KCQiA'
      ))
    end

    it 'monta o fbc no formato da Meta a partir do fbclid — o fbclid cru nao e aceito' do
      expect(described_class.for(event.reload).fbc).to match(/\Afb\.1\.\d+\.IwAR0abc\z/)
    end

    it 'devolve o gclid como esta, porque o Google o quer cru' do
      expect(described_class.for(event.reload).gclid).to eq('Cj0KCQiA')
    end
  end

  describe 'client_id do GA4' do
    it 'e DETERMINISTICO quando o cookie _ga nao chegou: o mesmo visitante nao vira dois usuarios' do
      primeiro = described_class.for(event).ga_client_id
      segundo = described_class.for(event.reload).ga_client_id

      expect(primeiro).to be_present
      expect(primeiro).to eq(segundo)
    end

    it 'prefere o cookie real quando ele existe' do
      conversation.update!(additional_attributes: conversation.additional_attributes.merge('ga_client_id' => '111.222'))

      expect(described_class.for(event.reload).ga_client_id).to eq('111.222')
    end
  end

  describe 'external_id' do
    it 'e o id opaco do contato — dele nao se volta a nome, e-mail nem telefone' do
      expect(visitor.external_id).to eq(contact.id.to_s)
    end
  end
end
