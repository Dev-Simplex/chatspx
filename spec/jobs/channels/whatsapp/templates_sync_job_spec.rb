require 'rails_helper'

RSpec.describe Channels::Whatsapp::TemplatesSyncJob do
  let(:channel_whatsapp) { create(:channel_whatsapp, sync_templates: false) }

  it 'enqueues the job' do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    expect { described_class.perform_later(channel_whatsapp.id) }.to have_enqueued_job(described_class)
      .on_queue('low')
  end

  context 'when called' do
    it 'calls sync_templates' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      allow(channel_whatsapp).to receive(:sync_templates).and_return(true)
      expect(channel_whatsapp).to receive(:sync_templates)
      allow(Channel::Whatsapp).to receive(:find_by).with(id: channel_whatsapp.id).and_return(channel_whatsapp)
      described_class.perform_now(channel_whatsapp.id)
    end
  end
end
