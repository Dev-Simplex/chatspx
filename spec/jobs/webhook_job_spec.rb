require 'rails_helper'

RSpec.describe WebhookJob do
  include ActiveJob::TestHelper

  subject(:job) { described_class.perform_later(url, payload, webhook_type) }

  let(:url) { 'https://test.chatwoot.com' }
  let(:payload) { { name: 'test' } }
  let(:webhook_type) { :account_webhook }

  it 'queues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(url, payload, webhook_type)
      .on_queue('medium')
  end

  it 'executes perform with default webhook type' do
    expect(Webhooks::Trigger).to receive(:execute).with(url, payload, webhook_type, secret: nil, delivery_id: nil)
    perform_enqueued_jobs { job }
  end

  context 'when the destination is down' do
    let(:payload) { { event: 'conversation_created' } }

    it 'retries up to 5 attempts and handles the failure only after the last one' do
      allow(RestClient::Request).to receive(:execute).and_raise(RestClient::ServiceUnavailable.new(nil, 503))
      allow(Rails.logger).to receive(:warn)

      perform_enqueued_jobs { job }

      expect(RestClient::Request).to have_received(:execute).exactly(5).times
      expect(Rails.logger).to have_received(:warn).with(/Invalid webhook URL/).once
    end
  end

  context 'with custom webhook type' do
    let(:webhook_type) { :api_inbox_webhook }

    it 'executes perform with inbox webhook type' do
      expect(Webhooks::Trigger).to receive(:execute).with(url, payload, webhook_type, secret: nil, delivery_id: nil)
      perform_enqueued_jobs { job }
    end
  end
end
