require 'rails_helper'

# A JUNTA (5.02 x 5.11): o resolver le o cofre de verdade.
#
# O risco que este arquivo existe para cobrir e o de um teste que passa no VACUO. Enquanto o resolver
# devolvia `nil` fixo, "sem credencial nao entrega" era verdade porque nao havia credencial nenhuma —
# a afirmacao passava com o resolver quebrado. Por isso cada exemplo negativo aqui vem com o exemplo
# POSITIVO equivalente ao lado: o par so tem valor junto.
RSpec.describe Tracking::CredentialResolver do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  let(:meta_token) { 'EAAtoken-da-junta-que-nao-pode-vazar-4321' }
  let(:ga4_secret) { 'ga4-secret-da-junta-8765' }

  # A config PUBLICA (bloco 5.01) mora no jsonb da inbox; o segredo (5.02), na tabela cifrada.
  # As duas metades so se encontram aqui, no servidor.
  def configure_public!(**tracking)
    inbox.update!(additional_attributes: inbox.additional_attributes.to_h.merge('widget_tracking' => tracking.stringify_keys))
  end

  def configure_secrets!(target_inbox: inbox, **attributes)
    create(:tracking_credential, { account: account, inbox: target_inbox,
                                   meta_access_token: meta_token, ga4_api_secret: ga4_secret }.merge(attributes))
  end

  describe 'as duas metades juntas' do
    before do
      configure_public!(meta_pixel_id: '99887766', ga4_measurement_id: 'G-JUNTA123')
      configure_secrets!(meta_test_event_code: 'TEST12345')
    end

    it 'monta o Settings com o id publico da inbox e o segredo do cofre' do
      settings = described_class.call(account: account, inbox: inbox)

      expect(settings).to have_attributes(
        meta_pixel_id: '99887766', meta_access_token: meta_token, meta_test_event_code: 'TEST12345',
        ga4_measurement_id: 'G-JUNTA123', ga4_api_secret: ga4_secret
      )
    end

    it 'declara Meta e GA4 prontos — e e isto que faz a fila deixar de ser inerte' do
      settings = described_class.call(account: account, inbox: inbox)

      expect(settings.meta_capi_ready?).to be(true)
      expect(settings.ga4_mp_ready?).to be(true)
    end
  end

  describe 'a metade que falta derruba SO o destino dela' do
    it 'sem o id publico, o segredo sozinho nao configura a Meta' do
      configure_secrets!

      settings = described_class.call(account: account, inbox: inbox)

      # O CONTROLE: o segredo esta la. Sem esta linha, o `be(false)` abaixo passaria tambem se o
      # resolver nao tivesse lido o cofre coisa nenhuma.
      expect(settings.meta_access_token).to eq(meta_token)
      expect(settings.meta_pixel_id).to be_nil
      expect(settings.meta_capi_ready?).to be(false)
    end

    it 'sem o segredo, o id publico sozinho tambem nao' do
      configure_public!(meta_pixel_id: '99887766', ga4_measurement_id: 'G-JUNTA123')
      configure_secrets!(meta_access_token: nil)

      settings = described_class.call(account: account, inbox: inbox)

      expect(settings.meta_pixel_id).to eq('99887766')
      expect(settings.meta_capi_ready?).to be(false)
      # e o outro destino, cujo segredo veio, continua pronto — a falta e por destino, nao geral
      expect(settings.ga4_mp_ready?).to be(true)
    end
  end

  describe 'a ancora e a credencial' do
    before { configure_public!(meta_pixel_id: '99887766', ga4_measurement_id: 'G-JUNTA123') }

    it 'sem linha no cofre devolve nil, mesmo com a inbox toda configurada' do
      expect(described_class.call(account: account, inbox: inbox)).to be_nil
    end

    # O PAR do exemplo acima: mesma conta, mesma inbox, mesma config publica. A UNICA diferenca e a
    # linha no cofre. Sem este exemplo, o `be_nil` acima passaria com o resolver devolvendo nil fixo.
    it 'com a linha no cofre devolve o Settings — mesmo cenario, so muda o cofre' do
      configure_secrets!

      expect(described_class.call(account: account, inbox: inbox)).to be_a(described_class::Settings)
    end
  end

  describe 'a resolucao e estritamente por inbox' do
    before { configure_public!(meta_pixel_id: '99887766') }

    it 'evento sem inbox nao herda credencial da conta — a tabela nao tem linha de conta' do
      configure_secrets!

      expect(described_class.call(account: account, inbox: nil)).to be_nil
    end

    it 'a credencial de uma inbox nao vale para outra da mesma conta' do
      outra = create(:inbox, account: account)
      configure_secrets!(target_inbox: outra)

      expect(described_class.call(account: account, inbox: inbox)).to be_nil
      # o CONTROLE: a linha existe, e resolve para a inbox dela
      expect(described_class.call(account: account, inbox: outra)).to be_a(described_class::Settings)
    end

    it 'nao resolve credencial de outra conta' do
      configure_secrets!

      expect(described_class.call(account: create(:account), inbox: inbox)).to be_nil
    end
  end

  describe 'a fronteira do Google Ads, que depende do OAuth que nao existe' do
    before do
      configure_public!(meta_pixel_id: '99887766', google_ads_send_to: 'AW-123456789/AbC-D_efGh12')
      configure_secrets!(google_ads_developer_token: 'developer-token-do-google-1234')
    end

    it 'traz o developer token do cofre, mas os quatro campos sem fonte ficam nil' do
      settings = described_class.call(account: account, inbox: inbox)

      # O CONTROLE: o unico campo do Google que TEM fonte hoje chegou.
      expect(settings.google_ads_developer_token).to eq('developer-token-do-google-1234')
      expect(described_class::UNSOURCED_FIELDS.map { |field| settings[field] }).to all(be_nil)
    end

    # A trava da fronteira: o dia em que alguem ligar o Google Ads pela metade — derivando o
    # `customer_id` do `google_ads_send_to`, por exemplo — este exemplo fica vermelho antes de a
    # frota descobrir por uma entrega morta na DLQ.
    it 'e por isso o destino NAO se declara pronto' do
      expect(described_class.call(account: account, inbox: inbox).google_ads_ready?).to be(false)
    end
  end

  describe 'a ausencia do bloco 5.01 nao derruba nada' do
    it 'inbox sem widget_tracking resolve com os ids publicos nulos, sem NoMethodError' do
      configure_secrets!

      expect { described_class.call(account: account, inbox: inbox) }.not_to raise_error
      expect(described_class.call(account: account, inbox: inbox).meta_pixel_id).to be_nil
    end
  end

  # Divergir aqui e falha SILENCIOSA: o cliente salva o Pixel ID, a tela confirma, e a fila nunca
  # entrega porque leu uma chave que ninguem grava.
  it 'le as chaves publicas pelo mesmo nome que o widget publica' do
    expect(described_class::PUBLIC_SOURCE.values).to all(be_in(WidgetTrackingProjection::PUBLIC_KEYS))
  end
end
