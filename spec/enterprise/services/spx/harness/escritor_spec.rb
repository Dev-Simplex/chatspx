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

  # A regra é do CLIENTE, não da conversa. A fala da IA é o objeto do teste: é nela que mora o
  # preço afirmado sem busca. Parafraseá-la apagava o que a fixture precisa provar.
  describe 'quem é parafraseado' do
    subject(:saida) { described_class.new(id: 'x').send(:marcar_para_parafrase, conversa) }

    let(:conversa) do
      { 'mensagens' => [
        { 'de' => 'cliente', 'texto' => 'quanto custa?' },
        { 'de' => 'ia', 'texto' => 'o aluguel fica em R$ 2.400' },
        { 'de' => 'humano', 'texto' => 'na verdade são R$ 3.200' }
      ] }
    end

    it 'parafraseia a fala do cliente' do
      expect(saida['mensagens'][0]['texto']).to eq(described_class::PARAFRASEAR)
    end

    it 'PRESERVA a fala da IA, com o número que ela afirmou' do
      expect(saida['mensagens'][1]['texto']).to include('R$ 2.400')
    end

    # Humano não é IA: rotular a fala de uma pessoa como do agente faria a fixture asseverar
    # que o modelo disse o que o atendente disse. Na 41803 são três mensagens assim.
    it 'PRESERVA a fala do humano' do
      expect(saida['mensagens'][2]['texto']).to include('R$ 3.200')
    end
  end

  # SHA1 de string vazia. Mensagem com esse digesto não é fala: é mídia (pin, carrossel, áudio).
  # Marcá-la para paráfrase pedia que se reescrevesse o nada.
  describe 'mídia' do
    subject(:mensagem) { described_class.new(id: 'x').send(:marcar_para_parafrase, conversa)['mensagens'].first }

    let(:conversa) { { 'mensagens' => [{ 'de' => 'ia', 'texto' => '', 'midia' => 'location' }] } }

    it 'não vira marcador de paráfrase' do
      expect(mensagem['texto']).to be_nil
      expect(mensagem.to_s).not_to include('PARAFRASEAR')
    end

    it 'conserva o tipo e descarta o digesto do vazio' do
      expect(mensagem['midia']).to eq('location')
      expect(mensagem).not_to have_key('texto_sha')
    end
  end

  describe 'a checagem de preservação no caminho de gravação' do
    it 'não escreve quando um valor do original se perdeu' do
      escritor = described_class.new(id: 'x', original: 'ia: fica em R$ 2.400')
      bruto = { 'mensagens' => [{ 'de' => 'cliente', 'texto' => 'quanto?' }] }

      expect { escritor.gravar!(bruto, destino) }.to raise_error(Spx::Harness::Preservacao::Perdido)
      expect(File).not_to exist(destino)
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
