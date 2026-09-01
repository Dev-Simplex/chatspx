require 'rails_helper'

RSpec.describe Copilot::ThreadStreamService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }

  let(:chunks) { ['Bom ', 'dia, ', 'agente!'] }
  let(:written) { +'' }
  # Sonda: quando o evento `done` for escrito, olhamos o banco. E assim que se
  # prova que a mensagem foi persistida ANTES do `done`, e nao depois.
  let(:assistant_messages_when_done) { [] }
  let(:io) do
    probe = instance_double(StringIO)
    allow(probe).to receive(:write) do |chunk|
      written << chunk
      assistant_messages_when_done << copilot_thread.copilot_messages.assistant.pluck(:id) if chunk.include?('event: done')
    end
    allow(probe).to receive(:close)
    probe
  end
  let(:sse) { Copilot::SseStream.new(io, heartbeat_interval: nil) }

  before { create(:integrations_hook, :openai, account: account, settings: { api_key: 'test-account-key' }) }

  def run(input: { message: 'Resume a conversa' })
    described_class.new(copilot_thread: copilot_thread, user: user, sse: sse, input: input).call
  end

  describe 'caminho feliz' do
    before { stub_copilot_llm(chunks: chunks, account: account) }

    it 'emite start, tokens e done nessa ordem' do
      run

      expect(sse_events(written).map(&:first)).to eq(%w[start token token token done])
      expect(sse_deltas(written)).to eq(chunks)
    end

    it 'grava a pergunta do agente e a resposta na thread' do
      run

      messages = copilot_thread.copilot_messages.order(created_at: :asc, id: :asc)
      expect(messages.map(&:message_type)).to eq(%w[user assistant])
      expect(messages.last.message['content']).to eq('Bom dia, agente!')
      expect(messages.last.message['finish_reason']).to eq('stop')
    end

    it 'persiste a resposta ANTES de emitir o done' do
      run

      persisted_id = copilot_thread.copilot_messages.assistant.first.id
      expect(assistant_messages_when_done.first).to eq([persisted_id])
      expect(sse_events(written).last.last).to eq({ 'message_id' => persisted_id, 'finish_reason' => 'stop' })
    end

    it 'consome uma resposta da cota da conta' do
      expect { run }.to change { account.reload.usage_limits[:captain][:responses][:consumed] }.by(1)
    end
  end

  describe 'cancelamento no meio da geracao' do
    before do
      stub_copilot_llm(chunks: chunks, account: account)
      call_count = 0
      allow(io).to receive(:write) do |chunk|
        written << chunk
        call_count += 1
        # O agente fecha a aba: a partir da terceira escrita o socket morre.
        raise IOError, 'closed stream' if call_count > 2
      end
    end

    it 'para de gerar e preserva o parcial com finish_reason cancelled' do
      run

      message = copilot_thread.copilot_messages.assistant.first
      expect(message.message['content']).to eq('Bom dia, ')
      expect(message.message['finish_reason']).to eq('cancelled')
    end

    it 'nao emite done para um cliente que ja foi embora' do
      run

      expect(written).not_to include('event: done')
    end
  end

  describe 'parar explicito (botao do agente)' do
    let(:cancellation) { Copilot::StreamCancellation.new(copilot_thread.id) }

    before do
      stub_copilot_llm(chunks: chunks, account: account)
      # Sem o intervalo, o stub emite os tres chunks em menos de 200ms e o
      # cancelamento nunca seria reconsultado.
      stub_const('Copilot::StreamCancellation::CHECK_INTERVAL_SECONDS', 0)
    end

    after { cancellation.clear! }

    it 'nem chama o provedor quando o pedido chegou antes do primeiro token' do
      cancellation.request!

      run

      expect(sse_deltas(written)).to be_empty
      expect(copilot_thread.copilot_messages.assistant.count).to eq(0)
      expect(sse_events(written).last.last['finish_reason']).to eq('cancelled')
    end

    it 'preserva o parcial quando o pedido chega no meio da geracao' do
      allow(io).to receive(:write) do |chunk|
        written << chunk
        cancellation.request! if chunk.include?('"dia, "')
      end

      run

      message = copilot_thread.copilot_messages.assistant.first
      expect(message.message['content']).to eq('Bom dia, ')
      expect(message.message['finish_reason']).to eq('cancelled')
    end

    it 'avisa o agente com done/cancelled, porque ele continua na escuta' do
      cancellation.request!

      run

      expect(sse_events(written).map(&:first)).to eq(%w[start done])
      expect(sse_events(written).last.last['finish_reason']).to eq('cancelled')
    end
  end

  describe 'falha do provedor' do
    before do
      stub_copilot_llm(error: RubyLLM::UnauthorizedError.new(nil, 'Incorrect API key provided: sk-proj-abcdef123456'),
                       account: account)
    end

    it 'emite error com codigo estavel e depois done com finish_reason error' do
      run

      expect(sse_events(written).map(&:first)).to eq(%w[start error done])
      expect(sse_events(written)[1].last).to eq(
        { 'code' => 'unauthorized', 'message' => Copilot::StreamingError::MESSAGES['unauthorized'] }
      )
      expect(sse_events(written).last.last['finish_reason']).to eq('error')
    end

    it 'nao vaza a credencial nem o corpo do provedor para o cliente' do
      run

      expect(written).not_to include('sk-proj')
      expect(written).not_to include('Incorrect API key')
    end

    it 'nao suja o historico com mensagem de erro' do
      run

      expect(copilot_thread.copilot_messages.assistant.count).to eq(0)
      expect(copilot_thread.copilot_messages.user.count).to eq(1)
    end

    it 'nao consome cota quando nada foi gerado' do
      expect { run }.not_to(change { account.reload.usage_limits[:captain][:responses][:consumed] })
    end
  end

  describe 'timeout da geracao' do
    before do
      stub_copilot_llm(chunks: chunks, account: account)
      stub_const('Copilot::StreamingChatService::MAX_DURATION_SECONDS', -1)
    end

    it 'corta a geracao e reporta timeout' do
      run

      expect(sse_events(written).map(&:first)).to eq(%w[start error done])
      expect(sse_events(written)[1].last['code']).to eq('timeout')
    end
  end

  describe 'regenerar' do
    before do
      stub_copilot_llm(chunks: chunks, account: account)
      create(:captain_copilot_message, account: account, copilot_thread: copilot_thread,
                                       message: { content: 'Pergunta antiga' }, message_type: :user)
      create(:captain_copilot_message, account: account, copilot_thread: copilot_thread,
                                       message: { content: 'Resposta ruim' }, message_type: :assistant)
    end

    it 'descarta a resposta anterior e gera outra para a mesma pergunta' do
      described_class.new(copilot_thread: copilot_thread, user: user, sse: sse, input: { regenerate: true }).call

      messages = copilot_thread.copilot_messages.order(created_at: :asc, id: :asc)
      expect(messages.map { |message| message.message['content'] }).to eq(['Pergunta antiga', 'Bom dia, agente!'])
    end
  end

  describe 'historico da thread' do
    before { stub_copilot_llm(chunks: chunks, account: account) }

    it 'fica recuperavel e em ordem estavel depois de varias geracoes' do
      run(input: { message: 'Primeira' })
      run(input: { message: 'Segunda' })

      history = copilot_thread.reload.previous_history
      expect(history.pluck(:role)).to eq(%w[user assistant user assistant])
      expect(history.pluck(:content)).to eq(['Primeira', 'Bom dia, agente!', 'Segunda', 'Bom dia, agente!'])
    end
  end
end
