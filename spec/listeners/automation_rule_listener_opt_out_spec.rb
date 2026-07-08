# frozen_string_literal: true

require 'rails_helper'

# Opt-out de compliance ("PARAR") no motor Flow: uma mensagem incoming de descadastro registra
# uma suppression de marketing e NÃO dispara flow algum por si (nem por-evento, nem keyword).
describe AutomationRuleListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before { Rails.cache.clear }
  after { Current.reset }

  def enable_flows_engine
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
  end

  # Keyword flow que casaria com "parar" (contains). Serve pra provar que o opt-out
  # curto-circuita o motor ANTES do keyword matching — sem o opt-out, este flow dispararia.
  def keyword_flow(keywords = %w[parar], label: 'kw-hit')
    node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [label] }
    create(:flow, account: account, trigger_type: :keyword,
                  trigger_config: { 'keywords' => keywords, 'match' => 'contains' },
                  definition: { 'nodes' => [node], 'edges' => [] })
  end

  def deliver(message)
    listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message }))
  end

  def incoming(content)
    create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :incoming, content: content)
  end

  describe 'opt-out ("PARAR")' do
    before do
      enable_flows_engine
      keyword_flow
    end

    it 'records a marketing opt-out suppression for the contact' do
      expect { deliver(incoming('PARAR')) }.to change(ContactFlowSuppression, :count).by(1)
      expect(ContactFlowSuppression.last).to have_attributes(contact_id: contact.id, category: 'marketing', reason: 'opt_out')
    end

    it 'does not fire any flow for the opt-out message (short-circuits before keyword matching)' do
      allow(Flows::RunnerService).to receive(:new).and_call_original
      deliver(incoming('PARAR'))
      expect(Flows::RunnerService).not_to have_received(:new)
      expect(conversation.reload.label_list).not_to include('kw-hit')
    end

    ['PARAR', 'Parar', 'sair', 'STOP', 'Cancelar', 'parar!', 'Parar.'].each do |word|
      it "recognises #{word.inspect} (case/accent/punctuation-insensitive)" do
        expect { deliver(incoming(word)) }.to change(ContactFlowSuppression, :count).by(1)
      end
    end

    it 'is idempotent across repeated opt-outs (no duplicate row)' do
      deliver(incoming('PARAR'))
      expect { deliver(incoming('parar')) }.not_to change(ContactFlowSuppression, :count)
    end

    it 'does NOT opt out on a sentence that merely contains the word — and the keyword flow fires normally' do
      allow(Flows::RunnerService).to receive(:new).and_call_original
      expect { deliver(incoming('não vou parar de comprar')) }.not_to change(ContactFlowSuppression, :count)
      expect(conversation.reload.label_list).to include('kw-hit')
      expect(Flows::RunnerService).to have_received(:new)
    end

    it 'ignores outgoing messages (an agent typing "parar" must not opt the contact out)' do
      expect do
        deliver(create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :outgoing, content: 'parar'))
      end.not_to change(ContactFlowSuppression, :count)
    end

    it 'ignores private notes' do
      expect do
        deliver(create(:message, conversation: conversation, inbox: inbox, account: account,
                                 message_type: :outgoing, private: true, content: 'parar'))
      end.not_to change(ContactFlowSuppression, :count)
    end
  end

  describe 'engine gating' do
    it 'does not record an opt-out when the flows engine is disabled (legacy engine path)' do
      keyword_flow # a flow exists, but the engine flag stays OFF
      expect { deliver(incoming('PARAR')) }.not_to change(ContactFlowSuppression, :count)
    end
  end
end
