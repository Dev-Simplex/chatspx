# frozen_string_literal: true

require 'rails_helper'

# F2 — o loop completo do wait_for_reply no motor: send_interactive (F1) envia as opções → o nó
# wait_for_reply SUSPENDE esperando a resposta → a retomada RAMIFICA pela opção escolhida (id da
# reply == value da opção == edge.branch) OU por 'timeout' (retomada por tempo). Sem HTTP real: o
# MessageBuilder só cria a Message; o envio ao canal é um job não performado aqui (adapter :test).
# Ver o contrato (fonte de verdade) em plano/F2-contrato-wait-for-reply.md §AGENTE B.
RSpec.describe Flows::RunnerService do
  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              sync_templates: false, validate_provider_config: false)
  end
  let(:conversation) { create(:conversation, account: account, inbox: whatsapp_channel.inbox) }
  let(:contact) { conversation.contact }

  after { Current.reset }

  # Abre a janela de 24h (a conversa WhatsApp nasce fora dela) com um incoming recente do contato,
  # pra o send_interactive/send_message passarem no compliance (utility, free_form).
  def open_window!
    create(:message, conversation: conversation, account: account, inbox: whatsapp_channel.inbox,
                     message_type: :incoming, content: 'oi', sender: contact)
  end

  # Loop completo: send_interactive (2 opções) → wait_for_reply → branches
  # [yes: assign_team] / [no: send_message] / [timeout: add_label] / [fallback (aresta sem rótulo): add_label].
  def loop_definition(timeout: { 'enabled' => false }) # rubocop:disable Metrics/MethodLength
    {
      'nodes' => [
        { 'id' => 'si', 'type' => 'action', 'action_name' => 'send_interactive',
          'action_params' => [{ 'content' => 'Confirma?',
                                'items' => [{ 'title' => 'Sim', 'value' => 'yes' },
                                            { 'title' => 'Não', 'value' => 'no' }] }] },
        { 'id' => 'wfr', 'type' => 'wait_for_reply',
          'replies' => [{ 'key' => 'yes' }, { 'key' => 'no' }],
          'timeout' => timeout, 'fallback_key' => 'fallback' },
        { 'id' => 'a_yes', 'type' => 'action', 'action_name' => 'assign_team', 'action_params' => [team.id] },
        { 'id' => 'a_no', 'type' => 'action', 'action_name' => 'send_message', 'action_params' => ['Tudo bem!'] },
        { 'id' => 'a_timeout', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['sem-resposta'] },
        { 'id' => 'a_fallback', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['nao-entendi'] }
      ],
      'edges' => [
        { 'from' => 'si', 'to' => 'wfr' },
        { 'from' => 'wfr', 'to' => 'a_yes', 'branch' => 'yes' },
        { 'from' => 'wfr', 'to' => 'a_no', 'branch' => 'no' },
        { 'from' => 'wfr', 'to' => 'a_timeout', 'branch' => 'timeout' },
        { 'from' => 'wfr', 'to' => 'a_fallback' } # sem branch = fallback (aresta sem rótulo)
      ]
    }
  end

  def build_flow(definition)
    create(:flow, account: account, definition: definition)
  end

  # Roda o flow do início e devolve [flow, o FlowRun suspenso no wait_for_reply].
  def perform_until_wait(definition)
    flow = build_flow(definition)
    described_class.new(flow: flow, conversation: conversation).perform
    [flow, FlowRun.last]
  end

  describe 'first touch — suspends waiting for the reply' do
    before { open_window! }

    it 'sends the interactive, suspends at the wait_for_reply node (itself) with wait_until nil, and skips the branches' do
      expect do
        flow = build_flow(loop_definition)
        described_class.new(flow: flow, conversation: conversation).perform
      end.to change(FlowRun, :count).by(1)

      run = FlowRun.last
      expect(run).to be_waiting
      expect(run.current_node_id).to eq('wfr') # o PRÓPRIO nó de reentrada, não o sucessor
      expect(run.wait_until).to be_nil          # sem timeout → espera indefinida pela resposta

      # send_interactive efetivado (mensagem outgoing input_select); nenhum branch executado.
      expect(conversation.reload.messages.where(message_type: :outgoing).last.content_type).to eq('input_select')
      expect(conversation.team_id).to be_nil
      expect(conversation.label_list).not_to include('sem-resposta', 'nao-entendi')
    end
  end

  describe 'resume by reply — branches on the chosen option' do
    before { open_window! }

    it "reply 'yes' → follows branch A (assign_team) and completes the run" do
      flow, run = perform_until_wait(loop_definition)

      described_class.new(flow: flow, conversation: conversation, flow_run: run,
                          resume_reply: { id: 'yes', title: 'Sim' }).resume_from(run.current_node_id)

      expect(conversation.reload.team_id).to eq(team.id)
      expect(run.reload).to be_completed
      expect(run.current_node_id).to be_nil
      expect(run.wait_until).to be_nil
    end

    it "reply 'no' → follows branch B (send_message)" do
      flow, run = perform_until_wait(loop_definition)

      expect do
        described_class.new(flow: flow, conversation: conversation, flow_run: run,
                            resume_reply: { id: 'no', title: 'Não' }).resume_from(run.current_node_id)
      end.to change { conversation.messages.where(message_type: :outgoing, content: 'Tudo bem!').count }.by(1)

      expect(conversation.reload.team_id).to be_nil
      expect(run.reload).to be_completed
    end

    it 'an unknown reply value falls back to the unlabeled edge (fallback branch)' do
      flow, run = perform_until_wait(loop_definition)

      described_class.new(flow: flow, conversation: conversation, flow_run: run,
                          resume_reply: { id: 'talvez', title: 'Talvez' }).resume_from(run.current_node_id)

      expect(conversation.reload.label_list).to include('nao-entendi')
      expect(conversation.team_id).to be_nil
      expect(run.reload).to be_completed
    end
  end

  describe 'timeout — resume by time follows the timeout branch' do
    before { open_window! }

    it 'sets wait_until to the deadline when timeout is enabled (and still suspends at the node itself)' do
      _flow, run = perform_until_wait(loop_definition(timeout: { 'enabled' => true, 'value' => 2, 'unit' => 'hours' }))

      expect(run.current_node_id).to eq('wfr')
      expect(run.wait_until).to be_within(1.minute).of(2.hours.from_now)
    end

    it "a time-based resume (no reply) follows the 'timeout' branch via Flows::ResumeService" do
      _flow, run = perform_until_wait(loop_definition(timeout: { 'enabled' => true, 'value' => 2, 'unit' => 'hours' }))
      run.update!(wait_until: 1.minute.ago) # o prazo venceu → o ResumeJob pegaria como `due`

      Flows::ResumeService.new(flow_run: run).perform

      expect(conversation.reload.label_list).to include('sem-resposta')
      expect(conversation.label_list).not_to include('nao-entendi')
      expect(conversation.team_id).to be_nil
      expect(run.reload).to be_completed
    end
  end

  describe 'non-regression — the pure `wait` (time) is unchanged' do
    it 'still stores the SUCCESSOR (not the wait node) and a wait_until deadline' do
      flow = build_flow(
        'nodes' => [
          { 'id' => 'w1', 'type' => 'wait', 'wait' => { 'value' => 5, 'unit' => 'minutes' } },
          { 'id' => 'n2', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['after'] }
        ],
        'edges' => [{ 'from' => 'w1', 'to' => 'n2' }]
      )

      described_class.new(flow: flow, conversation: conversation).perform

      run = FlowRun.last
      expect(run.current_node_id).to eq('n2') # sucessor — comportamento do `wait` intacto
      expect(run.wait_until).to be_within(1.minute).of(5.minutes.from_now)
    end
  end

  describe 'dry-run — traverses wait_for_reply without suspending' do
    it 'records the wait_for_reply as a passthrough, keeps walking, and creates no FlowRun' do
      flow = build_flow(
        'nodes' => [
          { 'id' => 'a', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['a'] },
          { 'id' => 'wfr', 'type' => 'wait_for_reply', 'replies' => [{ 'key' => 'x' }], 'timeout' => { 'enabled' => false } },
          { 'id' => 'b', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['b'] }
        ],
        'edges' => [{ 'from' => 'a', 'to' => 'wfr' }, { 'from' => 'wfr', 'to' => 'b' }]
      )

      steps = nil
      expect do
        steps = described_class.new(flow: flow, conversation: conversation).simulate
      end.not_to change(FlowRun, :count)

      expect(steps.map { |s| s[:type] }).to include('wait_for_reply')
      expect(steps.map { |s| s[:node_id] }).to include('b') # atravessou até o nó depois do wait_for_reply
      expect(conversation.reload.label_list).to be_empty     # nada efetivado
    end
  end
end
