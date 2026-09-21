require 'rails_helper'

RSpec.describe Spx::Harness::Escritor do
  let(:destino) { Rails.root.join('tmp/harness-spec', "#{SecureRandom.hex(4)}.yml").to_s }
  let(:bruto) { { 'id' => 'x', 'mensagens' => [{ 'de' => 'cliente', 'texto' => 'quero alugar no Centro' }] } }

  after { FileUtils.rm_f(destino) }

  describe 'o digesto da paráfrase' do
    # Achado na PRIMEIRA gravação real (conv 41803): o SHA hexadecimal saiu com 10 dígitos
    # seguidos, casou como telefone e a trava derrubou a gravação. A correção é estrutural —
    # grupos de 4 separados por `_`, que fica fora da classe de separadores do padrão de
    # telefone —, não uma exceção na trava. Estes exemplos existem para isso não voltar.
    it 'nunca produz sequência longa de dígitos, nem para SHA totalmente numérico' do
      escritor = described_class.new(id: 'x')
      allow(Digest::SHA1).to receive(:hexdigest).and_return('398728498612')

      dados = escritor.send(:marcar_para_parafrase, bruto.deep_stringify_keys)

      expect(dados['mensagens'].first['texto_sha']).to eq('3987_2849_8612')
      expect(Spx::Harness::Vazamento.varrer(dados.to_yaml)).to be_empty
    end

    it 'resiste a uma varredura de digestos aleatórios' do
      escritor = described_class.new(id: 'x')

      200.times do
        hex = Array.new(12) { rand(16).to_s(16) }.join
        allow(Digest::SHA1).to receive(:hexdigest).and_return(hex)
        dados = escritor.send(:marcar_para_parafrase, bruto.deep_stringify_keys)

        expect(Spx::Harness::Vazamento.varrer(dados.to_yaml)).to be_empty
      end
    end

    it 'continua identificando o texto: mesmo texto, mesmo digesto' do
      a = described_class.new(id: 'x').send(:marcar_para_parafrase, bruto.deep_stringify_keys)
      b = described_class.new(id: 'y').send(:marcar_para_parafrase, bruto.deep_stringify_keys)

      expect(a['mensagens'].first['texto_sha']).to eq(b['mensagens'].first['texto_sha'])
    end
  end

  describe 'a ordem não negociável' do
    it 'não escreve nada quando a trava acusa' do
      allow(Spx::Harness::Vazamento).to receive(:conferir!).and_raise(Spx::Harness::Vazamento::Encontrado, 'boom')

      expect { described_class.new(id: 'x').gravar!(bruto, destino) }
        .to raise_error(Spx::Harness::Vazamento::Encontrado)
      expect(File).not_to exist(destino)
    end

    # A segunda conferida existe porque o marcador de paráfrase é aplicado DEPOIS da primeira:
    # gravar confiando na etapa anterior seria a fé cega que este harness existe para tirar.
    it 'confere duas vezes: antes e depois do marcador' do
      allow(Spx::Harness::Vazamento).to receive(:conferir!).and_call_original

      described_class.new(id: 'x').gravar!(bruto, destino)

      expect(Spx::Harness::Vazamento).to have_received(:conferir!).twice
    end
  end
end
