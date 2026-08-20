require 'rails_helper'

describe Whatsapp::HealthService do
  let(:account) { create(:account) }
  let(:waba_id) { '905788818829319' }
  let(:frontend_url) { 'https://tozi.chatspx.app' }
  let(:own_url) { "#{frontend_url}/webhooks/whatsapp/+556635317222" }

  let!(:channel) do
    create_wa_channel(phone_number: '+556635317222', waba: waba_id, phone_number_id: '915207101681633')
  end

  # A factory de channel_whatsapp sobrescreve provider_config com defaults proprios
  # (business_account_id => '123456789'), entao o config real e gravado depois da criacao,
  # via update_column, que tambem evita disparar o after_commit :setup_webhooks.
  def create_wa_channel(phone_number:, waba:, phone_number_id:, owner: account)
    channel = create(:channel_whatsapp, account: owner, phone_number: phone_number,
                                        provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    channel.update_column( # rubocop:disable Rails/SkipsModelValidations
      :provider_config,
      { 'api_key' => 'test_key', 'phone_number_id' => phone_number_id,
        'business_account_id' => waba, 'source' => 'embedded_signup' }
    )
    channel.reload
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('FRONTEND_URL', nil).and_return(frontend_url)
    stub_request(:get, /graph\.facebook\.com/)
      .to_return(
        status: 200,
        body: { 'id' => '915207101681633', 'display_phone_number' => '+55 66 3531-7222',
                'webhook_configuration' => { 'whatsapp_business_account' => own_url } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def health
    described_class.new(channel).fetch_health_status
  end

  context 'when the WABA has a single phone number' do
    it 'accepts only its own webhook url' do
      expect(health[:acceptable_webhook_urls]).to contain_exactly(own_url)
    end

    it 'reports its own url as the expected one' do
      expect(health[:expected_webhook_url]).to eq(own_url)
    end
  end

  context 'when a sibling channel shares the same WABA' do
    before do
      create_wa_channel(phone_number: '+556632114876', waba: waba_id, phone_number_id: '1198595696676446')
    end

    it 'accepts the webhook url of either number' do
      expect(health[:acceptable_webhook_urls]).to contain_exactly(
        own_url, "#{frontend_url}/webhooks/whatsapp/+556632114876"
      )
    end

    it 'still reports its own url as the expected one' do
      expect(health[:expected_webhook_url]).to eq(own_url)
    end
  end

  context 'when another channel belongs to a different WABA' do
    before do
      create_wa_channel(phone_number: '+556699999999', waba: 'outro-waba', phone_number_id: '999')
    end

    it 'does not accept the unrelated url' do
      expect(health[:acceptable_webhook_urls]).to contain_exactly(own_url)
    end
  end

  context 'when a channel of another account shares the same WABA' do
    before do
      create_wa_channel(phone_number: '+556688888888', waba: waba_id, phone_number_id: '888', owner: create(:account))
    end

    it 'does not leak the url of the other account' do
      expect(health[:acceptable_webhook_urls]).to contain_exactly(own_url)
    end
  end

  context 'when FRONTEND_URL is blank' do
    before { allow(ENV).to receive(:fetch).with('FRONTEND_URL', nil).and_return(nil) }

    it 'returns no expected url' do
      expect(health[:expected_webhook_url]).to be_nil
    end

    it 'returns an empty acceptable list' do
      expect(health[:acceptable_webhook_urls]).to eq([])
    end
  end

  context 'when business_account_id is missing' do
    before do
      channel.update_column(:provider_config, channel.provider_config.except('business_account_id')) # rubocop:disable Rails/SkipsModelValidations
      channel.reload
    end

    it 'falls back to its own url only' do
      expect(health[:acceptable_webhook_urls]).to contain_exactly(own_url)
    end
  end
end
