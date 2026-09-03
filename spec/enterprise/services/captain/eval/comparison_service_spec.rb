require 'rails_helper'

# 6.02 — "a IA melhorou?" vira número: quantos casos REGREDIRAM entre duas execuções.
RSpec.describe Captain::Eval::ComparisonService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:caso_a) { create(:captain_eval_case, captain_assistant: assistant, account: account, titulo: 'horário') }
  let(:caso_b) { create(:captain_eval_case, captain_assistant: assistant, account: account, titulo: 'desconto') }

  def execucao(fingerprint: 'abc123', resultados: {})
    run = Captain::EvalRun.create!(account_id: account.id, captain_assistant_id: assistant.id, status: 'concluida',
                                   prompt_fingerprint: fingerprint, casos_total: resultados.size,
                                   casos_ok: resultados.values.count(true), casos_falha: resultados.values.count(false))
    resultados.each do |eval_case, passou|
      Captain::EvalCaseResult.create!(account_id: account.id, eval_run_id: run.id, eval_case_id: eval_case.id,
                                      passou: passou, resposta: 'x')
    end
    run
  end

  it 'names the case that regressed' do
    antes = execucao(resultados: { caso_a => true, caso_b => true })
    depois = execucao(fingerprint: 'def456', resultados: { caso_a => false, caso_b => true })

    resultado = described_class.new(base: antes, comparada: depois).perform

    expect(resultado[:regrediram].map { |l| l[:titulo] }).to eq(['horário'])
    expect(resultado[:corrigiram]).to be_empty
  end

  it 'names the case that was fixed' do
    antes = execucao(resultados: { caso_a => false })
    depois = execucao(fingerprint: 'def456', resultados: { caso_a => true })

    resultado = described_class.new(base: antes, comparada: depois).perform

    expect(resultado[:corrigiram].map { |l| l[:titulo] }).to eq(['horário'])
    expect(resultado[:regrediram]).to be_empty
  end

  it 'puts the two verdicts of the same case side by side' do
    antes = execucao(resultados: { caso_a => true })
    depois = execucao(fingerprint: 'def456', resultados: { caso_a => false })

    linha = described_class.new(base: antes, comparada: depois).perform[:casos].first

    expect(linha[:antes]).to be(true)
    expect(linha[:depois]).to be(false)
    expect(linha[:situacao]).to eq('regrediu')
  end

  it 'says when the two runs used the SAME prompt — senão a comparação mede outra coisa' do
    antes = execucao(resultados: { caso_a => true })
    mesmo = execucao(resultados: { caso_a => false })
    outro = execucao(fingerprint: 'zzz', resultados: { caso_a => false })

    expect(described_class.new(base: antes, comparada: mesmo).perform[:mesmo_prompt]).to be(true)
    expect(described_class.new(base: antes, comparada: outro).perform[:mesmo_prompt]).to be(false)
  end

  # Caso criado depois da primeira execução não é regressão — não havia o que regredir.
  it 'does not invent a regression for a case that only exists in one run' do
    antes = execucao(resultados: { caso_a => true })
    depois = execucao(fingerprint: 'def456', resultados: { caso_a => true, caso_b => false })

    resultado = described_class.new(base: antes, comparada: depois).perform

    expect(resultado[:regrediram]).to be_empty
    expect(resultado[:casos].find { |l| l[:titulo] == 'desconto' }[:situacao]).to eq('so_em_uma')
  end
end
