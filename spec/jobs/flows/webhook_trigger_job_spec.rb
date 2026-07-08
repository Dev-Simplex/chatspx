# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flows::WebhookTriggerJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:flow) { create(:flow, account: account, trigger_type: :external_webhook, active: true) }
  let(:runner) { instance_double(Flows::RunnerService, perform: true) }

  before do
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
    allow(Flows::RunnerService).to receive(:new).and_return(runner)
  end

  it 'runs the RunnerService over the resolved conversation' do
    described_class.perform_now(flow.id, conversation_display_id: conversation.display_id, payload: { 'trigger' => 'external_webhook' })

    expect(Flows::RunnerService).to have_received(:new).with(
      flow: flow, conversation: conversation, trigger_payload: { 'trigger' => 'external_webhook' }
    )
    expect(runner).to have_received(:perform)
  end

  it 'is a no-op when the flow no longer exists' do
    described_class.perform_now(-1, conversation_display_id: conversation.display_id)
    expect(Flows::RunnerService).not_to have_received(:new)
  end

  it 'is a no-op when the flow is inactive (re-validated after enqueue)' do
    flow.update!(active: false)
    described_class.perform_now(flow.id, conversation_display_id: conversation.display_id)
    expect(Flows::RunnerService).not_to have_received(:new)
  end

  it 'is a no-op when the flow is no longer a webhook' do
    flow.update!(trigger_type: :manual)
    described_class.perform_now(flow.id, conversation_display_id: conversation.display_id)
    expect(Flows::RunnerService).not_to have_received(:new)
  end

  it 'is a no-op when the account engine was turned off' do
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => false))
    described_class.perform_now(flow.id, conversation_display_id: conversation.display_id)
    expect(Flows::RunnerService).not_to have_received(:new)
  end

  it 'is a no-op when the target conversation was deleted' do
    described_class.perform_now(flow.id, conversation_display_id: 999_999)
    expect(Flows::RunnerService).not_to have_received(:new)
  end

  it 'isolates a RunnerService error into the exception tracker (never re-raises)' do
    allow(runner).to receive(:perform).and_raise(StandardError, 'boom')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    expect do
      described_class.perform_now(flow.id, conversation_display_id: conversation.display_id)
    end.not_to raise_error
    expect(tracker).to have_received(:capture_exception)
  end
end
