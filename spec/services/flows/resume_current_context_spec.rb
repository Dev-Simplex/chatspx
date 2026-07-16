# frozen_string_literal: true

require 'rails_helper'

# Contexto do Current na RETOMADA de um flow (por RESPOSTA e por TEMPO).
#
# Bug: os dois services de retomada reentram o Flows::RunnerService DENTRO de um `with_lock`
# (transação aberta). O runner resetava o Current no seu `ensure`, ou seja, ANTES do commit — então
# os after_commit da Conversation acordavam sem contexto e o create_team_change_activity, que lê
# Current.executed_by, retornava cedo: a activity "Atribuído a <time> por Sistema de Automação"
# nunca nascia. O disparo INICIAL (#perform) não sofre disso porque roda FORA de transação.
#
# Fix: o reset virou responsabilidade de quem abre o contexto — os services resetam num `ensure`
# DEPOIS que o with_lock fecha. Estes specs cobrem os dois lados: o contexto vivo no commit E a
# ausência de vazamento do Current (thread_mattr_accessor + Sidekiq reusa threads).
#
# describe por STRING (não por classe): o comportamento é transversal aos DOIS services de retomada
# (ReplyResumeService/ResumeService) + o runner, e o controle compara com o disparo inicial.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Flows: contexto do Current na retomada' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, team_message_isolation: true) }
  let(:triagem) { create(:team, account: account, name: 'triagem') }
  let(:cobranca) { create(:team, account: account, name: 'cobranca') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: triagem) }

  after { Current.reset }

  # wait_for_reply -> (branch 'cobranca') -> assign_team cobranca. Espelha o menu da conta 1.
  def assign_team_flow
    create(:flow, account: account, definition: {
             'nodes' => [
               { 'id' => 'wfr', 'type' => 'wait_for_reply', 'replies' => [{ 'key' => 'cobranca' }],
                 'timeout' => { 'enabled' => false }, 'fallback_key' => 'fallback' },
               { 'id' => 'n8', 'type' => 'action', 'action_name' => 'assign_team', 'action_params' => [cobranca.id] }
             ],
             'edges' => [{ 'from' => 'wfr', 'to' => 'n8', 'branch' => 'cobranca' }]
           })
  end

  def team_change_activities
    enqueued_jobs.select { |job| job[:job] == Conversations::ActivityMessageJob }
  end

  def reply_run(flow)
    create(:flow_run, flow: flow, conversation: conversation, current_node_id: 'wfr',
                      wait_until: nil, status: :waiting)
  end

  describe 'retomada por RESPOSTA (Flows::ReplyResumeService, dentro de with_lock)' do
    it 'cria a activity de mudança de time atribuída ao Sistema de Automação' do
      reply_run(assign_team_flow)

      described = Flows::ReplyResumeService.new(conversation: conversation, reply: { id: 'cobranca', title: 'Cobrança' })
      described.perform

      expect(conversation.reload.team_id).to eq(cobranca.id)
      expect(team_change_activities).not_to be_empty
    end

    # Garantia anti-vazamento: o reset saiu do runner e virou do service — precisa continuar
    # limpando em TODO caminho de saída, senão o executed_by vaza pro próximo job da thread.
    it 'limpa o Current no fim (sucesso)' do
      reply_run(assign_team_flow)

      Flows::ReplyResumeService.new(conversation: conversation, reply: { id: 'cobranca', title: 'C' }).perform

      expect(Current.executed_by).to be_nil
      expect(Current.user).to be_nil
      expect(Current.flow_depth).to be_nil
    end

    it 'limpa o Current mesmo quando a retomada explode' do
      reply_run(assign_team_flow)
      allow(Flows::RunnerService).to receive(:new).and_raise(StandardError, 'boom')

      Flows::ReplyResumeService.new(conversation: conversation, reply: { id: 'cobranca', title: 'C' }).perform

      expect(Current.executed_by).to be_nil
    end

    it 'limpa o Current no early-return (nenhum run esperando resposta)' do
      Current.executed_by = create(:flow, account: account) # sujeira de um job anterior na thread

      Flows::ReplyResumeService.new(conversation: conversation, reply: { id: 'x' }).perform

      expect(Current.executed_by).to be_nil
    end
  end

  describe 'retomada por TEMPO (Flows::ResumeService, dentro de with_lock)' do
    # Mesmo formato do ReplyResumeService: reentra o runner dentro de um with_lock. Um `wait` puro
    # grava o SUCESSOR em current_node_id, então a reentrada cai direto no assign_team.
    def wait_flow
      create(:flow, account: account, definition: {
               'nodes' => [
                 { 'id' => 'w', 'type' => 'wait', 'wait' => { 'value' => 1, 'unit' => 'minutes' } },
                 { 'id' => 'n8', 'type' => 'action', 'action_name' => 'assign_team', 'action_params' => [cobranca.id] }
               ],
               'edges' => [{ 'from' => 'w', 'to' => 'n8' }]
             })
    end

    it 'cria a activity de mudança de time atribuída ao Sistema de Automação' do
      run = create(:flow_run, flow: wait_flow, conversation: conversation, current_node_id: 'n8',
                              wait_until: 1.minute.ago, status: :waiting)

      Flows::ResumeService.new(flow_run: run).perform

      expect(conversation.reload.team_id).to eq(cobranca.id)
      expect(team_change_activities).not_to be_empty
    end

    it 'limpa o Current no fim' do
      run = create(:flow_run, flow: wait_flow, conversation: conversation, current_node_id: 'n8',
                              wait_until: 1.minute.ago, status: :waiting)

      Flows::ResumeService.new(flow_run: run).perform

      expect(Current.executed_by).to be_nil
      expect(Current.flow_depth).to be_nil
    end
  end

  # Controle: o MESMO nó assign_team no disparo inicial (#perform, fora de transação) já funcionava
  # antes do fix — é o que provava que o problema era a transação, não o assign_team.
  describe 'disparo INICIAL (Flows::RunnerService#perform, fora de transação) — controle' do
    it 'cria a activity de mudança de time' do
      flow = create(:flow, account: account, definition: {
                      'nodes' => [{ 'id' => 'n23', 'type' => 'action', 'action_name' => 'assign_team',
                                    'action_params' => [cobranca.id] }],
                      'edges' => []
                    })

      Flows::RunnerService.new(flow: flow, conversation: conversation).perform

      expect(conversation.reload.team_id).to eq(cobranca.id)
      expect(team_change_activities).not_to be_empty
    end
  end

  # REGRESSÃO (não faz parte do bug do Current): a sincronia do team_id das mensagens é independente
  # do Current — o update_messages_team_id só depende de saved_change_to_team_id?. Estes dois specs
  # PASSAVAM antes do fix e ficam como guarda: o job é enfileirado e as mensagens seguem o time novo.
  describe 'team_id das mensagens na retomada (independente do Current)' do
    it 'enfileira o UpdateMessagesTeamIdJob' do
      reply_run(assign_team_flow)

      Flows::ReplyResumeService.new(conversation: conversation, reply: { id: 'cobranca', title: 'C' }).perform

      expect(Conversations::UpdateMessagesTeamIdJob).to have_been_enqueued.with(conversation.id, cobranca.id)
    end

    it 'sincroniza o team_id das mensagens antigas quando o job roda (elas não somem do time novo)' do
      reply_run(assign_team_flow)
      message = create(:message, conversation: conversation, account: account, inbox: inbox)
      expect(message.reload.team_id).to eq(triagem.id)

      perform_enqueued_jobs do
        Flows::ReplyResumeService.new(conversation: conversation, reply: { id: 'cobranca', title: 'C' }).perform
      end

      expect(message.reload.team_id).to eq(cobranca.id)
      expect(conversation.reload.messages).to include(message)
    end
  end
end

# rubocop:enable RSpec/DescribeClass
