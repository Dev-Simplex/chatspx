# frozen_string_literal: true

require 'rails_helper'

# W-C — a troca de responsavel so pode matar o menu do bot (wait_for_reply pendente) quando quem
# atribuiu foi um HUMANO de carne e osso. A guarda antiga era NEGATIVA (cancelava sempre) e por isso
# as atribuicoes AUTOMATICAS — o assign_agent do proprio flow, o round-robin, o PeriodicAssignmentJob
# e o Motor de Distribuicao — derrubavam o menu com o cliente no meio dele.
# Ver AutomationRuleListener#cancel_pending_flow_waits_on_assignment e #human_assignment_takeover?.
describe AutomationRuleListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let!(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent) }

  # Flow suspenso num wait_for_reply: e exatamente o menu que nao pode morrer sozinho.
  let!(:flow) do
    create(:flow, account: account, active: true, definition: {
             'nodes' => [
               { 'id' => 'wfr', 'type' => 'wait_for_reply', 'replies' => [{ 'key' => 'yes' }],
                 'timeout' => { 'enabled' => false }, 'fallback_key' => 'fallback' }
             ],
             'edges' => []
           })
  end

  let!(:run) do
    create(:flow_run, flow: flow, conversation: conversation, current_node_id: 'wfr',
                      wait_until: nil, status: :waiting)
  end

  before do
    Rails.cache.clear
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
    # `assignee_changed_by` so e escrito no payload com o gate ligado
    # (AssignmentHandler#assignment_change_event_data). Ver o exemplo "conta sem o gate" no fim.
    account.update!(settings: account.settings.merge('reply_assignment_gate' => true))
    # O listener roda no worker async (EventDispatcherJob/Sidekiq), onde Current nasce ZERADO: quem
    # executou a atribuicao so chega pelo event data. Todos os exemplos rodam nesse contexto.
    Current.reset
  end

  after { Current.reset }

  # Payload REAL de AssignmentHandler#notify_assignment_change -> Conversation#dispatcher_dispatch:
  #   performed_by        = Current.executed_by (so automacao preenche: AutomationRule/Flow/AssignmentPolicy/Inbox)
  #   assignee_changed_by = Current.user        (so o caminho humano preenche)
  def assignee_changed_event(performed_by: nil, assignee_changed_by: nil, conv: conversation)
    Events::Base.new(
      'assignee_changed',
      Time.zone.now,
      conversation: conv,
      notifiable_assignee_change: true,
      changed_attributes: { 'assignee_id' => [nil, conv.assignee_id] },
      performed_by: performed_by,
      assignee_changed_by: assignee_changed_by
    )
  end

  describe '#assignee_changed' do
    it 'cancela os waits pendentes quando um agente HUMANO assume a conversa' do
      listener.assignee_changed(assignee_changed_event(assignee_changed_by: agent))

      expect(run.reload).to be_completed
    end

    it 'NAO cancela quando o proprio flow atribuiu (assign_agent)' do
      # Flows::ActionService#initialize faz `Current.executed_by = flow` no modo automacao, entao o
      # payload chega com performed_by = Flow e sem ator humano.
      listener.assignee_changed(assignee_changed_event(performed_by: flow))

      expect(run.reload).to be_waiting
    end

    it 'NAO cancela quando o Motor de Distribuicao atribuiu' do
      # Spx::Distribuicao::DistribuirService#assign! -> Conversations::AssignmentService roda DENTRO
      # do Sidekiq (DesignacaoListener/RepasseService): o thread-local nasce zerado, entao nem
      # Current.executed_by nem Current.user existem e o payload chega SEM ator nenhum. E o caso que
      # a guarda negativa nao conseguia separar de um humano — e que agora fica de fora do cancelamento.
      listener.assignee_changed(assignee_changed_event(performed_by: nil, assignee_changed_by: nil))

      expect(run.reload).to be_waiting
    end

    it 'NAO cancela quando o round-robin/PeriodicAssignmentJob atribuiu' do
      # AutoAssignment::AssignmentService faz `Current.executed_by = inbox.assignment_policy || inbox`.
      listener.assignee_changed(assignee_changed_event(performed_by: inbox))

      expect(run.reload).to be_waiting
    end

    it 'NAO cancela quando uma regra de automacao atribuiu' do
      rule = create(:automation_rule, account: account, event_name: 'conversation_created')
      listener.assignee_changed(assignee_changed_event(performed_by: rule))

      expect(run.reload).to be_waiting
    end

    it 'NAO cancela quando a automacao rodou INLINE com um humano no Current.user' do
      # Motor de funil do Kanban re-entra sincrono dentro do request (Current.funnel_automation_depth):
      # o payload sai com os DOIS atores. Quem decidiu a atribuicao foi a regra, nao a pessoa.
      rule = create(:automation_rule, account: account, event_name: 'conversation_created')
      listener.assignee_changed(assignee_changed_event(performed_by: rule, assignee_changed_by: agent))

      expect(run.reload).to be_waiting
    end

    it 'NAO cancela ao DESATRIBUIR (assignee -> nil), mesmo com humano na acao' do
      conversation.update!(assignee: nil)

      listener.assignee_changed(assignee_changed_event(assignee_changed_by: agent))

      expect(run.reload).to be_waiting
    end

    it 'NAO cancela quando o ator do payload nao e um User (token de AgentBot)' do
      bot = create(:agent_bot, account: account)
      listener.assignee_changed(assignee_changed_event(assignee_changed_by: bot))

      expect(run.reload).to be_waiting
    end

    it 'nao cancela quando o motor de flows esta desligado na conta' do
      account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => false))

      listener.assignee_changed(assignee_changed_event(assignee_changed_by: agent))

      expect(run.reload).to be_waiting
    end

    it 'nao explode quando o evento vem sem conversa' do
      event = Events::Base.new('assignee_changed', Time.zone.now, conversation: nil)

      expect { listener.assignee_changed(event) }.not_to raise_error
      expect(run.reload).to be_waiting
    end
  end

  # Documenta a PROVENIENCIA do sinal — sem isto o resto do arquivo seria circular (payload montado
  # a mao). Prova, no proprio produtor, que `assignee_changed_by` distingue humano de Motor.
  describe 'proveniencia de assignee_changed_by (AssignmentHandler#assignment_change_event_data)' do
    it 'carrega o User quando quem atribui e um humano (contexto sincrono do request)' do
      Current.user = agent

      data = conversation.send(:assignment_change_event_data, Events::Types::ASSIGNEE_CHANGED)

      expect(data[:assignee_changed_by]).to eq(agent)
    end

    it 'vem NIL no worker do Motor de Distribuicao (Current zerado na thread do Sidekiq)' do
      Current.reset

      data = conversation.send(:assignment_change_event_data, Events::Types::ASSIGNEE_CHANGED)

      expect(data[:assignee_changed_by]).to be_nil
    end

    # O ator NAO depende mais do `reply_assignment_gate`. O gate foi removido do produtor
    # (assignment_handler.rb#assignment_change_event_data) porque as duas contas que rodam o motor
    # de flows — Catatau e AGN — o tem DESLIGADO: com o gate, nenhum ator chegaria ao listener
    # nelas e a atribuicao humana nunca cancelaria o menu, ou seja, a guarda nasceria morta
    # exatamente onde precisa funcionar. A notificacao de takeover, que era a outra consumidora,
    # tem portao PROPRIO em NotificationListener#notify_previous_assignee — nada foi ligado por
    # tabela. Este exemplo existe para impedir que o gate volte ao produtor sem que se perceba.
    it 'carrega o ator humano mesmo com a conta SEM o reply_assignment_gate' do
      account.update!(settings: account.settings.merge('reply_assignment_gate' => false))
      Current.user = agent

      data = conversation.reload.send(:assignment_change_event_data, Events::Types::ASSIGNEE_CHANGED)

      expect(data[:assignee_changed_by]).to eq(agent)
    end
  end
end
