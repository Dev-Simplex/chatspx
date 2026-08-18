# frozen_string_literal: true

require 'rails_helper'

# 4.01 — A PONTE QUE FALTA.
#
# No WhatsApp, tocar num botão/lista gera uma mensagem `incoming` com
# `content_attributes.selected_option` (Whatsapp::IncomingMessageBaseService, :187) — e é ela que o
# AutomationRuleListener#resume_pending_reply consome para retomar um `wait_for_reply`.
#
# No canal WEB isso não existia: clicar numa opção do widget só gravava `submitted_values` na
# própria mensagem OUTGOING (PATCH /api/v1/widget/messages/:id), nenhuma mensagem incoming nascia,
# e por isso o FlowRun ficava `waiting` PARA SEMPRE. Este spec mede as duas metades do aceite:
#
#   (a) o flow avança quando o visitante clica — 2 cliques = 1 mensagem e 1 retomada;
#   (b) com o motor desligado, NADA muda (nem mensagem nova, nem efeito colateral).
RSpec.describe '/api/v1/widget/messages — ponte input_select/form → incoming (4.01)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, email: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:conversation) do
    create(:conversation, contact: contact, account: account, inbox: web_widget.inbox, contact_inbox: contact_inbox)
  end
  let(:auth_payload) { { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id } }
  let(:token) { Widget::TokenService.new(payload: auth_payload).generate_token }

  after { Current.reset }

  # Motor Flow ligado para a conta (mesmo gate do AutomationRuleListener#flows_engine_active?:
  # a flag em internal_attributes + existir flow ativo).
  def enable_flows_engine!
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
  end

  # Flow suspenso num wait_for_reply, com um ramo por opção (add_label — sem canal externo).
  def wait_for_reply_flow
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

  # A mensagem que o `send_interactive` (F1) já cria hoje no canal web: outgoing, input_select,
  # com `items` e a marca `flow_id` (anti-loop do listener).
  def interactive_message(flow)
    create(:message, account: account, inbox: web_widget.inbox, conversation: conversation,
                     message_type: :outgoing, content: 'Confirma?', content_type: 'input_select',
                     content_attributes: { 'items' => [{ 'title' => 'Sim', 'value' => 'yes' },
                                                       { 'title' => 'Não', 'value' => 'no' }],
                                           'flow_id' => flow.id })
  end

  # O AutomationRuleListener mora no AsyncDispatcher (EventDispatcherJob) — a retomada NÃO acontece
  # dentro da requisição, e sim no worker. `clear_enqueued_jobs` antes isola o que ESTE clique
  # enfileirou do ruído das factories; o `perform_enqueued_jobs` depois roda o worker de verdade.
  def click_option(message, title:, value:)
    clear_enqueued_jobs
    put api_v1_widget_message_url(message.id),
        params: { website_token: web_widget.website_token, message: { submitted_values: [{ title: title, value: value }] } },
        headers: { 'X-Auth-Token' => token },
        as: :json
    perform_enqueued_jobs(only: EventDispatcherJob)
  end

  def submit_form(message, values)
    clear_enqueued_jobs
    put api_v1_widget_message_url(message.id),
        params: { website_token: web_widget.website_token, message: { submitted_values: values } },
        headers: { 'X-Auth-Token' => token },
        as: :json
    perform_enqueued_jobs(only: EventDispatcherJob)
  end

  describe 'clicking an option on an input_select' do
    let(:flow) { wait_for_reply_flow }
    let!(:message) { interactive_message(flow) }
    let!(:run) do
      create(:flow_run, flow: flow, account: account, conversation: conversation, contact: contact,
                        current_node_id: 'wfr', wait_until: nil, status: :waiting)
    end

    before { enable_flows_engine! }

    it 'creates exactly ONE incoming message' do
      expect { click_option(message, title: 'Sim', value: 'yes') }
        .to change { conversation.messages.incoming.count }.from(0).to(1)

      expect(response).to have_http_status(:success)
    end

    it 'shapes the incoming message exactly like the WhatsApp interactive reply' do
      click_option(message, title: 'Sim', value: 'yes')

      reply = conversation.messages.incoming.last
      expect(reply.content).to eq('Sim')
      expect(reply.content_attributes['selected_option']).to eq({ 'id' => 'yes', 'title' => 'Sim' })
      expect(reply.content_attributes['in_reply_to']).to eq(message.id)
      expect(reply.sender).to eq(contact)
      # NÃO pode carregar flow_id: senão o próprio listener a ignoraria como "gerada pela automação".
      expect(reply.content_attributes['flow_id']).to be_nil
    end

    it 'resumes the waiting wait_for_reply on the branch of the chosen option' do
      click_option(message, title: 'Sim', value: 'yes')

      expect(run.reload).to be_completed
      expect(conversation.reload.label_list).to include('yes-branch')
      expect(conversation.label_list).not_to include('no-branch')
    end

    it 'marks the structured message with reply_message_id so the widget does not draw a duplicate bubble' do
      click_option(message, title: 'Sim', value: 'yes')

      expect(message.reload.content_attributes['reply_message_id']).to eq(conversation.messages.incoming.last.id)
    end

    it 'keeps recording submitted_values on the original outgoing message (non-regression)' do
      click_option(message, title: 'Sim', value: 'yes')

      expect(message.reload.content_attributes['submitted_values']).to eq([{ 'title' => 'Sim', 'value' => 'yes' }])
    end

    it 'is idempotent: 2 clicks = 1 incoming message and 1 resume' do
      click_option(message, title: 'Sim', value: 'yes')
      expect(conversation.messages.incoming.count).to eq(1)

      # Segundo clique (double-click, retry de rede, aba duplicada): não pode nascer 2ª mensagem
      # nem retomar o flow de novo por outro ramo.
      expect { click_option(message, title: 'Não', value: 'no') }
        .not_to(change { conversation.messages.incoming.count })

      expect(response).to have_http_status(:success)
      expect(conversation.reload.label_list).to include('yes-branch')
      expect(conversation.label_list).not_to include('no-branch')
      expect(FlowRun.where(conversation: conversation).count).to eq(1)
    end
  end

  describe 'submitting a form' do
    let(:flow) { wait_for_reply_flow }
    let!(:form_message) do
      create(:message, account: account, inbox: web_widget.inbox, conversation: conversation,
                       message_type: :outgoing, content: 'Seus dados', content_type: 'form',
                       content_attributes: { 'items' => [{ 'name' => 'nome', 'label' => 'Nome', 'type' => 'text' }],
                                             'flow_id' => flow.id })
    end

    before do
      create(:flow_run, flow: flow, account: account, conversation: conversation, contact: contact,
                        current_node_id: 'wfr', wait_until: nil, status: :waiting)
      enable_flows_engine!
    end

    it 'creates one incoming message with the submitted values as content' do
      expect do
        submit_form(form_message, [{ name: 'nome', value: 'Walisson' }, { name: 'cargo', value: 'Dev' }])
      end.to change { conversation.messages.incoming.count }.from(0).to(1)

      reply = conversation.messages.incoming.last
      expect(reply.content).to eq("nome: Walisson\ncargo: Dev")
      # Formulário não é escolha de opção: sem selected_option, o wait_for_reply casa pelo conteúdo.
      expect(reply.content_attributes['selected_option']).to be_nil
    end
  end

  describe 'with the flows engine OFF (nada muda)' do
    let(:flow) { wait_for_reply_flow }
    let!(:message) { interactive_message(flow) }
    let!(:run) do
      create(:flow_run, flow: flow, account: account, conversation: conversation, contact: contact,
                        current_node_id: 'wfr', wait_until: nil, status: :waiting)
    end

    it 'records submitted_values exactly as before and creates NO message at all' do
      expect(account.flows_engine_enabled?).to be(false)

      expect { click_option(message, title: 'Sim', value: 'yes') }
        .not_to(change { conversation.messages.count })

      expect(response).to have_http_status(:success)
      expect(message.reload.content_attributes['submitted_values']).to eq([{ 'title' => 'Sim', 'value' => 'yes' }])
      expect(run.reload).to be_waiting
      expect(conversation.reload.label_list).to be_empty
    end
  end

  describe 'content types that are NOT structured replies' do
    before { enable_flows_engine! }

    it 'does not echo an incoming message for input_email' do
      email_message = create(:message, account: account, inbox: web_widget.inbox, conversation: conversation,
                                       message_type: :outgoing, content_type: 'input_email')

      expect do
        clear_enqueued_jobs
        put api_v1_widget_message_url(email_message.id),
            params: { website_token: web_widget.website_token, contact: { email: 'lead@example.com' } },
            headers: { 'X-Auth-Token' => token },
            as: :json
        perform_enqueued_jobs(only: EventDispatcherJob)
      end.not_to(change { conversation.messages.incoming.count })

      expect(response).to have_http_status(:success)
      expect(email_message.reload.submitted_email).to eq('lead@example.com')
    end
  end
end
