require 'rails_helper'

# Nós de IA da Fase 3.2 (ai_classify / ai_generate). São ENTERPRISE: dependem do Captain
# (assistants + LLM), por isso vivem sob spec/enterprise/.
#
# INVARIANTE DE SEGURANÇA (incidente Clara): a IA REAL NUNCA é chamada aqui. Mockamos a CLASSE
# do serviço Captain real reusado — Captain::Llm::AssistantChatService — de modo que `.new` nem
# instancia o serviço; nenhum request a LLM/assistente real acontece. Cada exemplo define o
# retorno `generate_response`. Nos caminhos de guarda (config inválida) exigimos que
# `generate_response` NUNCA seja recebido — prova de que um nó mal configurado não queima crédito.
RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:captain_service) { instance_double(Captain::Llm::AssistantChatService) }

  after { Current.reset }

  def action(name, params)
    { 'type' => 'action', 'action_name' => name, 'action_params' => params }
  end

  before do
    create(:message, conversation: conversation, message_type: :incoming, content: 'Meu pedido está atrasado!')
    # `.new` devolve o double: o serviço Captain REAL nunca é construído (⇒ nunca chama LLM).
    allow(Captain::Llm::AssistantChatService).to receive(:new).and_return(captain_service)
  end

  describe 'whitelist (enterprise)' do
    it 'accepts ai_classify and ai_generate as action nodes' do
      nodes = [
        { 'id' => 'n1', 'type' => 'action', 'action_name' => 'ai_classify' },
        { 'id' => 'n2', 'type' => 'action', 'action_name' => 'ai_generate' }
      ]
      candidate = build(:flow, account: account, definition: { 'nodes' => nodes, 'edges' => [] })
      expect(candidate).to be_valid
    end
  end

  describe '#ai_classify' do
    let(:params) do
      [{ 'assistant_id' => assistant.id, 'prompt' => 'Classifique a intenção do cliente',
         'categories' => %w[elogio reclamação dúvida], 'key' => 'triagem_ia' }]
    end

    it 'stores the MOCKed category on the conversation custom_attributes (feeds a router)' do
      allow(captain_service).to receive(:generate_response).and_return({ 'response' => 'reclamação' })
      described_class.new(flow: flow, conversation: conversation).execute(action('ai_classify', params))
      expect(conversation.reload.custom_attributes['triagem_ia']).to eq('reclamação')
    end

    it 'normalizes a verbose answer to one of the canonical categories (substring, case-insensitive)' do
      allow(captain_service).to receive(:generate_response).and_return({ 'response' => 'Isso parece uma RECLAMAÇÃO.' })
      described_class.new(flow: flow, conversation: conversation).execute(action('ai_classify', params))
      expect(conversation.reload.custom_attributes['triagem_ia']).to eq('reclamação')
    end

    it 'writes on the contact when target is contact' do
      allow(captain_service).to receive(:generate_response).and_return({ 'response' => 'elogio' })
      contact_params = [params[0].merge('target' => 'contact')]
      described_class.new(flow: flow, conversation: conversation).execute(action('ai_classify', contact_params))
      expect(conversation.contact.reload.custom_attributes['triagem_ia']).to eq('elogio')
    end

    it 'writes to additional_attributes when store is additional' do
      allow(captain_service).to receive(:generate_response).and_return({ 'response' => 'dúvida' })
      add_params = [params[0].merge('store' => 'additional')]
      described_class.new(flow: flow, conversation: conversation).execute(action('ai_classify', add_params))
      expect(conversation.reload.additional_attributes['triagem_ia']).to eq('dúvida')
    end

    it 'is a cost-safe no-op (never calls the LLM) when categories are missing' do
      expect(captain_service).not_to receive(:generate_response)
      bad = [{ 'assistant_id' => assistant.id, 'key' => 'triagem_ia' }]
      described_class.new(flow: flow, conversation: conversation).execute(action('ai_classify', bad))
      expect(conversation.reload.custom_attributes).to eq({})
    end

    it 'is a no-op (never calls the LLM) when the assistant is not in the account' do
      expect(captain_service).not_to receive(:generate_response)
      bad = [{ 'assistant_id' => 0, 'categories' => %w[a b], 'key' => 'triagem_ia' }]
      described_class.new(flow: flow, conversation: conversation).execute(action('ai_classify', bad))
      expect(conversation.reload.custom_attributes).to eq({})
    end
  end

  describe '#ai_generate' do
    let(:params) { [{ 'assistant_id' => assistant.id, 'prompt' => 'Rascunhe uma resposta cordial' }] }

    it 'writes the MOCKed text as an internal private note by default' do
      allow(captain_service).to receive(:generate_response).and_return({ 'response' => 'Olá! Já estamos verificando seu pedido.' })
      service = described_class.new(flow: flow, conversation: conversation)
      expect { service.execute(action('ai_generate', params)) }
        .to change { conversation.reload.messages.where(private: true).count }.by(1)
      expect(conversation.messages.where(private: true).last.content).to eq('Olá! Já estamos verificando seu pedido.')
    end

    it 'stamps the flow_id anti-loop marker on the generated note (the note cannot re-trigger the flow)' do
      allow(captain_service).to receive(:generate_response).and_return({ 'response' => 'rascunho' })
      described_class.new(flow: flow, conversation: conversation).execute(action('ai_generate', params))
      expect(conversation.messages.where(private: true).last.content_attributes['flow_id']).to eq(flow.id)
    end

    it 'writes to a custom attribute when target is attribute' do
      allow(captain_service).to receive(:generate_response).and_return({ 'response' => 'texto gerado' })
      attr_params = [{ 'assistant_id' => assistant.id, 'prompt' => 'x', 'target' => 'attribute', 'key' => 'rascunho_ia' }]
      described_class.new(flow: flow, conversation: conversation).execute(action('ai_generate', attr_params))
      expect(conversation.reload.custom_attributes['rascunho_ia']).to eq('texto gerado')
    end

    it 'accepts a plain-string LLM response as well (fallback parse path)' do
      allow(captain_service).to receive(:generate_response).and_return('resposta em texto puro')
      described_class.new(flow: flow, conversation: conversation).execute(action('ai_generate', params))
      expect(conversation.messages.where(private: true).last.content).to eq('resposta em texto puro')
    end

    it 'is a cost-safe no-op (never calls the LLM) when the prompt is blank' do
      expect(captain_service).not_to receive(:generate_response)
      bad = [{ 'assistant_id' => assistant.id, 'prompt' => '' }]
      described_class.new(flow: flow, conversation: conversation).execute(action('ai_generate', bad))
      expect(conversation.reload.messages.where(private: true)).to be_empty
    end
  end
end
