# Executa o CONJUNTO de casos e grava a execução (bloco 6.02).
#
# ─── POR QUE `dry_run` NÃO TEM O OUTRO LADO ─────────────────────────────────────────
# O aceite diz: "nenhum caso de cliente é executado contra IA de produção sem dry_run".
# A forma mais barata de garantir isso não é uma flag que alguém pode desligar — é NÃO
# CONSTRUIR o outro modo. Aqui a execução sempre roda fora da conversa do cliente
# (Captain::Eval::AssistantResponder: `conversation: nil`, nenhuma conversa e nenhuma
# mensagem gravadas, nada entregue a visitante), e pedir `dry_run: false` levanta
# ArgumentError.
#
# `dry_run` é sobre ENTREGA, não sobre custo: a chamada ao modelo acontece de verdade e
# é debitada de verdade (ver #debitar_resposta) — é o que faz o número exibido antes de
# rodar valer alguma coisa.
#
# A coluna `dry_run` existe mesmo assim, e não é decoração: ela registra, em cada linha
# do histórico, sob que regime aquele número foi obtido. Se um dia o modo ao vivo for
# construído (outro bloco), o histórico antigo continua legível.
class Captain::Eval::RunService
  def initialize(assistant:, responder: nil, dry_run: true)
    raise ArgumentError, 'execução fora de dry_run não existe neste bloco' unless dry_run

    @assistant = assistant
    @responder = responder
  end

  # Cria a execução e roda na hora (usado pelo job e pelos testes).
  def perform
    run = criar_execucao
    executar(run)
    run
  end

  # Cria a execução PENDENTE e joga o trabalho para o job — o cliente clica e a tela
  # não fica pendurada esperando N chamadas de modelo.
  def enqueue
    run = criar_execucao(status: 'pendente')
    Captain::Eval::RunJob.perform_later(run)
    run
  end

  # Roda uma execução já criada.
  def executar(run)
    ok = 0
    run.update!(status: 'rodando', iniciado_em: run.iniciado_em || Time.current)
    casos.each do |eval_case|
      veredito = Captain::Eval::CaseRunnerService.new(
        assistant: @assistant, eval_case: eval_case, responder: @responder
      ).perform
      ok += 1 if veredito[:passou]
      gravar(run, eval_case, veredito)
      debitar_resposta
    end
    run.update!(status: 'concluida', casos_ok: ok, casos_falha: casos.size - ok, concluido_em: Time.current)
  rescue StandardError => e
    run.update(status: 'erro', concluido_em: Time.current)
    Rails.logger.error("[eval-run] execução #{run.id} falhou: #{e.class} #{e.message}")
    raise
  end

  private

  def criar_execucao(status: 'rodando')
    identidade = Captain::Eval::PromptIdentityService.new(assistant: @assistant)
    Captain::EvalRun.create!(
      account_id: @assistant.account_id,
      captain_assistant_id: @assistant.id,
      status: status,
      dry_run: true,
      prompt_fingerprint: identidade.fingerprint,
      prompt_snapshot: identidade.snapshot,
      modelo: @assistant.config['model'].presence || Llm::Models.default_model_for('assistant'),
      casos_total: casos.size,
      custo_estimado: Captain::Eval::CostEstimatorService.new(assistant: @assistant, cases: casos).perform,
      iniciado_em: Time.current
    )
  end

  # A UNIDADE DO CUSTO. A tela mostra, antes de rodar, "N casos · N respostas" e avisa
  # quando N passa do saldo. Enquanto a execução não debitava nada, esse número era
  # decoração: o aviso de saldo não avisava de nada e N chamadas ao modelo saíam de
  # graça. Um caso = uma resposta da IA, a mesma unidade em que o produto cobra — e é
  # ela que o `CostEstimatorService` projeta.
  #
  # Debita por caso EXECUTADO, não por caso aprovado: o modelo foi chamado do mesmo
  # jeito. Depois da execução, `saldo[:consumido]` da estimativa anda exatamente o que
  # a estimativa tinha anunciado.
  def debitar_resposta
    @assistant.account.increment_response_usage
  end

  def gravar(run, eval_case, veredito)
    Captain::EvalCaseResult.create!(
      account_id: run.account_id,
      eval_run_id: run.id,
      eval_case_id: eval_case.id,
      passou: veredito[:passou],
      resposta: veredito[:resposta],
      findings: veredito[:findings],
      ferramentas: veredito[:ferramentas],
      duracao_ms: veredito[:duracao_ms]
    )
  end

  def casos
    @casos ||= @assistant.eval_cases.ativos.ordenados.to_a
  end
end
