# frozen_string_literal: true

require 'rails_helper'

# F2 — retomada de um wait_for_reply por MENSAGEM: acha o FlowRun `waiting` da conversa apontando um
# nó wait_for_reply, reentra o runner NESSE nó injetando o reply e ramifica pela opção escolhida.
RSpec.describe Flows::ReplyResumeService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  after { Current.reset }

  # Flow com um wait_for_reply e dois ramos por opção (add_label — sem WhatsApp).
  def reply_flow
    create(:flow, account: account, definition: {
             'nodes' => [
               { 'id' => 'wfr', 'type' => 'wait_for_reply', 'replies' => [{ 'key' => 'yes' }, { 'key' => 'no' }],
                 'timeout' => { 'enabled' => false }, 'fallback_key' => 'fallback' },
               { 'id' => 'a_yes', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['yes-branch'] },
               { 'id' => 'a_no', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['no-branch'] }
             ],
             'edges' => [
               { 'from' => 'wfr', 'to' => 'a_yes', 'branch' => 'yes' },
               { 'from' => 'wfr', 'to' => 'a_no', 'branch' => 'no' }
             ]
           })
  end

  def waiting_run(flow, node_id: 'wfr')
    create(:flow_run, flow: flow, conversation: conversation, current_node_id: node_id,
                      wait_until: nil, status: :waiting)
  end

  describe '#perform' do
    it 'resumes the waiting wait_for_reply run, branches on the reply id, and completes it' do
      run = waiting_run(reply_flow)

      result = described_class.new(conversation: conversation, reply: { id: 'yes', title: 'Sim' }).perform

      expect(result).to be(true)
      expect(conversation.reload.label_list).to include('yes-branch')
      expect(conversation.label_list).not_to include('no-branch')
      expect(run.reload).to be_completed
    end

    it 'returns false when the conversation has no waiting wait_for_reply run' do
      expect(described_class.new(conversation: conversation, reply: { id: 'yes' }).perform).to be(false)
    end

    it 'ignores a waiting run whose current_node_id is NOT a wait_for_reply (e.g. a pure `wait` successor)' do
      flow = create(:flow, account: account, definition: {
                      'nodes' => [{ 'id' => 'n2', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['x'] }],
                      'edges' => []
                    })
      run = waiting_run(flow, node_id: 'n2')

      expect(described_class.new(conversation: conversation, reply: { id: 'yes' }).perform).to be(false)
      expect(run.reload).to be_waiting # intocado
      expect(conversation.reload.label_list).not_to include('x')
    end

    it 'is best-effort: swallows the error, marks the run failed, and returns false when the resume raises' do
      run = waiting_run(reply_flow)
      allow(Flows::RunnerService).to receive(:new).and_raise(StandardError, 'boom')

      result = nil
      expect { result = described_class.new(conversation: conversation, reply: { id: 'yes' }).perform }.not_to raise_error
      expect(result).to be(false)
      expect(run.reload).to be_failed
    end

    # O índice único parcial permite no máx 1 run in-flight por (flow, conversation) — então vários
    # runs waiting numa mesma conversa vêm de FLOWS distintos. Retomamos o mais recente.
    it 'picks the most-recently-updated waiting wait_for_reply run when several exist' do
      old_run = waiting_run(reply_flow)
      old_run.update!(updated_at: 1.hour.ago)
      newer_run = waiting_run(reply_flow) # flow diferente (reply_flow cria um novo a cada chamada)

      described_class.new(conversation: conversation, reply: { id: 'no', title: 'Não' }).perform

      expect(newer_run.reload).to be_completed
      expect(old_run.reload).to be_waiting
      expect(conversation.reload.label_list).to include('no-branch')
    end
  end
end
