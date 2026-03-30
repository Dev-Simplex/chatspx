require 'rails_helper'

RSpec.describe Channels::Twilio::TemplatesSyncJob do
  let!(:account) { create(:account) }
  let!(:twilio_channel) { create(:channel_twilio_sms, medium: :whatsapp, account: account) }

  it 'enqueues the job' do
    expect { described_class.perform_later(twilio_channel.id) }.to have_enqueued_job(described_class)
      .on_queue('low')
      .with(twilio_channel.id)
  end

  describe '#perform' do
    let(:template_sync_service) { instance_double(Twilio::TemplateSyncService) }

    context 'with successful template sync' do
      it 'creates and calls the template sync service' do
        expect(Twilio::TemplateSyncService).to receive(:new).with(channel: twilio_channel).and_return(template_sync_service)
        expect(template_sync_service).to receive(:call).and_return(true)

        described_class.perform_now(twilio_channel.id)
      end
    end

    context 'with template sync exception' do
      let(:error_message) { 'Twilio API error' }

      before do
        allow(Twilio::TemplateSyncService).to receive(:new).with(channel: twilio_channel).and_return(template_sync_service)
        allow(template_sync_service).to receive(:call).and_raise(StandardError, error_message)
      end

      it 'does not suppress the exception' do
        expect { described_class.perform_now(twilio_channel.id) }.to raise_error(StandardError, error_message)
      end
    end

    context 'with nil channel id' do
      it 'returns early when channel not found' do
        expect(Twilio::TemplateSyncService).not_to receive(:new)

        described_class.perform_now(0)
      end
    end
  end

  describe 'job configuration' do
    it 'is configured to run on low priority queue' do
      expect(described_class.queue_name).to eq('low')
    end
  end
end
