require 'rails_helper'

# CHAT-168: com faq_lookup/search_knowledge fora da lista de um agente, o molde compartilhado ainda
# pode levar o modelo a chamá-las. Sem a guarda, o ruby_llm executa `nil` e o turno inteiro morre.
RSpec.describe Llm::MissingToolGuard do
  let(:chat) do
    RubyLLM::Chat.allocate.tap { |c| c.instance_variable_set(:@tools, {}) }
  end
  let(:tool_call) { Struct.new(:name, :arguments).new('captain--tools--faq_lookup', { 'query' => 'x' }) }

  it 'está instalada no RubyLLM::Chat' do
    expect(RubyLLM::Chat.ancestors).to include(described_class)
  end

  it 'devolve ao modelo que a ferramenta não existe, em vez de levantar erro' do
    resultado = chat.send(:execute_tool, tool_call)

    expect(resultado).to include('captain--tools--faq_lookup')
  end

  it 'executa normalmente a ferramenta que existe' do
    ferramenta = instance_double(RubyLLM::Tool, call: 'ok')
    chat.instance_variable_set(:@tools, { 'captain--tools--faq_lookup': ferramenta })

    expect(chat.send(:execute_tool, tool_call)).to eq('ok')
  end
end
