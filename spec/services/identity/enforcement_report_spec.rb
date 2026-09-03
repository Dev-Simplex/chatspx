require 'rails_helper'

# Bloco 4.15 — o numero que decide a virada para `obrigatorio`. Se ele inflar, alguem liga
# enforcement achando que vai derrubar 300 sessoes e derruba 40; se ele desinflar, alguem
# acha que vai derrubar 40 e derruba 300. Os exemplos abaixo travam as duas direcoes.
RSpec.describe Identity::EnforcementReport do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_widget, account: account) }
  let(:inbox) { channel.inbox }

  def session(identity: {}, verified: false)
    contact = create(:contact, { account: account }.merge(identity))
    create(:contact_inbox, contact: contact, inbox: inbox, hmac_verified: verified)
  end

  def report
    described_class.new(inbox: inbox).perform
  end

  describe 'quem entra na conta' do
    it 'conta a sessao identificada por e-mail sem assinatura verificada' do
      session(identity: { email: 'a@corp.com' })

      expect(report[:unverified][:total]).to eq(1)
    end

    it 'conta identificacao por telefone e por identifier tambem' do
      session(identity: { phone_number: '+5565999990001' })
      session(identity: { identifier: 'crm-77' })

      expect(report[:unverified][:total]).to eq(2)
    end

    # A regra que impede o numero de inflar: visitante anonimo nao tem identidade para
    # verificar, e `obrigatorio` nao recusaria a sessao dele.
    it 'NAO conta sessao anonima' do
      session
      session
      session(identity: { email: 'a@corp.com' })

      expect(report[:unverified][:total]).to eq(1)
    end

    it 'NAO conta sessao cuja assinatura foi verificada' do
      session(identity: { email: 'a@corp.com' }, verified: true)
      session(identity: { email: 'b@corp.com' }, verified: false)

      expect(report[:unverified][:total]).to eq(1)
    end

    it 'NAO conta sessao de outra inbox' do
      outra = create(:channel_widget, account: account).inbox
      create(:contact_inbox, contact: create(:contact, account: account, email: 'c@corp.com'), inbox: outra)
      session(identity: { email: 'a@corp.com' })

      expect(report[:unverified][:total]).to eq(1)
    end

    it 'devolve zero, e nao erro, na inbox sem trafego' do
      expect(report[:unverified][:total]).to eq(0)
      expect(report[:rows]).to eq([])
    end
  end

  describe 'o que o relatorio devolve' do
    it 'nomeia o estado em que a inbox opera' do
      inbox.update!(identity_enforcement: 'observado')

      expect(report[:state]).to eq('observado')
    end

    it 'descreve cada linha com o contato e quais campos de identidade ele tem' do
      contact_inbox = session(identity: { email: 'a@corp.com', phone_number: '+5565999990002' })

      linha = report[:rows].first
      expect(linha[:contact_inbox_id]).to eq(contact_inbox.id)
      expect(linha[:contact_id]).to eq(contact_inbox.contact_id)
      expect(linha[:identity_fields]).to eq(%i[email phone_number])
    end

    it 'corta a lista em MAX_ROWS sem mentir no total' do
      (described_class::MAX_ROWS + 3).times { |i| session(identity: { email: "a#{i}@corp.com" }) }

      expect(report[:rows].length).to eq(described_class::MAX_ROWS)
      expect(report[:unverified][:total]).to eq(described_class::MAX_ROWS + 3)
    end
  end

  # A mesma regra do Tracking::OriginReport: historico apresentado como medido e mentira, e
  # zero e pior — leria-se "nao houve nenhuma" onde houve, sem ninguem anotando.
  describe 'medido sob observacao vs historico' do
    it 'devolve nil, e nao zero, antes de a observacao comecar' do
      session(identity: { email: 'a@corp.com' })

      expect(report[:observed_since]).to be_nil
      expect(report[:unverified][:since_observation]).to be_nil
      expect(report[:unverified][:before_observation]).to be_nil
      expect(report[:unverified][:covers_whole_history]).to be(true)
    end

    it 'separa o que veio depois de a observacao comecar do que ja estava la' do
      antiga = session(identity: { email: 'antiga@corp.com' })
      antiga.update_columns(updated_at: 10.days.ago) # rubocop:disable Rails/SkipsModelValidations

      inbox.update!(identity_enforcement: 'observado')
      session(identity: { email: 'nova@corp.com' })

      medido = report
      expect(medido[:observed_since]).to be_present
      expect(medido[:unverified][:total]).to eq(2)
      expect(medido[:unverified][:since_observation]).to eq(1)
      expect(medido[:unverified][:before_observation]).to eq(1)
      expect(medido[:unverified][:covers_whole_history]).to be(false)
    end
  end
end
