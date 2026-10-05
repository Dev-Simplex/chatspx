require 'rails_helper'

# O `piso` responde "está aceitável?". O baseline responde "PIOROU?" — e é a segunda pergunta
# que pega a regressão de prompt que fica ACIMA do piso. Um cenário que ia 6/6 e passou a ir
# 4/6 continua acima de um piso 4 e não acusa nada.
RSpec.describe Spx::Conduta::Baseline do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account, config: { 'instructions' => 'aja assim' }) }
  let(:digest) { described_class.digest_do_prompt(assistant) }

  def cenario(acertos:, prompt: digest)
    { 'nome' => 'x', 'baseline' => { 'acertos' => acertos, 'prompt' => prompt, 'em' => '2026-09-21' } }
  end

  describe '.ler' do
    it 'acusa queda quando cai além da variância' do
      leitura = described_class.ler(cenario(acertos: 6), acertos: 4, assistant: assistant)

      expect(leitura).to be_caiu
      expect(leitura.texto).to include('CAIU 6->4')
    end

    # Medido: o mesmo prompt deu 5/6 e 6/6 no mesmo dia. Acusar queda de 1 transformaria
    # variância em alarme falso, e alarme falso é como um portão deixa de ser lido.
    it 'não acusa queda de 1, que está dentro da variância entre rodadas idênticas' do
      expect(described_class.ler(cenario(acertos: 6), acertos: 5, assistant: assistant)).not_to be_caiu
    end

    it 'reconhece melhora' do
      expect(described_class.ler(cenario(acertos: 4), acertos: 6, assistant: assistant).texto).to include('subiu 4->6')
    end

    # Comparar contra número medido em OUTRO prompt não diz nada. Vencido é vencido, não queda.
    it 'não compara baseline medido em outro prompt' do
      leitura = described_class.ler(cenario(acertos: 6, prompt: 'outro-digest'), acertos: 2, assistant: assistant)

      expect(leitura).not_to be_caiu
      expect(leitura.texto).to include('baseline vencido')
    end

    it 'diz quando não há baseline nenhum' do
      expect(described_class.ler({ 'nome' => 'x' }, acertos: 6, assistant: assistant).texto).to eq('sem baseline')
    end
  end

  describe 'o arquivo irmão' do
    # Separado do arquivo de cenários de propósito: aquele é metade comentário (o porquê de
    # cada piso, o caso real que o originou) e reescrevê-lo por máquina apagaria isso.
    it 'mora ao lado do arquivo de cenários' do
      expect(described_class.arquivo_de('docs/x/conduta-regressao.yml')).to eq('docs/x/conduta-regressao.baseline.yml')
    end

    it 'mescla por nome e deixa sem baseline quem não foi medido' do
      allow(described_class).to receive(:carregar).and_return({ 'medido' => { 'acertos' => 6 } })

      aplicados = described_class.aplicar([{ 'nome' => 'medido' }, { 'nome' => 'novo' }], 'x.yml')

      expect(aplicados.first['baseline']).to eq({ 'acertos' => 6 })
      expect(aplicados.last).not_to have_key('baseline')
    end
  end

  describe '.congelar' do
    it 'grava o número com a data e o prompt em que foi medido' do
      congelado = described_class.congelar(acertos: 5, assistant: assistant)

      expect(congelado).to include('acertos' => 5, 'prompt' => digest)
      expect(congelado['em']).to eq(Date.current.iso8601)
    end
  end
end
