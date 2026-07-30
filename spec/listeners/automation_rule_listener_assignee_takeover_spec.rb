# frozen_string_literal: true

require 'rails_helper'

# Um agente humano ASSUMIR a conversa ja encerra o menu do bot — nao da pra esperar ele digitar. O
# cancelamento so existia no caminho da MENSAGEM (cancel_pending_flow_waits_on_agent_reply), deixando
# aberta a janela entre "assumi" e "mandei a primeira mensagem": a resposta que o cliente manda nesse
# meio era capturada pelo wait_for_reply velho e virava "Nao entendi a opcao".
describe AutomationRuleListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before { Rails.cache.clear }
  after { Current.reset }

  def enable_flows_engine
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
  end

  def reply_flow
    create(:flow, account: account, active: true, definition: {
             'nodes' => [
               { 'id' => 'wfr', 'type' => 'wait_for_reply', 'replies' => [{ 'key' => 'yes' }],
                 'timeout' => { 'enabled' => false }, 'fallback_key' => 'fallback' }
             ],
             'edges' => []
           })
  end

  def waiting_run
    create(:flow_run, flow: reply_flow, conversation: conversation, current_node_id: 'wfr',
                      wait_until: nil, status: :waiting)
  end

  def fire_assignee_changed!
    listener.assignee_changed(
      Events::Base.new('assignee_changed', Time.zone.now, { conversation: conversation.reload })
    )
  end

  describe '#assignee_changed' do
    before { enable_flows_engine }

    it 'cancela o wait_for_reply pendente quando um agente humano assume' do
      run = waiting_run
      conversation.update!(assignee: agent)

      fire_assignee_changed!

      expect(run.reload).to be_completed
    end

    it 'NAO cancela quando a conversa e DESatribuida (volta para a fila)' do
      run = waiting_run
      conversation.update!(assignee: nil)

      fire_assignee_changed!

      expect(run.reload).to be_waiting
    end
  end
end
