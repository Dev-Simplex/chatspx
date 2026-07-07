require 'rails_helper'

describe AutomationRuleListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:created_event) do
    Events::Base.new('conversation_created', Time.zone.now, { conversation: conversation, changed_attributes: {} })
  end

  def event_flow(action_name = 'add_label', params = ['auto'])
    node = { 'id' => 'n1', 'type' => 'action', 'action_name' => action_name, 'action_params' => params }
    create(:flow, account: account, trigger_type: :conversation_event,
                  trigger_config: { 'event_name' => 'conversation_created', 'conditions' => [] },
                  definition: { 'nodes' => [node], 'edges' => [] })
  end

  def enable_flows_engine
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
  end

  before { Rails.cache.clear }

  describe 'engine gating by the `flows` feature flag' do
    context 'when the flows feature is enabled' do
      before do
        event_flow
        enable_flows_engine
      end

      it 'runs the Flow engine and the Flow acts on the conversation' do
        listener.conversation_created(created_event)
        expect(conversation.reload.label_list).to include('auto')
      end

      it 'does not run the legacy AutomationRule engine (R-1: no double execution)' do
        create(:automation_rule, event_name: 'conversation_created', account: account)
        allow(AutomationRules::ActionService).to receive(:new)
        listener.conversation_created(created_event)
        expect(AutomationRules::ActionService).not_to have_received(:new)
      end
    end

    context 'when the flows feature is disabled (default)' do
      before { event_flow }

      it 'does not run the Flow engine' do
        allow(Flows::RunnerService).to receive(:new)
        listener.conversation_created(created_event)
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'still runs the legacy AutomationRule engine' do
        create(:automation_rule, event_name: 'conversation_created', account: account, conditions: [])
        allow(AutomationRules::ActionService).to receive(:new).and_return(instance_double(AutomationRules::ActionService, perform: nil))
        listener.conversation_created(created_event)
        expect(AutomationRules::ActionService).to have_received(:new)
      end
    end

    # Fix da revisão adversarial: flag ON sem flows (backfill não rodado) NÃO pode silenciar
    # as automations — cai de volta no motor legado até existirem flows.
    context 'when flows is enabled but no flows exist yet (pre-backfill)' do
      before { enable_flows_engine }

      it 'falls back to the legacy engine instead of silencing automations' do
        create(:automation_rule, event_name: 'conversation_created', account: account, conditions: [])
        allow(AutomationRules::ActionService).to receive(:new).and_return(instance_double(AutomationRules::ActionService, perform: nil))
        allow(Flows::RunnerService).to receive(:new)
        listener.conversation_created(created_event)
        expect(AutomationRules::ActionService).to have_received(:new)
        expect(Flows::RunnerService).not_to have_received(:new)
      end
    end
  end

  describe 'anti-loop for engine-generated messages' do
    before { enable_flows_engine }

    it 'ignores message_created events carrying a flow_id (no re-trigger)' do
      allow(Flows::RunnerService).to receive(:new)
      message = create(:message, conversation: conversation, account: account, content_attributes: { 'flow_id' => 42 })
      event = Events::Base.new('message_created', Time.zone.now, { message: message })
      listener.message_created(event)
      expect(Flows::RunnerService).not_to have_received(:new)
    end
  end

  describe 'keyword trigger' do
    before { enable_flows_engine }

    after { Current.reset }

    def keyword_flow(keywords, match: 'contains', active: true, label: 'kw-hit')
      node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [label] }
      create(:flow, account: account, active: active, trigger_type: :keyword,
                    trigger_config: { 'keywords' => keywords, 'match' => match },
                    definition: { 'nodes' => [node], 'edges' => [] })
    end

    def deliver(message)
      listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message }))
    end

    def incoming(content)
      create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :incoming, content: content)
    end

    context 'with contains match (default)' do
      before { keyword_flow(%w[suporte ajuda]) }

      it 'fires when the message contains a keyword' do
        deliver(incoming('preciso de suporte agora'))
        expect(conversation.reload.label_list).to include('kw-hit')
      end

      it 'does not fire when no keyword is present' do
        deliver(incoming('bom dia'))
        expect(conversation.reload.label_list).not_to include('kw-hit')
      end

      it 'matches case-insensitively' do
        deliver(incoming('QUERO AJUDA'))
        expect(conversation.reload.label_list).to include('kw-hit')
      end

      it 'matches accent-insensitively (keyword accented, message not)' do
        keyword_flow(['horário'], label: 'accent-hit')
        deliver(incoming('qual o horario de atendimento?'))
        expect(conversation.reload.label_list).to include('accent-hit')
      end

      it 'matches accent-insensitively (message accented, keyword not)' do
        keyword_flow(['horario'], label: 'accent-hit')
        deliver(incoming('qual o horário?'))
        expect(conversation.reload.label_list).to include('accent-hit')
      end
    end

    context 'with exact match' do
      before { keyword_flow(%w[oi], match: 'exact') }

      it 'fires when the whole message equals a keyword (normalized)' do
        deliver(incoming('Oi'))
        expect(conversation.reload.label_list).to include('kw-hit')
      end

      it 'does not fire when the keyword is only a substring of the message' do
        deliver(incoming('oi, tudo bem?'))
        expect(conversation.reload.label_list).not_to include('kw-hit')
      end
    end

    context 'with ineligible messages' do
      before { keyword_flow(%w[suporte]) }

      it 'ignores outgoing messages' do
        allow(Flows::RunnerService).to receive(:new)
        deliver(create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :outgoing, content: 'suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'ignores private notes' do
        allow(Flows::RunnerService).to receive(:new)
        deliver(create(:message, conversation: conversation, inbox: inbox, account: account,
                                 message_type: :outgoing, private: true, content: 'suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'ignores activity messages' do
        allow(Flows::RunnerService).to receive(:new)
        deliver(create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :activity, content: 'suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end
    end

    context 'with guards' do
      it 'does not re-trigger on a message the flow itself generated (flow_id anti-loop)' do
        keyword_flow(%w[suporte])
        allow(Flows::RunnerService).to receive(:new)
        deliver(create(:message, conversation: conversation, inbox: inbox, account: account,
                                 message_type: :incoming, content: 'suporte', content_attributes: { 'flow_id' => 7 }))
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'does not fire an inactive keyword flow' do
        keyword_flow(%w[suporte], active: false)
        allow(Flows::RunnerService).to receive(:new)
        deliver(incoming('quero suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'does not fire when the keyword list is empty' do
        keyword_flow([])
        allow(Flows::RunnerService).to receive(:new)
        deliver(incoming('quero suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'does not fire when the flows engine is disabled for the account' do
        account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => false))
        keyword_flow(%w[suporte])
        allow(Flows::RunnerService).to receive(:new)
        deliver(incoming('quero suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end
    end
  end
end
