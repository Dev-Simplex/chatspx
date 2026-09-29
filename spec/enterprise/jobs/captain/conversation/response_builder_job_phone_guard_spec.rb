require 'rails_helper'

# CHAT-159: o cliente pediu o WhatsApp e a IA respondeu, duas vezes, um telefone que não existia
# em lugar nenhum. A guarda de saída barra telefone sem fonte no atendimento.
RSpec.describe Captain::Conversation::ResponseBuilderJob, type: :job do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:inbox) { create(:inbox, account: account, pending_status_enabled: true) }
  let(:guards) { { 'telefone_sem_fonte' => true } }
  let(:assistant) { create(:captain_assistant, account: account, behavior: { 'guards' => guards }) }
  let(:contact) { create(:contact, account: account, phone_number: '+5566999990000') }
  let(:conversation) do
    create(:conversation, inbox: inbox, account: account, contact: contact, status: :pending,
                          assignee_agent_bot: assistant.mirror_agent_bot)
  end
  let(:runner) { instance_double(Captain::Assistant::AgentRunnerService) }
  let(:handoff) { instance_double(Captain::Conversation::HumanHandoffService, perform: true) }
  let(:inventado) { 'Nosso WhatsApp é (66) 3531-2284, pode chamar!' }

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    create(:message, conversation: conversation, content: 'Qual o WhatsApp de vocês?', message_type: :incoming)
    Unit.create!(account_id: account.id, name: 'Matriz', timezone: 'America/Cuiaba', phone: '(66) 3531-7222')

    allow(account).to receive(:feature_enabled?).and_return(false)
    allow(account).to receive(:feature_enabled?).with('captain_integration_v2').and_return(true)
    allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)
    allow(Captain::Conversation::HumanHandoffService).to receive(:new).and_return(handoff)
  end

  def responde(*respostas)
    allow(runner).to receive(:generate_response).and_return(*respostas.map { |r| { 'response' => r } })
  end

  def enviadas
    conversation.messages.outgoing.where(sender_type: 'Captain::Assistant').pluck(:content)
  end

  context 'when the guard is on' do
    it 'barra o telefone inventado, regenera uma vez e, se insistir, não envia e chama gente' do
      responde(inventado, inventado)

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).twice
      expect(enviadas).to be_empty
      expect(handoff).to have_received(:perform)
      log = Captain::AssistantLog.where(conversation: conversation, event_type: 'phone_unsourced').order(:id).last
      expect(log.payload).to include('numeros' => ['(66) 3531-2284'], 'acao' => 'bloqueado')
    end

    it 'envia a resposta regenerada quando ela traz o telefone da unidade' do
      responde(inventado, 'Nosso WhatsApp é (66) 3531-7222.')

      described_class.perform_now(conversation, assistant)

      expect(enviadas).to eq(['Nosso WhatsApp é (66) 3531-7222.'])
      expect(handoff).not_to have_received(:perform)
    end

    it 'deixa passar o telefone da unidade, mesmo escrito de outro jeito' do
      responde('Chama a gente no 66 35317222 que o time te atende.')

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).once
      expect(enviadas).to eq(['Chama a gente no 66 35317222 que o time te atende.'])
    end

    it 'deixa passar o telefone que o próprio cliente mandou' do
      create(:message, conversation: conversation, content: 'Me liga no 66 98888-1234', message_type: :incoming)
      responde('Combinado, vamos te ligar no (66) 9 8888-1234.')

      described_class.perform_now(conversation, assistant)

      expect(enviadas).to eq(['Combinado, vamos te ligar no (66) 9 8888-1234.'])
    end

    it 'deixa passar o telefone do contato, sem o nono dígito' do
      responde('Vamos te chamar no 66 9999-0000.')

      described_class.perform_now(conversation, assistant)

      expect(enviadas).to eq(['Vamos te chamar no 66 9999-0000.'])
    end

    it 'deixa passar o telefone que uma ferramenta devolveu no atendimento' do
      Captain::ToolCall.create!(account: account, conversation: conversation, tool_name: 'buscar_imovel',
                                result_preview: 'Corretor responsável: (66) 99123-4567')
      responde('O corretor responde no (66) 99123-4567.')

      described_class.perform_now(conversation, assistant)

      expect(enviadas).to eq(['O corretor responde no (66) 99123-4567.'])
    end

    it 'não legitima o número que a própria IA já tinha inventado antes' do
      create(:message, conversation: conversation, content: inventado, message_type: :outgoing, sender: assistant)
      responde(inventado, inventado)

      described_class.perform_now(conversation, assistant)

      expect(enviadas).to eq([inventado]) # só a mensagem antiga
      expect(handoff).to have_received(:perform)
    end

    it 'não confunde preço, CEP e código com telefone' do
      texto = 'A casa 6573 sai por R$ 520.000,00, CEP 78550-000.'
      responde(texto)

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).once
      expect(enviadas).to eq([texto])
    end
  end

  context 'when the guard is off' do
    let(:guards) { {} }

    it 'envia como hoje' do
      responde(inventado)

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).once
      expect(enviadas).to eq([inventado])
    end
  end
end
