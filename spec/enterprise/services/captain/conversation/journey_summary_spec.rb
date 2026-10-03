require 'rails_helper'

RSpec.describe Captain::Conversation::JourneySummary do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account, name: 'Equipe') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team) }
  let(:atendente) { create(:user, account: account, display_name: 'Atendente') }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_context) { instance_double(RubyLLM::Context, chat: mock_chat) }
  let(:resposta) { instance_double(RubyLLM::Message, content: 'Pedido: resumo gerado', input_tokens: 10, output_tokens: 5) }
  let!(:pedido) { create(:message, conversation: conversation, message_type: :incoming, content: 'preciso de ajuda') }
  let!(:fala_humana) { create(:message, conversation: conversation, message_type: :outgoing, sender: atendente, content: 'resolvido') }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(Llm::Config).to receive(:with_api_key).and_yield(mock_context)
    allow(mock_chat).to receive(:with_instructions)
    allow(mock_chat).to receive(:ask).and_return(resposta)
  end

  it 'returns the generated summary' do
    expect(described_class.for(conversation)).to eq('Pedido: resumo gerado')
  end

  it 'sends a transcript that marks who said each thing' do
    enviado = nil
    allow(mock_chat).to receive(:ask) { |conteudo| (enviado = conteudo) && resposta }

    described_class.for(conversation)

    expect(enviado).to include('contato: preciso de ajuda')
    expect(enviado).to include('atendente Atendente (time equipe): resolvido')
  end

  it 'only summarizes messages up to the cut' do
    create(:message, conversation: conversation, message_type: :incoming, content: 'mensagem nova')
    enviado = nil
    allow(mock_chat).to receive(:ask) { |conteudo| (enviado = conteudo) && resposta }

    described_class.for(conversation, ate: fala_humana.id)

    expect(enviado).not_to include('mensagem nova')
  end

  it 'reuses the summary of the same stretch instead of calling the model again' do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

    2.times { described_class.for(conversation, ate: fala_humana.id) }

    expect(mock_chat).to have_received(:ask).once
  end

  it 'returns nil when the model call fails' do
    allow(mock_chat).to receive(:ask).and_raise(StandardError, 'boom')

    expect(described_class.for(conversation)).to be_nil
  end

  it 'does not consume the Captain response quota' do
    expect { described_class.for(conversation) }.not_to(change { account.reload.usage_limits[:captain][:responses][:consumed] })
  end

  it 'returns nil without calling the model when there is nothing to summarize' do
    expect(described_class.for(conversation, ate: pedido.id - 1)).to be_nil
    expect(mock_chat).not_to have_received(:ask)
  end
end
