require 'rails_helper'

# 6.02 — o vocabulário de expectativa, e o juiz que o aplica. Determinístico: nenhuma
# destas asserções chama modelo.
RSpec.describe Captain::Eval::Expectations do
  describe '.validate' do
    it 'accepts the declared vocabulary' do
      expect(described_class.validate({ 'contem' => ['horário'], 'faz_handoff' => true })).to be_empty
    end

    it 'refuses a key nobody can judge' do
      expect(described_class.validate({ 'seja_simpatico' => true }))
        .to eq(['expectativa desconhecida: seja_simpatico'])
    end

    it 'refuses a list-shaped key that is not a list' do
      expect(described_class.validate({ 'contem' => 'horário' })).to eq(['contem precisa ser uma lista'])
    end
  end

  describe '.evaluate' do
    it 'passes when nothing is expected' do
      expect(described_class.evaluate({}, resposta: 'qualquer coisa')).to be_empty
    end

    it 'catches the missing snippet, and names it' do
      findings = described_class.evaluate({ 'contem' => ['das 9h às 18h'] }, resposta: 'Funcionamos de manhã.')

      expect(findings.size).to eq(1)
      expect(findings.first['categoria']).to eq('nao_contem_o_esperado')
      expect(findings.first['porque']).to include('das 9h às 18h')
    end

    it 'ignores casing, because the visitor reads the same text either way' do
      expect(described_class.evaluate({ 'contem' => ['DAS 9H'] }, resposta: 'abrimos das 9h às 18h')).to be_empty
    end

    it 'catches the forbidden snippet' do
      findings = described_class.evaluate({ 'nao_contem' => ['desconto'] }, resposta: 'Posso dar um desconto.')

      expect(findings.first['categoria']).to eq('contem_o_proibido')
    end

    it 'catches a tool that should have been called and was not' do
      findings = described_class.evaluate({ 'chama_ferramenta' => ['buscar_imovel'] },
                                          resposta: 'Temos sim!', ferramentas: [])

      expect(findings.first['categoria']).to eq('nao_chamou_a_ferramenta')
    end

    it 'catches a forbidden tool that was called' do
      findings = described_class.evaluate({ 'nao_chama_ferramenta' => ['enviar_email'] },
                                          resposta: 'Enviei!', ferramentas: %w[enviar_email])

      expect(findings.first['categoria']).to eq('chamou_ferramenta_proibida')
    end

    it 'judges handoff in both directions' do
      esperado = described_class.evaluate({ 'faz_handoff' => true }, resposta: 'x', handoff: false)
      indevido = described_class.evaluate({ 'faz_handoff' => false }, resposta: 'x', handoff: true)

      expect(esperado.first['categoria']).to eq('nao_fez_handoff')
      expect(indevido.first['categoria']).to eq('fez_handoff_indevido')
      expect(described_class.evaluate({ 'faz_handoff' => true }, resposta: 'x', handoff: true)).to be_empty
    end

    it 'accumulates every miss instead of stopping at the first' do
      findings = described_class.evaluate(
        { 'contem' => %w[a b], 'nao_contem' => ['c'] }, resposta: 'c'
      )

      expect(findings.map { |f| f['categoria'] })
        .to eq(%w[nao_contem_o_esperado nao_contem_o_esperado contem_o_proibido])
    end
  end
end
