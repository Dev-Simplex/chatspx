require 'rails_helper'

# CHAT-159: o cliente pediu o WhatsApp e a IA respondeu, duas vezes, um telefone que não existia
# em lugar nenhum. A IA não escreve telefone em texto (o da empresa sai pelo card de contato);
# só passa número que o cliente ou alguém da equipe escreveu na conversa. Resposta com número sem
# fonte volta para a IA refazer, com teto de tentativas.
RSpec.describe Captain::Conversation::ResponseBuilderJob, type: :job do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:inbox) { create(:inbox, account: account, pending_status_enabled: true) }
  let(:behavior) { {} }
  let(:assistant) { create(:captain_assistant, account: account, behavior: behavior) }
  let(:contact) { create(:contact, account: account, phone_number: '+5566999990000') }
  let(:conversation) do
    create(:conversation, inbox: inbox, account: account, contact: contact, status: :pending,
                          assignee_agent_bot: assistant.mirror_agent_bot)
  end
  let(:runner) { instance_double(Captain::Assistant::AgentRunnerService) }
  let(:handoff) { instance_double(Captain::Conversation::HumanHandoffService, perform: true) }
  let(:inventado) { 'Nosso WhatsApp é (66) 3531-2284, pode chamar!' }
  let(:correta) { 'Te mandei o contato da unidade aqui, é só tocar para chamar.' }

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

  def logs
    Captain::AssistantLog.where(conversation: conversation, event_type: 'phone_unsourced').order(:id).pluck(:payload)
  end

  context 'with the guard on by default' do
    it 'não envia o telefone inventado e devolve para a IA refazer' do
      responde(inventado, correta)

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).twice
      expect(enviadas).to eq([correta])
      expect(handoff).not_to have_received(:perform)
      expect(logs).to eq([{ 'numeros' => ['(66) 3531-2284'], 'tentativa' => 1, 'acao' => 'regenerar' }])
    end

    it 'entrega o motivo à IA sem citar o número barrado' do
      historicos = []
      allow(runner).to receive(:generate_response) do |message_history:|
        historicos << message_history
        { 'response' => historicos.size == 1 ? inventado : correta }
      end

      described_class.perform_now(conversation, assistant)

      diretiva = historicos.last.last[:content]
      expect(diretiva).to include('enviar_contato_unidade')
      expect(diretiva).not_to match(/\d{4}/)
    end

    it 'barra o telefone da unidade escrito em texto: contato da empresa vai por card' do
      responde('Chama a gente no 66 35317222 que o time te atende.', correta)

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).twice
      expect(enviadas).to eq([correta])
    end

    it 'barra telefone que só veio de retorno de ferramenta' do
      Captain::ToolCall.create!(account: account, conversation: conversation, tool_name: 'buscar_imovel',
                                result_preview: 'Corretor responsável: (66) 99123-4567')
      responde('O corretor responde no (66) 99123-4567.', correta)

      described_class.perform_now(conversation, assistant)

      expect(enviadas).to eq([correta])
    end

    it 'deixa passar o número que o próprio cliente escreveu, mesmo formatado de outro jeito' do
      create(:message, conversation: conversation, content: 'Me liga no 66 98888-1234', message_type: :incoming)
      responde('Combinado, vamos te ligar no (66) 9 8888-1234.')

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).once
      expect(enviadas).to eq(['Combinado, vamos te ligar no (66) 9 8888-1234.'])
      expect(logs).to be_empty
    end

    it 'deixa passar o número que um humano da equipe escreveu' do
      create(:message, conversation: conversation, content: 'Pode falar com o plantão no (66) 99777-5555',
                       message_type: :outgoing, sender: create(:user, account: account))
      # A fala humana tira a IA da conversa; o caso é a reentrada, com a conversa devolvida ao bot.
      conversation.update!(status: :pending, assignee_agent_bot: assistant.mirror_agent_bot)
      create(:message, conversation: conversation, content: 'Qual é mesmo o número?', message_type: :incoming)
      responde('Isso, o plantão atende no (66) 99777-5555.')

      described_class.perform_now(conversation, assistant)

      expect(enviadas).to include('Isso, o plantão atende no (66) 99777-5555.')
    end

    it 'não legitima o número que a própria IA já tinha escrito antes' do
      create(:message, conversation: conversation, content: inventado, message_type: :outgoing, sender: assistant)
      responde(inventado, correta)

      described_class.perform_now(conversation, assistant)

      expect(enviadas).to eq([inventado, correta]) # a antiga e a corrigida
    end

    it 'no teto de 3 tentativas tira a frase com o número e envia o resto, se ainda for mensagem' do
      insistente = "Claro! Nosso WhatsApp é (66) 3531-2284.\nQualquer dúvida sobre o imóvel, estou por aqui."
      responde(inventado, inventado, insistente)

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).exactly(3).times
      expect(enviadas).to eq(["Claro!\nQualquer dúvida sobre o imóvel, estou por aqui."])
      expect(handoff).not_to have_received(:perform)
      expect(logs.map { |l| [l['tentativa'], l['acao']] }).to eq([[1, 'regenerar'], [2, 'regenerar'], [3, 'removido']])
    end

    it 'no teto de 3 tentativas não envia nada e chama gente quando sem o número não sobra mensagem' do
      responde(inventado, inventado, inventado)

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).exactly(3).times
      expect(enviadas).to be_empty
      expect(handoff).to have_received(:perform)
      expect(logs.last).to include('tentativa' => 3, 'acao' => 'bloqueado')
    end

    it 'não confunde preço, CEP, CPF e código com telefone' do
      texto = 'A casa 6573 sai por R$ 520.000,00, CEP 78550-000, contrato no CPF 123.456.789-09.'
      responde(texto)

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).once
      expect(enviadas).to eq([texto])
      expect(logs).to be_empty
    end
  end

  context 'when the assistant turns the guard off' do
    let(:behavior) { { 'guards' => { 'telefone_sem_fonte' => false } } }

    it 'envia como hoje' do
      responde(inventado)

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).once
      expect(enviadas).to eq([inventado])
    end
  end

  context 'when the account turns the guard off' do
    let(:account) do
      create(:account, custom_attributes: { plan_name: 'startups', captain_guard_telefone_sem_fonte: false })
    end

    it 'envia como hoje' do
      responde(inventado)

      described_class.perform_now(conversation, assistant)

      expect(runner).to have_received(:generate_response).once
      expect(enviadas).to eq([inventado])
    end
  end
end
