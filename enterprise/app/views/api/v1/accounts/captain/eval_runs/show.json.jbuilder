json.data do
  json.partial! 'eval_run', eval_run: @eval_run
  json.prompt_snapshot @eval_run.prompt_snapshot
  json.resultados do
    json.array! @results do |resultado|
      json.eval_case_id resultado.eval_case_id
      json.titulo resultado.eval_case.titulo
      json.passou resultado.passou
      json.resposta resultado.resposta
      json.findings resultado.findings
      json.ferramentas resultado.ferramentas
      json.duracao_ms resultado.duracao_ms
    end
  end
end
