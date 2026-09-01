require 'rails_helper'
require_relative 'fake_http_client'

# Bloco 5.12 — ACEITE: "Nenhum campo `em`/`ph`/`fn`/`ln` sai; verificado no log de auditoria, que
# registra NOMES de campos".
#
# O aceite e uma afirmacao NEGATIVA, e afirmacao negativa passa no vacuo: "nao ha `em` no payload" e
# verdade tambem quando o payload esta vazio, quando o contato nao tem e-mail e quando o job nunca
# rodou. Por isso todo exemplo aqui prova as tres coisas juntas:
#
#   (a) o contato TINHA e-mail, telefone, nome e sobrenome — a supressao teve o que suprimir;
#   (b) o payload SAIU, com identidade dentro (external_id, fbc, IP e UA do visitante);
#   (c) e mesmo assim `em`/`ph`/`fn`/`ln` nao estao la — nem como chave, nem como valor, nem como
#       digest do valor.
#
# E o ultimo bloco fecha a porta do vacuo pelo outro lado: com a politica destravada, os quatro
# campos APARECEM. Se o caminho com PII nao existisse, o teste negativo passaria por nao haver
# codigo nenhum — e nao por haver uma trava.
RSpec.describe Tracking::PiiPolicy do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  let(:contact) do
    create(:contact, account: account, name: 'Maria Aparecida',
                     email: 'Maria.Aparecida@Exemplo.COM', phone_number: '+5511987654321',
                     additional_attributes: {
                       'city' => 'São Paulo', 'country_code' => 'BR',
                       'created_at_ip' => '203.0.113.7'
                     })
  end

  let(:conversation) do
    conv = create(:conversation, account: account, inbox: inbox, contact: contact)
    conv.update!(
      additional_attributes: conv.additional_attributes.merge(
        'browser' => { 'user_agent' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5) Safari/605.1.15' },
        'referer' => 'https://cliente.com.br/planos'
      ),
      custom_attributes: conv.custom_attributes.merge('last_fbclid' => 'IwAR0abc', 'last_gclid' => 'Cj0KCQiA')
    )
    conv
  end

  let(:event) do
    Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                    conversation: conversation, contact: contact,
                                    properties: { 'value' => 350.0, 'currency' => 'BRL' },
                                    dedup_key: 'lead-sem-pii', deliver: false)
  end

  let(:settings) do
    Tracking::CredentialResolver::Settings.new(
      meta_pixel_id: '1234567890', meta_access_token: 'EAA-token-secreto',
      ga4_measurement_id: 'G-ABC123', ga4_api_secret: 'segredo-ga4',
      google_ads_customer_id: '111', google_ads_conversion_action_id: '222',
      google_ads_developer_token: 'dev', google_ads_access_token: 'ya29'
    )
  end

  let(:http_client) { FakeHttpClient.new }

  # O que a supressao PRECISA ter tido a mao para o teste nao ser vacuo.
  describe 'a premissa: a base tinha o que suprimir' do
    it 'o contato tem e-mail, telefone, nome e sobrenome' do
      person = Tracking::PersonData.new(contact)

      expect(person.available_names).to include('em', 'ph', 'fn', 'ln')
      expect(person['em']).to be_present
      expect(person['ph']).to be_present
    end

    it 'e a politica esta travada por construcao, nao por configuracao de conta' do
      expect(Tracking::PiiPolicy::DPA_SIGNED).to be(false)
      expect(described_class.person_fields_allowed?).to be(false)
      expect(described_class.mode).to eq(:without_pii)
    end
  end

  describe 'a entrega de verdade, pelo job, com o log de auditoria persistido' do
    let(:delivery) { event.claim_delivery(:meta_capi) }

    before do
      allow(Tracking::CredentialResolver).to receive(:call).and_return(settings)
      allow(Tracking::HttpClient).to receive(:new).and_return(http_client)
      delivery
      Tracking::MetaCapiDeliveryJob.perform_now(delivery.id)
    end

    it '(a) o payload SAIU, e saiu com identidade dentro' do
      expect(http_client.calls.size).to eq(1)

      user_data = http_client.last_body[:data].first[:user_data]
      expect(user_data).to include(:external_id, :fbc, :client_ip_address, :client_user_agent)
      # IP e UA do VISITANTE (T-C5.8 / RC10), nao da maquina que rodou o job.
      expect(user_data[:client_ip_address]).to eq('203.0.113.7')
      expect(user_data[:client_user_agent]).to start_with('Mozilla/5.0 (iPhone')
      expect(delivery.reload).to have_attributes(status: 'sent', http_status: 200)
    end

    it '(b) e mesmo assim nao ha `em`/`ph`/`fn`/`ln` — nem chave, nem valor, nem digest' do
      names = Tracking::FieldNames.from(http_client.last_body)
      expect(names).not_to include('em', 'ph', 'fn', 'ln')
      expect(names).not_to include('ct', 'st', 'zp', 'country')

      json = http_client.last_body_json
      # o valor cru
      expect(json).not_to include('Maria')
      expect(json).not_to include('5511987654321')
      expect(json.downcase).not_to include('exemplo.com')
      # e o digest do valor normalizado, que e a forma em que ele SAIRIA no modo com PII
      expect(json).not_to include(Digest::SHA256.hexdigest('maria.aparecida@exemplo.com'))
      expect(json).not_to include(Digest::SHA256.hexdigest('5511987654321'))
    end

    it '(c) o log de auditoria registra os NOMES dos campos suprimidos, nunca os valores' do
      expect(delivery.reload.suppressed_field_names).to include('em', 'ph', 'fn', 'ln')
      # a cidade e o pais tambem sao campos de pessoa no vocabulario de anuncio
      expect(delivery.suppressed_field_names).to include('ct', 'country')
      # NOMES: nenhum valor do contato aparece no log
      expect(delivery.suppressed_field_names.join(' ')).not_to include('Maria', 'exemplo', '5511')
      expect(delivery.field_names).to include('external_id', 'client_ip_address', 'client_user_agent')
      expect(delivery.field_names).not_to include('em', 'ph', 'fn', 'ln')
    end

    it 'e o segredo nunca entra no corpo nem no log — ele viaja na query e fica no backend' do
      expect(http_client.last_body_json).not_to include('EAA-token-secreto')
      expect(delivery.reload.field_names).not_to include('access_token')
      expect(http_client.calls.first[:query]).to eq(access_token: 'EAA-token-secreto')
    end
  end

  # A METADE DO ACEITE QUE FALTAVA: "verificado no LOG DE AUDITORIA". Ate aqui a supressao era
  # calculada pelo destino e chegava ao banco so na entrega BEM SUCEDIDA. A entrega que nao saiu
  # gravava status e motivo, e o que o destino tinha calculado morria no caminho — justamente na
  # classe onde a supressao pesa mais: o Google Ads sem `gclid`, que sob o modo sem PII fica sem
  # identificador nenhum e vira `skipped` inteiro, todas as vezes, para toda conta.
  describe 'a entrega que NAO saiu — o `skipped` tambem grava os nomes retidos' do
    let(:conversa_sem_clique) do
      conv = create(:conversation, account: account, inbox: inbox, contact: contact)
      conv.update!(
        additional_attributes: conv.additional_attributes.merge(
          'browser' => { 'user_agent' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5) Safari/605.1.15' }
        )
      )
      conv
    end

    let(:evento_sem_clique) do
      Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                      conversation: conversa_sem_clique, contact: contact,
                                      properties: { 'value' => 350.0, 'currency' => 'BRL' },
                                      dedup_key: 'lead-sem-gclid', deliver: false)
    end

    before do
      allow(Tracking::CredentialResolver).to receive(:call).and_return(settings)
      allow(Tracking::HttpClient).to receive(:new).and_return(http_client)
    end

    # O CONTROLE, e ele e duplo: a entrega nao saiu (nao houve chamada) E a base tinha o que
    # suprimir. Sem os dois, "gravou a lista de retidos" seria verdade tambem para uma lista vazia.
    it 'o CONTROLE: sem gclid o Google Ads nao tem o que mandar, e o destino CALCULA a supressao' do
      resultado = Tracking::Destinations::GoogleAds
                  .new(event: evento_sem_clique, settings: settings, http_client: http_client).deliver!

      expect(http_client.calls).to be_empty
      expect(resultado.status).to eq(:skipped)
      expect(resultado.reason).to eq('no_identifier')
      expect(resultado.suppressed_field_names).to include('em', 'ph', 'fn', 'ln')
    end

    it 'e o que o destino calculou CHEGA ao banco, nao so o status' do
      entrega = evento_sem_clique.claim_delivery(:google_ads)

      Tracking::GoogleAdsDeliveryJob.perform_now(entrega.id)

      expect(entrega.reload).to have_attributes(status: 'skipped', error_code: 'no_identifier')
      expect(entrega.suppressed_field_names).to include('em', 'ph', 'fn', 'ln')
      # NOMES, nunca valores — a mesma regra da entrega que sai.
      expect(entrega.suppressed_field_names.join(' ')).not_to include('Maria', 'exemplo', '5511')
      expect(entrega.field_names).to eq([])
    end

    # A PORTA LATERAL, fechada de proposito: `skipped` por credencial ausente nao chega a montar
    # payload nenhum, entao nao houve supressao. Preencher a lista ali seria log que PROMETE — e o
    # painel diria "retivemos `em`" para uma entrega que nunca existiu.
    it 'mas o `skipped` sem destino configurado nao inventa lista' do
      sem_google = Tracking::CredentialResolver::Settings.new(meta_pixel_id: '1234567890',
                                                              meta_access_token: 'EAA-token-secreto')
      allow(Tracking::CredentialResolver).to receive(:call).and_return(sem_google)
      entrega = evento_sem_clique.claim_delivery(:google_ads)

      Tracking::GoogleAdsDeliveryJob.perform_now(entrega.id)

      expect(entrega.reload).to have_attributes(status: 'skipped', error_code: 'not_configured')
      expect(entrega.suppressed_field_names).to eq([])
    end
  end

  describe 'os tres destinos, nao so a Meta' do
    before { allow(Tracking::CredentialResolver).to receive(:call).and_return(settings) }

    {
      'Tracking::Destinations::MetaCapi' => 'meta_capi',
      'Tracking::Destinations::Ga4Mp' => 'ga4_mp',
      'Tracking::Destinations::GoogleAds' => 'google_ads'
    }.each do |klass_name, label|
      it "#{label} entrega e nao leva campo de pessoa" do
        client = FakeHttpClient.new
        result = klass_name.constantize.new(event: event, settings: settings, http_client: client).deliver!

        expect(client.calls.size).to eq(1)
        expect(result.status).to eq(:sent)
        expect(result.field_names).not_to include('em', 'ph', 'fn', 'ln')
        expect(result.suppressed_field_names).to include('em', 'ph', 'fn', 'ln')
        expect(client.last_body_json.downcase).not_to include('exemplo.com')
      end
    end
  end

  # A prova de que o exemplo (b) NAO passa no vacuo: destravada a politica, os quatro campos saem.
  # Se este bloco ficar verde com um payload sem `em`, o teste negativo la de cima nao estava medindo
  # nada — estaria medindo a ausencia do codigo, e nao a presenca da trava.
  describe 'a mesma entrega com a politica destravada — o vermelho que da sentido ao verde' do
    before do
      allow(described_class).to receive(:person_fields_allowed?).and_return(true)
      allow(described_class).to receive(:suppressed_from).and_return([])
    end

    it 'a Meta passaria a receber em/ph/fn/ln hasheados no servidor' do
      Tracking::Destinations::MetaCapi.new(event: event, settings: settings, http_client: http_client).deliver!

      user_data = http_client.last_body[:data].first[:user_data]
      expect(user_data).to include(:em, :ph, :fn, :ln)
      expect(user_data[:em]).to eq(Digest::SHA256.hexdigest('maria.aparecida@exemplo.com'))
      expect(user_data[:ph]).to eq(Digest::SHA256.hexdigest('5511987654321'))
    end

    it 'e o Google Ads passaria a receber os user_identifiers com telefone em E.164' do
      client = FakeHttpClient.new
      Tracking::Destinations::GoogleAds.new(event: event, settings: settings, http_client: client).deliver!

      identifiers = client.last_body[:conversions].first[:userIdentifiers]
      expect(identifiers).to include(hashedEmail: Digest::SHA256.hexdigest('maria.aparecida@exemplo.com'))
      expect(identifiers).to include(hashedPhoneNumber: Digest::SHA256.hexdigest('+5511987654321'))
    end
  end
end
