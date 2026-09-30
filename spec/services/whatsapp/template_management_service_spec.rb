require 'rails_helper'

RSpec.describe Whatsapp::TemplateManagementService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:service) { described_class.new(whatsapp_channel) }
  let(:waba_id) { whatsapp_channel.provider_config['business_account_id'] }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('WHATSAPP_CLOUD_BASE_URL', anything).and_return('https://graph.facebook.com')
  end

  describe '#list' do
    # Os dois campos só chegam se forem pedidos. Sem eles a tela não tem como
    # mostrar por que um template foi recusado nem que a Meta rebaixou a
    # categoria pedida — que é o caso comum de UTILITY virando MARKETING.
    it 'asks Meta for the rejection reason and the previous category' do
      stub = stub_request(:get, %r{graph\.facebook\.com/v22\.0/#{waba_id}/message_templates})
             .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      service.list

      expect(stub.with { |req| req.uri.query_values['fields'].include?('rejected_reason') }).to have_been_made
      expect(stub.with { |req| req.uri.query_values['fields'].include?('previous_category') }).to have_been_made
    end

    it 'returns the templates Meta reports' do
      stub_request(:get, %r{graph\.facebook\.com/v22\.0/#{waba_id}/message_templates})
        .to_return(status: 200,
                   body: { data: [{ 'name' => 'oi', 'category' => 'MARKETING', 'previous_category' => 'UTILITY' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = service.list

      expect(result[:success]).to be(true)
      expect(result[:templates].first['previous_category']).to eq('UTILITY')
    end
  end
end
