# frozen_string_literal: true

require 'rails_helper'

# Regressao do LOOP do wait_for_reply (bug de producao AGN, 29/07). Religar o no de fallback
# ("Nao entendi a opcao.") de volta no no que reenvia a lista fazia o walker reencontrar o MESMO
# wait_for_reply dentro da MESMA retomada. Como o marcador de reentrada (@resume_start_id) nunca era
# consumido, o no NAO re-suspendia: re-ramificava com a resposta velha (@resume_reply, tambem nunca
# consumida), repetindo o ciclo ate MAX_STEPS=100 (~33 pares "lista + nao entendi" em rajada) e
# terminando por completar o run — o que ainda desarmava a espera.
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

  def open_window!
    create(:message, conversation: conversation, account: account, inbox: whatsapp_channel.inbox,
                     message_type: :incoming, content: 'oi', sender: contact)
  end

  # Menu COM religamento: si -> wfr -> (yes) a_yes | (fallback) a_fallback -> VOLTA para si.
  def cycle_definition
    {
      'nodes' => [
        { 'id' => 'si', 'type' => 'action', 'action_name' => 'send_interactive',
          'action_params' => [{ 'content' => 'Escolha uma opcao',
                                'items' => [{ 'title' => 'Sim', 'value' => 'yes' }] }] },
        { 'id' => 'wfr', 'type' => 'wait_for_reply', 'replies' => [{ 'key' => 'yes' }],
          'timeout' => { 'enabled' => false }, 'fallback_key' => 'fallback' },
        { 'id' => 'a_yes', 'type' => 'action', 'action_name' => 'assign_team', 'action_params' => [team.id] },
        { 'id' => 'a_fallback', 'type' => 'action', 'action_name' => 'send_message',
          'action_params' => ['Nao entendi a opcao.'] }
      ],
      'edges' => [
        { 'from' => 'si', 'to' => 'wfr' },
        { 'from' => 'wfr', 'to' => 'a_yes', 'branch' => 'yes' },
        { 'from' => 'wfr', 'to' => 'a_fallback' },
        { 'from' => 'a_fallback', 'to' => 'si' }
      ]
    }
  end

  def perform_until_wait(definition)
    flow = create(:flow, account: account, definition: definition)
    described_class.new(flow: flow, conversation: conversation).perform
    [flow, FlowRun.last]
  end

  def resume_with(flow, run, id)
    described_class.new(flow: flow, conversation: conversation, flow_run: run,
                        resume_reply: { id: id, title: id }).resume_from(run.current_node_id)
  end

  describe 'fallback religado na lista (ciclo no grafo)' do
    before { open_window! }

    it 'reenvia a lista e RE-SUSPENDE no wait_for_reply em vez de ciclar' do
      flow, run = perform_until_wait(cycle_definition)

      resume_with(flow, run, 'talvez')

      run.reload
      expect(run).to be_waiting
      expect(run.current_node_id).to eq('wfr')
    end

    it 'dispara o fallback UMA unica vez (nao a rajada de ~33)' do
      flow, run = perform_until_wait(cycle_definition)

      expect { resume_with(flow, run, 'talvez') }
        .to change { conversation.messages.where(content: 'Nao entendi a opcao.').count }.by(1)

      expect(conversation.messages.where(content: 'Nao entendi a opcao.').count).to eq(1)
    end

    it 'captura a resposta CORRETA enviada logo depois do fallback' do
      flow, run = perform_until_wait(cycle_definition)

      resume_with(flow, run, 'talvez')
      resume_with(flow, run.reload, 'yes')

      expect(conversation.reload.team_id).to eq(team.id)
      expect(run.reload).to be_completed
    end
  end

  describe 'ciclo de acoes (aresta malformada) estoura MAX_STEPS' do
    before { open_window! }

    # O ciclo precisa vir DEPOIS de um wait_for_reply: e a SUSPENSAO que materializa o FlowRun. Um
    # flow que nunca suspende nao cria run, entao nao existiria nada para marcar como failed — o
    # `@flow_run&.fail!` simplesmente nao teria alvo (e o `finish_run` tambem nao tinha).
    def cycle_after_wait_definition
      {
        'nodes' => [
          { 'id' => 'wfr', 'type' => 'wait_for_reply', 'replies' => [{ 'key' => 'yes' }],
            'timeout' => { 'enabled' => false }, 'fallback_key' => 'fallback' },
          { 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['a'] },
          { 'id' => 'n2', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['b'] }
        ],
        'edges' => [
          { 'from' => 'wfr', 'to' => 'n1', 'branch' => 'yes' },
          { 'from' => 'n1', 'to' => 'n2' },
          { 'from' => 'n2', 'to' => 'n1' }
        ]
      }
    end

    it 'marca o run como failed em vez de completed' do
      flow, run = perform_until_wait(cycle_after_wait_definition)

      resume_with(flow, run, 'yes')

      expect(run.reload).to be_failed
    end
  end
end
