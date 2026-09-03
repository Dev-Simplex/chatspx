require 'rails_helper'

RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:flow) { create(:flow, account: account) }
  let(:agent) { create(:user, account: account) }

  after { Current.reset }

  def action(name, params = [])
    { 'type' => 'action', 'action_name' => name, 'action_params' => params }
  end

  describe 'authorship — fusão dos dois overrides (§2.4)' do
    context 'when in automation mode (actor: nil)' do
      it 'sets Current.executed_by to the flow' do
        described_class.new(flow: flow, conversation: conversation)
        expect(Current.executed_by).to eq(flow)
      end

      it 'creates messages with a nil author and the flow_id anti-loop marker' do
        service = described_class.new(flow: flow, conversation: conversation)
        expect(Messages::MessageBuilder).to receive(:new) do |author, _conv, params|
          expect(author).to be_nil
          expect(params[:content_attributes]).to eq({ flow_id: flow.id })
          instance_double(Messages::MessageBuilder, perform: nil)
        end
        service.execute(action('send_message', ['Olá']))
      end
    end

    context 'when in manual mode (actor present)' do
      it 'sets Current.user to the actor' do
        described_class.new(flow: flow, conversation: conversation, actor: agent)
        expect(Current.user).to eq(agent)
      end

      it 'creates messages authored by the actor without the anti-loop marker' do
        service = described_class.new(flow: flow, conversation: conversation, actor: agent)
        expect(Messages::MessageBuilder).to receive(:new) do |author, _conv, params|
          expect(author).to eq(agent)
          expect(params[:content_attributes]).to eq({})
          instance_double(Messages::MessageBuilder, perform: nil)
        end
        service.execute(action('send_message', ['Olá']))
      end

      it 'resolves assign_agent "self" to the actor id' do
        create(:inbox_member, inbox: inbox, user: agent)
        service = described_class.new(flow: flow, conversation: conversation, actor: agent)
        service.execute(action('assign_agent', ['self']))
        expect(conversation.reload.assignee_id).to eq(agent.id)
      end
    end
  end

  describe '#execute' do
    it 'dispatches to a base ActionService action (reuso total)' do
      service = described_class.new(flow: flow, conversation: conversation)
      service.execute(action('add_label', ['vip']))
      expect(conversation.reload.label_list).to include('vip')
    end

    it 'is best-effort: a failing node is captured, never raised' do
      service = described_class.new(flow: flow, conversation: conversation)
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      expect { service.execute(action('nonexistent_action')) }.not_to raise_error
      expect(tracker).to have_received(:capture_exception)
    end
  end

  describe 'send_attachment' do
    it 'uses @flow.files as the attachment source' do
      flow.files.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      service = described_class.new(flow: flow, conversation: conversation)
      expect(Messages::MessageBuilder).to receive(:new).and_return(instance_double(Messages::MessageBuilder, perform: nil))
      service.execute(action('send_attachment', [flow.files.first.blob_id]))
    end
  end

  describe 'send_webhook_event' do
    # O bloco 4.13 passou a ASSINAR o webhook: a chamada deixou de ser `(url, payload)` e virou
    # `(url, payload, :account_webhook, secret:)`. Estas expectativas ficaram na forma antiga e
    # por isso nunca casavam. O que elas provam — o rotulo do evento — segue intacto; o resto
    # da assinatura entra como `hash_including(:secret)` para nao cravar o valor do segredo.
    it 'labels the event flow_event.<event> in automation mode' do
      flow.update!(trigger_type: :conversation_event, trigger_config: { 'event_name' => 'conversation_created' })
      service = described_class.new(flow: flow, conversation: conversation)
      expect(WebhookJob).to receive(:perform_later).with(
        'https://example.com', hash_including(event: 'flow_event.conversation_created'), :account_webhook, hash_including(:secret)
      )
      service.execute(action('send_webhook_event', ['https://example.com']))
    end

    it 'labels the event flow.executed in manual mode' do
      service = described_class.new(flow: flow, conversation: conversation, actor: agent)
      expect(WebhookJob).to receive(:perform_later).with(
        'https://example.com', hash_including(event: 'flow.executed'), :account_webhook, hash_including(:secret)
      )
      service.execute(action('send_webhook_event', ['https://example.com']))
    end

    it 'falls back to flow.executed when an automation-mode flow has no event_name' do
      service = described_class.new(flow: flow, conversation: conversation)
      expect(WebhookJob).to receive(:perform_later).with(
        'https://example.com', hash_including(event: 'flow.executed'), :account_webhook, hash_including(:secret)
      )
      service.execute(action('send_webhook_event', ['https://example.com']))
    end
  end

  # Regressão de paridade encontrada na revisão adversarial: Current.executed_by = flow não
  # era reconhecido pelos handlers de activity → a timeline perdia a entrada de sistema.
  describe 'activity message attribution (timeline não suprimida)' do
    it 'credits a status change to the automation system' do
      service = described_class.new(flow: flow, conversation: conversation)
      perform_enqueued_jobs { service.execute(action('resolve_conversation')) }
      activity = conversation.reload.messages.where(message_type: :activity).last
      expect(activity).to be_present
      expect(activity.content).to include(I18n.t('automation.system_name'))
    end

    it 'credits a priority change to the automation system' do
      service = described_class.new(flow: flow, conversation: conversation)
      perform_enqueued_jobs { service.execute(action('change_priority', ['urgent'])) }
      activity = conversation.reload.messages.where(message_type: :activity).last
      expect(activity).to be_present
      expect(activity.content).to include(I18n.t('automation.system_name'))
    end
  end
end
