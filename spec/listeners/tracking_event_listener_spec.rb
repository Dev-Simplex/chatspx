require 'rails_helper'

# Bloco 5.03, o aceite literal: "resolver uma conversa gera o evento com event_id".
describe TrackingEventListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: user) }

  def resolved_event(at: Time.zone.now)
    Events::Base.new('conversation.resolved', at, conversation: conversation)
  end

  describe '#conversation_resolved' do
    it 'records chatspx_conversation_resolved with an event_id' do
      listener.conversation_resolved(resolved_event)

      event = TrackingEvent.last
      expect(event.name).to eq('chatspx_conversation_resolved')
      expect(event.event_id).to match(/\A[0-9a-f-]{36}\z/)
      expect(event.account_id).to eq(account.id)
      expect(event.inbox_id).to eq(inbox.id)
      expect(event.conversation_id).to eq(conversation.id)
      expect(event.source).to eq('server')
    end

    it 'carries the two parameters the contract declares for event #10' do
      moment = conversation.created_at + 7.minutes
      listener.conversation_resolved(resolved_event(at: moment))

      expect(TrackingEvent.last.properties).to eq({ 'resolution' => 'agent', 'duration_s' => 420 })
    end

    it 'says resolution: bot when no human ever replied' do
      bot_conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)
      event = Events::Base.new('conversation.resolved', Time.zone.now, conversation: bot_conversation)

      listener.conversation_resolved(event)

      expect(TrackingEvent.last.properties['resolution']).to eq('bot')
    end

    it 'points occurred_at at the FACT, not at the moment of writing' do
      moment = Time.zone.parse('2026-08-18 09:30:00')

      listener.conversation_resolved(resolved_event(at: moment))

      expect(TrackingEvent.last.occurred_at).to be_within(1.second).of(moment)
    end

    it 'attaches the contact when the conversation has one' do
      listener.conversation_resolved(resolved_event)

      expect(TrackingEvent.last.contact_id).to eq(conversation.contact_id)
    end

    # O AsyncDispatcher entrega por EventDispatcherJob.perform_later; job que falha e RETENTADO.
    it 'records ONE event when the job runs twice for the same fact' do
      moment = Time.zone.parse('2026-08-18 09:30:00')

      listener.conversation_resolved(resolved_event(at: moment))
      listener.conversation_resolved(resolved_event(at: moment))

      expect(TrackingEvent.where(name: 'chatspx_conversation_resolved').count).to eq(1)
    end

    it 'records TWO events when the conversation is resolved, reopened and resolved again' do
      listener.conversation_resolved(resolved_event(at: Time.zone.parse('2026-08-18 09:00:00')))
      listener.conversation_resolved(resolved_event(at: Time.zone.parse('2026-08-18 15:00:00')))

      expect(TrackingEvent.where(name: 'chatspx_conversation_resolved').count).to eq(2)
    end

    it 'does not create any delivery — deciding destinations is the job of 5.11' do
      listener.conversation_resolved(resolved_event)

      expect(TrackingDelivery.count).to eq(0)
    end

    # Observabilidade nunca pode quebrar o fluxo do produto (mesma regra do FlowStepLog).
    it 'never lets a recording failure break the resolution of a conversation' do
      allow(Tracking::EventRecorder).to receive(:record!).and_raise(StandardError.new('banco fora'))
      exception_tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(exception_tracker)

      expect { listener.conversation_resolved(resolved_event) }.not_to raise_error
      expect(ChatwootExceptionTracker).to have_received(:new)
    end
  end

  describe 'registration in the dispatcher' do
    it 'is subscribed to the async dispatcher, so it runs once per fact' do
      expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
    end

    it 'is NOT subscribed to the sync dispatcher, which would double every event' do
      expect(SyncDispatcher.new.listeners).not_to include(described_class.instance)
    end
  end
end
