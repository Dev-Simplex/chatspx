require 'rails_helper'

RSpec.describe HookJob do
  subject(:job) { described_class.perform_later(hook.id, event_name, message_id: message.id) }

  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:event_name) { 'message.created' }
  let(:message) { create(:message, account: account, content: 'muchas muchas gracias', message_type: :incoming) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(hook.id, event_name, message_id: message.id)
      .on_queue('medium')
  end

  context 'when the hook is disabled' do
    it 'does not execute the job' do
      hook = create(:integrations_hook, status: 'disabled', account: account)
      allow(SendOnSlackJob).to receive(:perform_later)
      allow(Integrations::Dialogflow::ProcessorService).to receive(:new)
      allow(Integrations::GoogleTranslate::DetectLanguageService).to receive(:new)

      expect(SendOnSlackJob).not_to receive(:perform_later)
      expect(Integrations::GoogleTranslate::DetectLanguageService).not_to receive(:new)
      expect(Integrations::Dialogflow::ProcessorService).not_to receive(:new)
      described_class.perform_now(hook.id, event_name, message_id: message.id)
    end
  end

  context 'when handleable events like message.created' do
    let(:process_service) { double }

    before do
      allow(process_service).to receive(:perform)
    end

    it 'calls SendOnSlackJob when its a slack hook' do
      hook = create(:integrations_hook, app_id: 'slack', account: account)
      allow(SendOnSlackJob).to receive(:perform_later).and_return(process_service)
      expect(SendOnSlackJob).to receive(:perform_later).with(message.id, hook.id)
      described_class.perform_now(hook.id, event_name, message_id: message.id)
    end

    it 'calls SendOnSlackJob when its a slack hook for message with attachments' do
      message_with_attachment = create(:message, :with_attachment, account: account)
      hook = create(:integrations_hook, app_id: 'slack', account: account)
      allow(SendOnSlackJob).to receive(:set).with(wait: 2.seconds).and_return(SendOnSlackJob)
      allow(SendOnSlackJob).to receive(:perform_later).and_return(process_service)
      expect(SendOnSlackJob).to receive(:perform_later).with(message_with_attachment.id, hook.id)
      described_class.perform_now(hook.id, event_name, message_id: message_with_attachment.id)
    end

    it 'calls Integrations::Dialogflow::ProcessorService when its a dialogflow intergation' do
      hook = create(:integrations_hook, :dialogflow, inbox: inbox, account: account)
      allow(Integrations::Dialogflow::ProcessorService).to receive(:new).and_return(process_service)
      expect(Integrations::Dialogflow::ProcessorService).to receive(:new).with(
        event_name: event_name, hook: hook, event_data: { message: message }
      )
      described_class.perform_now(hook.id, event_name, message_id: message.id)
    end

    it 'calls Conversations::DetectLanguageJob when its a google_translate intergation' do
      hook = create(:integrations_hook, :google_translate, account: account)
      allow(Integrations::GoogleTranslate::DetectLanguageService).to receive(:new).and_return(process_service)
      expect(Integrations::GoogleTranslate::DetectLanguageService).to receive(:new).with(hook: hook, message: message)
      described_class.perform_now(hook.id, event_name, message_id: message.id)
    end
  end

  context 'when processing leadsquared integration' do
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:processor_service) { instance_double(Crm::Leadsquared::ProcessorService) }
    let(:leadsquared_hook) { create(:integrations_hook, :leadsquared, account: account) }

    before do
      account.enable_features!('crm_integration')
      account.save!
      allow(Integrations::Hook).to receive(:find_by).and_call_original
      allow(Integrations::Hook).to receive(:find_by).with(id: leadsquared_hook.id).and_return(leadsquared_hook)
      allow(Crm::Leadsquared::ProcessorService).to receive(:new).with(leadsquared_hook).and_return(processor_service)
    end

    context 'when processing contact.updated event' do
      let(:event_name) { 'contact.updated' }

      it 'uses a lock when processing' do
        allow(leadsquared_hook).to receive(:feature_allowed?).and_return(true)
        allow(processor_service).to receive(:handle_contact).with(contact)

        job_instance = described_class.new
        allow(job_instance).to receive(:with_lock).and_yield
        allow(described_class).to receive(:new).and_return(job_instance)

        expect(job_instance).to receive(:with_lock).with(
          format(Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: leadsquared_hook.id)
        )

        job_instance.perform(leadsquared_hook.id, event_name, contact_id: contact.id)
      end

      it 'does not process when feature is not allowed' do
        allow(leadsquared_hook).to receive(:feature_allowed?).and_return(false)

        job_instance = described_class.new
        allow(job_instance).to receive(:with_lock)

        expect(job_instance).not_to receive(:with_lock)
        expect(processor_service).not_to receive(:handle_contact)

        job_instance.perform(leadsquared_hook.id, event_name, contact_id: contact.id)
      end
    end

    context 'when processing conversation.created event' do
      let(:event_name) { 'conversation.created' }

      it 'uses a lock when processing' do
        allow(leadsquared_hook).to receive(:feature_allowed?).and_return(true)
        allow(processor_service).to receive(:handle_conversation_created).with(conversation)

        job_instance = described_class.new
        allow(job_instance).to receive(:with_lock).and_yield
        allow(described_class).to receive(:new).and_return(job_instance)

        expect(job_instance).to receive(:with_lock).with(
          format(Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: leadsquared_hook.id)
        )

        job_instance.perform(leadsquared_hook.id, event_name, conversation_id: conversation.id)
      end
    end

    context 'when processing conversation.resolved event' do
      let(:event_name) { 'conversation.resolved' }

      it 'uses a lock when processing' do
        allow(leadsquared_hook).to receive(:feature_allowed?).and_return(true)
        allow(processor_service).to receive(:handle_conversation_resolved).with(conversation)

        job_instance = described_class.new
        allow(job_instance).to receive(:with_lock).and_yield
        allow(described_class).to receive(:new).and_return(job_instance)

        expect(job_instance).to receive(:with_lock).with(
          format(Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: leadsquared_hook.id)
        )

        job_instance.perform(leadsquared_hook.id, event_name, conversation_id: conversation.id)
      end
    end

    context 'when processing invalid event' do
      let(:event_name) { 'invalid.event' }

      it 'does not process for invalid event names' do
        allow(leadsquared_hook).to receive(:feature_allowed?).and_return(true)

        job_instance = described_class.new
        allow(job_instance).to receive(:with_lock)

        expect(job_instance).not_to receive(:with_lock)
        expect(processor_service).not_to receive(:handle_contact)

        job_instance.perform(leadsquared_hook.id, event_name, contact_id: contact.id)
      end
    end
  end
end
