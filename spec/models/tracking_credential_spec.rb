require 'rails_helper'

RSpec.describe TrackingCredential do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:secret) { 'EAAmeta-access-token-que-nao-pode-vazar-9876' }

  describe 'criptografia em repouso' do
    # O contra-teste de todos os outros: se o segredo NAO estivesse gravado e legivel, cada
    # "nao contem o segredo" deste arquivo passaria por vacuidade, medindo nada.
    it 'grava e le o segredo pelo modelo' do
      credential = create(:tracking_credential, account: account, inbox: inbox, meta_access_token: secret)

      expect(credential.reload.meta_access_token).to eq(secret)
    end

    it 'nao guarda o valor em claro na coluna' do
      credential = create(:tracking_credential, account: account, inbox: inbox, meta_access_token: secret)
      raw = described_class.connection.select_value(
        described_class.sanitize_sql_array(['SELECT meta_access_token FROM tracking_credentials WHERE id = ?', credential.id])
      )

      expect(raw).to be_present
      expect(raw).not_to include(secret)
    end

    # A armadilha registrada em onda-0-infra-0.4-0.10-EXECUTADO.md: duas declaracoes `encrypts` no
    # mesmo atributo se misturam e a opcao de cifra se perde EM SILENCIO — foi o que aconteceu com
    # `User#otp_secret`, que se le como deterministico e nao e. Aqui a escolha e o contrario
    # (nao deterministico, para o IV ser aleatorio), e este teste trava a escolha: se alguem
    # acrescentar um segundo `encrypts` deterministico, o esquema muda e isto acusa.
    it 'usa cifra nao deterministica em todos os segredos' do
      described_class::SECRET_ATTRIBUTES.each do |attribute|
        expect(described_class.type_for_attribute(attribute).scheme.deterministic?).to be(false), "#{attribute} deveria ser não determinístico"
      end
    end

    # A consequencia observavel do IV aleatorio: duas inboxes com o MESMO token nao produzem o
    # mesmo ciphertext, entao ninguem descobre que compartilham credencial olhando o banco.
    it 'produz ciphertext diferente para o mesmo valor em linhas diferentes' do
      first = create(:tracking_credential, account: account, inbox: inbox, meta_access_token: secret)
      second = create(:tracking_credential, account: account, inbox: create(:inbox, account: account), meta_access_token: secret)

      raws = [first, second].map do |credential|
        described_class.connection.select_value(
          described_class.sanitize_sql_array(['SELECT meta_access_token FROM tracking_credentials WHERE id = ?', credential.id])
        )
      end

      expect(raws.first).not_to eq(raws.last)
    end
  end

  describe '#secret_summary' do
    it 'devolve so `configured` e os 4 ultimos caracteres' do
      credential = create(:tracking_credential, account: account, inbox: inbox, meta_access_token: secret)

      expect(credential.secret_summary(:meta_access_token)).to eq(configured: true, last_four: '9876')
    end

    it 'devolve nao configurado quando o campo esta vazio' do
      credential = create(:tracking_credential, account: account, inbox: inbox, google_ads_refresh_token: nil)

      expect(credential.secret_summary(:google_ads_refresh_token)).to eq(configured: false, last_four: nil)
    end

    # Sem o piso de tamanho, um segredo de 5 caracteres voltaria quase inteiro nos "4 ultimos".
    it 'nao devolve pedaco de segredo curto demais' do
      credential = build(:tracking_credential, account: account, inbox: inbox, meta_access_token: 'abc')

      expect(credential.last_four(:meta_access_token)).to be_nil
      expect(credential).not_to be_valid
      expect(credential.errors[:meta_access_token]).to be_present
    end
  end

  describe 'validacoes' do
    it 'recusa inbox de outra conta' do
      credential = build(:tracking_credential, account: account, inbox: create(:inbox, account: create(:account)))

      expect(credential).not_to be_valid
      expect(credential.errors[:inbox]).to be_present
    end

    it 'recusa uma segunda credencial para a mesma inbox' do
      create(:tracking_credential, account: account, inbox: inbox)

      expect(build(:tracking_credential, account: account, inbox: inbox)).not_to be_valid
    end

    # Sem esta trava, um ambiente sem chaves gravaria o access token EM CLARO e ninguem saberia.
    it 'recusa gravar segredo quando a criptografia nao esta configurada' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
      credential = build(:tracking_credential, account: account, inbox: inbox, meta_access_token: secret)

      expect(credential).not_to be_valid
      expect(credential.errors[:base].join).to include('ACTIVE_RECORD_ENCRYPTION')
    end

    it 'aceita credencial sem nenhum segredo quando a criptografia nao esta configurada' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
      credential = build(:tracking_credential, account: account, inbox: inbox,
                                               meta_access_token: nil, ga4_api_secret: nil, meta_test_event_code: 'TEST123')

      expect(credential).to be_valid
    end
  end

  describe 'auditoria' do
    it 'registra a mudanca sem guardar o segredo' do
      credential = create(:tracking_credential, account: account, inbox: inbox, meta_access_token: secret)
      credential.update!(meta_test_event_code: 'TEST42', meta_access_token: "#{secret}-novo")

      changes = credential.audits.last.audited_changes

      # Controle: a auditoria REGISTROU esta atualizacao. Sem esta linha, o `not_to include` abaixo
      # passaria tambem num mundo em que `audited` nunca rodou.
      expect(changes).to have_key('meta_test_event_code')
      expect(changes.keys).not_to include(*described_class::SECRET_ATTRIBUTES.map(&:to_s))
      expect(changes.to_s).not_to include(secret)
    end
  end
end
