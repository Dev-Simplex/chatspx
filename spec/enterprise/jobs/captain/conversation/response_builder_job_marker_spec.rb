require 'rails_helper'

# CHAT-208: o historico mostra cada carrossel como "[carrossel de fotos do imovel X enviado]" e o
# agente copia o rotulo ANTES da fala dele. A trava de marcador so olhava a resposta inteira; com
# texto junto, o humanizer quebrava em baloes e o marcador chegava sozinho ao cliente (conv 44248).
RSpec.describe Captain::Conversation::ResponseBuilderJob, type: :job do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:inbox) { create(:inbox, account: account, pending_status_enabled: true) }
  let(:assistant) { create(:captain_assistant, account: account, behavior: {}) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) do
    create(:conversation, inbox: inbox, account: account, contact: contact, status: :pending,
                          assignee_agent_bot: assistant.mirror_agent_bot)
  end
  let(:runner) { instance_double(Captain::Assistant::AgentRunnerService) }
  let(:handoff) { instance_double(Captain::Conversation::HumanHandoffService, perform: true) }
  let(:fala) { 'Enviei! Dá pra ver que é bem ampla 😊' }

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    create(:message, conversation: conversation, content: 'Sim', message_type: :incoming)

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

  it 'tira a linha de marcador e manda so a fala' do
    responde("[carrossel de fotos do imóvel 5196 enviado]\n\n#{fala}")

    described_class.perform_now(conversation, assistant)

    expect(runner).to have_received(:generate_response).once
    expect(enviadas).to eq([fala])
    expect(Captain::AssistantLog.where(conversation: conversation, event_type: 'unknown_marker').pluck(:payload))
      .to eq([{ 'content' => '[carrossel de fotos do imóvel 5196 enviado]', 'acao' => 'removido' }])
  end

  it 'tira marcador no meio de varios paragrafos sem juntar as falas' do
    responde("Achei mais uma!\n\n[carrossel de fotos do imóvel 1699 enviado]\n\nQuer agendar a visita?")

    described_class.perform_now(conversation, assistant)

    expect(enviadas).to eq(["Achei mais uma!\n\nQuer agendar a visita?"])
  end

  it 'resposta que e SO marcador continua indo para a regeneracao' do
    responde('[carrossel de fotos do imóvel 5196 enviado]', fala)

    described_class.perform_now(conversation, assistant)

    expect(runner).to have_received(:generate_response).twice
    expect(enviadas).to eq([fala])
  end

  it '[IGNORAR] sozinho segue sendo silencio' do
    responde('[IGNORAR]')

    described_class.perform_now(conversation, assistant)

    expect(enviadas).to be_empty
  end

  it 'colchete dentro da frase nao e marcador' do
    texto = 'O código dela é [5196], quer ver as fotos?'
    responde(texto)

    described_class.perform_now(conversation, assistant)

    expect(enviadas).to eq([texto])
  end
end
