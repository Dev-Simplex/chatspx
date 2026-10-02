# Chamada a uma ferramenta que o agente não tem vira resposta ao modelo, não erro (CHAT-168).
#
# O ruby_llm executa `tools[nome]` sem conferir: nome fora da lista vira `nil.call` e o turno
# inteiro morre — o runner devolve saída vazia e a IA fica calada. Isso passou a importar quando
# faq_lookup/search_knowledge deixaram de entrar em agente sem conteúdo: o molde compartilhado
# ainda pode levar o modelo a chamá-las.
module Llm::MissingToolGuard
  def self.install!
    return unless defined?(RubyLLM::Chat)
    return if RubyLLM::Chat.include?(self)

    RubyLLM::Chat.prepend(self)
  end

  private

  def execute_tool(tool_call)
    return "A ferramenta #{tool_call.name} não está disponível para este agente. Siga sem ela." unless tools[tool_call.name.to_sym]

    super
  end
end
