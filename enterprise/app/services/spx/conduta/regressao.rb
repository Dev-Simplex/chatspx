# Motor da regressão de conduta (ver lib/tasks/spx_conduta.rake).
#
# Cada rodada: monta o histórico do cenário numa conversa de rascunho, chama o MESMO caminho
# que o ResponseBuilderJob usa em produção (collect_previous_messages -> AgentRunnerService#
# generate_response) e reverte. Montar o histórico à mão em vez de usar o do job já produziu
# leitura errada antes — o job aplica tratamento de mídia e recorte de episódio que a sonda
# improvisada não aplicava, e a conclusão saiu invertida.
class Spx::Conduta::Regressao
  def initialize(conversation:, rodadas: 6)
    @conversation = conversation
    @rodadas = rodadas
  end

  # Devolve quantos cenários ficaram ABAIXO do piso. Emite cada linha pelo bloco.
  def executar(cenarios)
    falhas = 0
    ActiveRecord::Base.transaction do
      cenarios.each do |cenario|
        resultado = rodar(cenario)
        falhas += 1 unless resultado[:ok]
        yield(formatar(cenario, resultado)) if block_given?
      end
      raise ActiveRecord::Rollback
    end
    falhas
  end

  private

  def rodar(cenario)
    assistant = Captain::Assistant.find(cenario.fetch('assistente'))
    respostas = Array.new(@rodadas) { uma_rodada(assistant, cenario.fetch('turnos')) }
    acertos = respostas.count { |r| aprovado?(r, cenario) }
    piso = cenario.fetch('piso', @rodadas)
    { acertos: acertos, total: @rodadas, piso: piso, ok: acertos >= piso, respostas: respostas }
  end

  # A rodada inteira roda numa transação aninhada revertida: as mensagens de rascunho não
  # sobrevivem, e uma rodada não contamina a seguinte com o histórico da anterior.
  def uma_rodada(assistant, turnos)
    texto = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      @conversation.messages.destroy_all
      turnos.each { |t| criar_mensagem(assistant, t) }
      texto = gerar(assistant)
      raise ActiveRecord::Rollback
    end
    texto.to_s
  end

  def criar_mensagem(assistant, turno)
    entrada = turno.fetch('de') == 'cliente'
    @conversation.messages.create!(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      content: turno.fetch('texto'),
      message_type: entrada ? :incoming : :outgoing,
      sender: entrada ? @conversation.contact : assistant
    )
  end

  def gerar(assistant)
    job = Captain::Conversation::ResponseBuilderJob.new
    job.instance_variable_set(:@conversation, @conversation)
    job.instance_variable_set(:@assistant, assistant)
    historico = job.send(:collect_previous_messages)
    resposta = Captain::Assistant::AgentRunnerService
               .new(assistant: assistant, conversation: @conversation)
               .generate_response(message_history: historico)
    resposta.is_a?(Hash) ? resposta['response'] : resposta
  end

  # `espera` e `proibe` são listas de regex. Uma resposta passa quando casa TODAS as de
  # `espera` e NENHUMA de `proibe`. Regex e não substring de propósito: o cenário precisa
  # distinguir vizinhos ("que dia você passa na loja" não é a mesma falha que "que dia você
  # quer conhecer o imóvel"), e detector grosseiro já fez descartar mudança que funcionava.
  def aprovado?(texto, cenario)
    Array(cenario['espera']).all? { |p| texto.match?(Regexp.new(p, Regexp::IGNORECASE)) } &&
      Array(cenario['proibe']).none? { |p| texto.match?(Regexp.new(p, Regexp::IGNORECASE)) }
  end

  def formatar(cenario, r)
    marca = r[:ok] ? '✅' : '❌'
    linha = "#{marca} #{cenario.fetch('nome').ljust(44)} #{r[:acertos]}/#{r[:total]} (piso #{r[:piso]})"
    return linha if r[:ok]

    reprovadas = r[:respostas].reject { |t| aprovado?(t, cenario) }.first(2)
    ([linha] + reprovadas.map { |t| "     ↳ #{t.to_s.gsub(/\s+/, ' ')[0, 200]}" }).join("\n")
  end
end
