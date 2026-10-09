# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalMessages::LinkPreviewJob do
  let(:channel) { create(:internal_channel, :with_two_members) }
  let(:message) { create(:internal_message, internal_channel: channel, content: 'olha isso https://exemplo.com/a.') }
  let(:preview) { { 'url' => 'https://exemplo.com/a', 'title' => 'Página A', 'domain' => 'exemplo.com' } }

  it 'stores the preview of the first link and broadcasts the updated message' do
    service = instance_double(InternalMessages::LinkPreviewService, perform: preview)
    allow(InternalMessages::LinkPreviewService).to receive(:new).with('https://exemplo.com/a').and_return(service)
    allow(InternalMessages::BroadcastService).to receive(:updated)

    described_class.perform_now(message.id)

    expect(message.reload.content_attributes['link_preview']).to eq(preview)
    expect(InternalMessages::BroadcastService).to have_received(:updated).with(message)
  end

  it 'keeps the message untouched when the preview fails' do
    service = instance_double(InternalMessages::LinkPreviewService, perform: nil)
    allow(InternalMessages::LinkPreviewService).to receive(:new).and_return(service)

    described_class.perform_now(message.id)

    expect(message.reload.content_attributes).not_to have_key('link_preview')
  end

  it 'is enqueued when a message with a link is created' do
    expect do
      InternalMessages::CreateService.new(channel: channel, user: channel.users.first, content: 'veja https://x.com').perform
    end.to have_enqueued_job(described_class)
  end
end
