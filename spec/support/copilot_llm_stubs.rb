# Stubs do provedor de LLM para os specs do copiloto.
#
# Regra: spec de copiloto NAO bate na OpenAI. Aqui o RubyLLM inteiro e trocado
# por dublês — inclusive o caminho de streaming, que entrega os chunks pelo bloco
# exatamente como o provedor entregaria.
module CopilotLlmStubs
  def stub_copilot_llm(chunks: ['ok'], error: nil, account: nil)
    context = instance_double(RubyLLM::Context, config: RubyLLM::Configuration.new)
    chat = instance_double(RubyLLM::Chat)

    stub_llm_context(context, account)
    allow(context).to receive(:chat).and_return(chat)
    [:with_temperature, :with_instructions, :add_message].each do |message|
      allow(chat).to receive(message).and_return(chat)
    end
    stub_llm_answer(chat, chunks, error)

    { context: context, chat: chat }
  end

  # Eventos SSE ja parseados: [['token', {'delta' => 'oi'}], ...]
  def sse_events(payload)
    payload.scan(/event: (\w+)\ndata: (.*)\n\n/).map { |name, data| [name, JSON.parse(data)] }
  end

  def sse_deltas(payload)
    sse_events(payload).filter_map { |name, data| data['delta'] if name == 'token' }
  end

  private

  def stub_llm_context(context, account)
    if account
      allow(Llm::Config).to receive(:context_for_account).with(account: account).and_return(context)
    else
      allow(Llm::Config).to receive(:context_for_account).and_return(context)
    end
  end

  def stub_llm_answer(chat, chunks, error)
    return allow(chat).to receive(:ask).and_raise(error) if error

    allow(chat).to receive(:ask) do |_content, &block|
      chunks.each { |chunk| block&.call(instance_double(RubyLLM::Chunk, content: chunk)) }
      instance_double(RubyLLM::Message, content: chunks.join)
    end
  end
end

RSpec.configure do |config|
  config.include CopilotLlmStubs
end
