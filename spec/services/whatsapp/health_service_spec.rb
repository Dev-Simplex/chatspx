require 'rails_helper'

describe Whatsapp::HealthService do
  let(:account) { create(:account) }
  let(:frontend_url) { 'https://app.example.com' }
  let(:waba_id) { '905788818829319' }
  let(:api_response) do
    {
      'id' => '123456789',
      'display_phone_number' => '556635317222',
      'verified_name' => 'Test Business',
      'quality_rating' => 'GREEN',
      'webhook_configuration' => { 'whatsapp_business_account' => "#{frontend_url}/webhooks/whatsapp/+556635317222" }
    }
  end

  # A factory sobrescreve business_account_id/phone_number_id no before(:create), entao os
  # valores usados pelo teste sao aplicados logo apos a criacao do canal.
  def create_cloud_channel(phone_number:, business_account_id:, channel_account: account, provider: 'whatsapp_cloud')
    channel = create(:channel_whatsapp,
                     account: channel_account,
                     phone_number: phone_number,
                     provider: provider,
                     sync_templates: false,
                     validate_provider_config: false)
    channel.update!(provider_config: channel.provider_config.merge('business_account_id' => business_account_id))
    channel
  end

  before do
    stub_request(:get, /graph\.facebook\.com/).to_return(
      status: 200, body: api_response.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  describe '#fetch_health_status' do
    context 'when the channel is the only one on the WABA' do
      let(:channel) { create_cloud_channel(phone_number: '+556635317222', business_account_id: waba_id) }

      it 'keeps expected_webhook_url pointing at its own number' do
        with_modified_env FRONTEND_URL: frontend_url do
          expect(described_class.new(channel).fetch_health_status[:expected_webhook_url])
            .to eq("#{frontend_url}/webhooks/whatsapp/+556635317222")
        end
      end

      it 'returns a single acceptable url, identical to the expected one' do
        with_modified_env FRONTEND_URL: frontend_url do
          health_data = described_class.new(channel).fetch_health_status

          expect(health_data[:acceptable_webhook_urls]).to eq([health_data[:expected_webhook_url]])
        end
      end
    end

    context 'when two channels share the same WABA' do
      let!(:channel_one) { create_cloud_channel(phone_number: '+556635317222', business_account_id: waba_id) }
      let!(:channel_two) { create_cloud_channel(phone_number: '+556632114876', business_account_id: waba_id) }

      it 'accepts both sibling urls regardless of which channel is being checked' do
        with_modified_env FRONTEND_URL: frontend_url do
          both_urls = [
            "#{frontend_url}/webhooks/whatsapp/+556635317222",
            "#{frontend_url}/webhooks/whatsapp/+556632114876"
          ]

          expect(described_class.new(channel_one).fetch_health_status[:acceptable_webhook_urls]).to match_array(both_urls)
          expect(described_class.new(channel_two).fetch_health_status[:acceptable_webhook_urls]).to match_array(both_urls)
        end
      end

      it 'lists its own url first' do
        with_modified_env FRONTEND_URL: frontend_url do
          health_data = described_class.new(channel_two).fetch_health_status

          expect(health_data[:acceptable_webhook_urls].first).to eq("#{frontend_url}/webhooks/whatsapp/+556632114876")
        end
      end

      it 'does not duplicate its own url' do
        with_modified_env FRONTEND_URL: frontend_url do
          urls = described_class.new(channel_one).fetch_health_status[:acceptable_webhook_urls]

          expect(urls).to eq(urls.uniq)
        end
      end
    end

    context 'when another channel belongs to a different WABA' do
      let(:channel) { create_cloud_channel(phone_number: '+556635317222', business_account_id: waba_id) }

      before { create_cloud_channel(phone_number: '+556632114876', business_account_id: 'other_waba_id') }

      it 'does not accept the unrelated url' do
        with_modified_env FRONTEND_URL: frontend_url do
          expect(described_class.new(channel).fetch_health_status[:acceptable_webhook_urls])
            .to eq(["#{frontend_url}/webhooks/whatsapp/+556635317222"])
        end
      end
    end

    context 'when a channel on the same WABA belongs to another account' do
      let(:channel) { create_cloud_channel(phone_number: '+556635317222', business_account_id: waba_id) }

      before do
        create_cloud_channel(phone_number: '+556632114876', business_account_id: waba_id, channel_account: create(:account))
      end

      it 'does not accept the url of the other account (search is account scoped)' do
        with_modified_env FRONTEND_URL: frontend_url do
          expect(described_class.new(channel).fetch_health_status[:acceptable_webhook_urls])
            .to eq(["#{frontend_url}/webhooks/whatsapp/+556635317222"])
        end
      end
    end

    context 'when a sibling on the same WABA is not a whatsapp_cloud channel' do
      let(:channel) { create_cloud_channel(phone_number: '+556635317222', business_account_id: waba_id) }

      before do
        create_cloud_channel(phone_number: '+556632114876', business_account_id: waba_id, provider: 'default')
      end

      it 'does not accept the url of the non cloud channel' do
        with_modified_env FRONTEND_URL: frontend_url do
          expect(described_class.new(channel).fetch_health_status[:acceptable_webhook_urls])
            .to eq(["#{frontend_url}/webhooks/whatsapp/+556635317222"])
        end
      end
    end

    context 'when business_account_id is blank' do
      let(:channel) { create_cloud_channel(phone_number: '+556635317222', business_account_id: '') }

      before { create_cloud_channel(phone_number: '+556632114876', business_account_id: '') }

      it 'falls back to its own url only, instead of grouping every channel without a WABA' do
        with_modified_env FRONTEND_URL: frontend_url do
          expect(described_class.new(channel).fetch_health_status[:acceptable_webhook_urls])
            .to eq(["#{frontend_url}/webhooks/whatsapp/+556635317222"])
        end
      end
    end

    context 'when FRONTEND_URL is blank' do
      let!(:channel) { create_cloud_channel(phone_number: '+556635317222', business_account_id: waba_id) }

      before { create_cloud_channel(phone_number: '+556632114876', business_account_id: waba_id) }

      it 'returns nil for expected_webhook_url, as before' do
        with_modified_env FRONTEND_URL: '' do
          expect(described_class.new(channel).fetch_health_status[:expected_webhook_url]).to be_nil
        end
      end

      it 'returns an empty list so the consumer falls back to the old comparison' do
        with_modified_env FRONTEND_URL: '' do
          expect(described_class.new(channel).fetch_health_status[:acceptable_webhook_urls]).to eq([])
        end
      end
    end
  end
end
