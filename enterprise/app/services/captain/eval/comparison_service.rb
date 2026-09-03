# Duas execuções, caso a caso (bloco 6.02).
#
# É o que transforma "a IA melhorou?" em número: quantos casos REGREDIRAM (passavam,
# pararam de passar), quantos foram corrigidos, e quais ficaram iguais. A pergunta que
# o cliente faz antes de publicar uma mudança de prompt é exatamente esta.
class Captain::Eval::ComparisonService
  def initialize(base:, comparada:)
    @base = base
    @comparada = comparada
  end

  def perform
    {
      base: resumo(@base),
      comparada: resumo(@comparada),
      mesmo_prompt: @base.prompt_fingerprint.present? && @base.prompt_fingerprint == @comparada.prompt_fingerprint,
      regrediram: linhas.select { |l| l[:situacao] == 'regrediu' },
      corrigiram: linhas.select { |l| l[:situacao] == 'corrigiu' },
      casos: linhas
    }
  end

  private

  # Um caso só aparece como "regrediu"/"corrigiu" quando existe nas DUAS execuções.
  # Caso novo ou apagado entre elas vira 'so_em_uma' — comparar o que não tem par seria
  # inventar uma regressão que ninguém causou.
  def linhas
    @linhas ||= (por_caso(@base).keys | por_caso(@comparada).keys).map do |case_id|
      antes = por_caso(@base)[case_id]
      depois = por_caso(@comparada)[case_id]
      {
        eval_case_id: case_id,
        titulo: (antes || depois).eval_case.titulo,
        antes: antes&.passou,
        depois: depois&.passou,
        situacao: situacao(antes, depois),
        findings_depois: depois&.findings || []
      }
    end
  end

  def situacao(antes, depois)
    return 'so_em_uma' if antes.nil? || depois.nil?

    case [antes.passou, depois.passou]
    when [true, false] then 'regrediu'
    when [false, true] then 'corrigiu'
    when [true, true] then 'segue_passando'
    else 'segue_falhando'
    end
  end

  def por_caso(run)
    @por_caso ||= {}
    @por_caso[run.id] ||= run.results.includes(:eval_case).index_by(&:eval_case_id)
  end

  def resumo(run)
    {
      id: run.id, criada_em: run.created_at, prompt_fingerprint: run.prompt_fingerprint,
      casos_total: run.casos_total, casos_ok: run.casos_ok, casos_falha: run.casos_falha,
      aprovacao: run.aprovacao, dry_run: run.dry_run
    }
  end
end
