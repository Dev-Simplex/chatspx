# frozen_string_literal: true

require 'rails_helper'

# F2 — o AutomationRuleListener retoma um wait_for_reply pendente quando o contato responde e dá
# early-return: a resposta pertence ao flow ativo, então NÃO dispara um flow novo (por-evento/keyword)
# com a mesma mensagem (espelha o early-return do opt-out). Ver AutomationRuleListener#resume_pending_reply.
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

  # Flow suspenso esperando resposta: wfr → [yes: add_label 'resumed'].
  def reply_flow
    create(:flow, account: account, active: true, definition: {
             'nodes' => [
               { 'id' => 'wfr', 'type' => 'wait_for_reply', 'replies' => [{ 'key' => 'yes' }],
                 'timeout' => { 'enabled' => false }, 'fallback_key' => 'fallback' },
               { 'id' => 'a_yes', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['resumed'] }
             ],
             'edges' => [{ 'from' => 'wfr', 'to' => 'a_yes', 'branch' => 'yes' }]
           })
  end

  def waiting_run(flow)
    create(:flow_run, flow: flow, conversation: conversation, current_node_id: 'wfr',
                      wait_until: nil, status: :waiting)
  end

  # Keyword flow que casaria com 'yes' — prova o short-circuit: sem a retomada, ele dispararia
  # com a mesma mensagem.
  def keyword_flow
    create(:flow, account: account, active: true, trigger_type: :keyword,
                  trigger_config: { 'keywords' => ['yes'], 'match' => 'contains' },
                  definition: { 'nodes' => [{ 'id' => 'k', 'type' => 'action', 'action_name' => 'add_label',
                                              'action_params' => ['kw-hit'] }], 'edges' => [] })
  end

  def deliver(message)
    listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message }))
  end

  def incoming(content, content_attributes: {})
    create(:message, conversation: conversation, inbox: inbox, account: account,
                     message_type: :incoming, content: content, content_attributes: content_attributes)
  end

  describe 'resuming a pending wait_for_reply' do
    before { enable_flows_engine }

    it 'resumes via the button/list reply id (selected_option) and does not fire a new flow' do
      run = waiting_run(reply_flow)
      keyword_flow

      deliver(incoming('Sim', content_attributes: { 'selected_option' => { 'id' => 'yes', 'title' => 'Sim' } }))

      expect(conversation.reload.label_list).to include('resumed')
      expect(conversation.label_list).not_to include('kw-hit') # early-return: keyword NÃO disparou
      expect(run.reload).to be_completed
    end

    it 'resumes via a typed reply (no selected_option) matching the option value as content' do
      run = waiting_run(reply_flow)

      deliver(incoming('yes'))

      expect(conversation.reload.label_list).to include('resumed')
      expect(run.reload).to be_completed
    end

    it 'does not consume an outgoing message (only incoming replies resume)' do
      run = waiting_run(reply_flow)
      allow(Flows::ReplyResumeService).to receive(:new).and_call_original

      # Trait `:bot_message` de proposito — e o unico jeito de a saida ficar SEM remetente: o
      # `after(:build)` da fabrica usa `||=`, entao passar `sender: nil` nao adianta.
      # A fabrica poe um User como remetente, e mensagem de saida com
      # remetente User e exatamente a definicao de `human_agent_takeover?` — que CANCELA as esperas
      # pendentes (`cancel_pending_flow_waits`), por decisao documentada no listener. O run saia de
      # `waiting` por essa regra, nao por retomada, e o exemplo acusava a coisa errada.
      #
      # Sem remetente humano, as duas regras ficam separadas: aqui se prova que saida NAO retoma;
      # o cancelamento por tomada humana e assunto de outro exemplo.
      deliver(create(:message, :bot_message, conversation: conversation, inbox: inbox, account: account,
                                             content: 'yes'))

      expect(Flows::ReplyResumeService).not_to have_received(:new)
      expect(run.reload).to be_waiting
    end

    it 'lets the message flow to normal dispatch when there is NO pending wait_for_reply' do
      keyword_flow # sem waiting_run

      deliver(incoming('yes'))

      expect(conversation.reload.label_list).to include('kw-hit') # caminho normal — não-regressão
    end

    it 'opt-out ("PARAR") wins over reply resume (compliance short-circuits first)' do
      run = waiting_run(reply_flow)

      expect { deliver(incoming('PARAR')) }.to change(ContactFlowSuppression, :count).by(1)
      expect(run.reload).to be_waiting # não retomou — o opt-out abortou antes
      expect(conversation.reload.label_list).not_to include('resumed')
    end
  end
end
