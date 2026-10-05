require 'rails_helper'

# A trava anti-vazamento pergunta "sobrou algo que não podia ficar?". Esta pergunta o oposto:
# "sumiu algo que precisava ficar?". São falhas independentes, e a primeira gravação da conv
# 41803 passou limpa na trava e teria sido reprovada aqui por DOIS motivos ao mesmo tempo.
RSpec.describe Spx::Harness::Preservacao do
  describe 'os dois defeitos reais da 41803' do
    # A fala da IA foi parafraseada junto com a do cliente, e o preço que o agente afirmou sem
    # busca desapareceu. Sem esse número a fixture não testa o caso dela.
    it 'acusa o preço inventado pela IA que sumiu na paráfrase' do
      original = 'cliente: quanto é? · ia: o aluguel desse fica em R$ 2.400'
      fixture = 'cliente: <PARAFRASEAR> · ia: <PARAFRASEAR>'

      expect { described_class.conferir!(fixture, original: original, origem: 'x') }
        .to raise_error(described_class::Perdido, /valor 2400/)
    end

    # Duas regras de URL em sequência reescreveram uma a saída da outra, e o código do imóvel
    # sumiu do argumento do atualizar_resumo.
    it 'acusa o código de imóvel que sumiu do argumento da ferramenta' do
      original = '{"resumo":"cliente quer o imóvel 9412"}'
      fixture = '{"resumo":"cliente quer o imóvel"}'

      expect { described_class.conferir!(fixture, original: original, origem: 'x') }
        .to raise_error(described_class::Perdido, /código 9412/)
    end

    it 'diz que a fixture não foi gravada, e por quê' do
      expect { described_class.conferir!('nada', original: 'cód 9412', origem: 'f1') }
        .to raise_error(described_class::Perdido, /f1.*não testaria o caso dela/m)
    end
  end

  describe 'o que passa' do
    it 'aceita quando tudo sobreviveu, mesmo em outro formato' do
      original = 'imóvel 9412 por R$ 2.400,00'
      fixture = 'imóvel 9412 por 2400 reais'

      expect(described_class.conferir!(fixture, original: original, origem: 'x')).to eq(fixture)
    end

    it 'aceita fixture que ACRESCENTA valor, contanto que não perca nenhum' do
      expect(described_class.faltantes('cód 9412 e cód 9908', 'cód 9412')).to be_empty
    end
  end

  # Entrou quando a troca de nome passou a agir em PEDAÇOS: sobrenome brasileiro é nome de
  # bairro com frequência — Oliveira, Campos, Rocha, Lima. Se a lista de proteção do
  # Pseudonimizador falhar, o bairro some da fixture e o cenário deixa de descrever a conversa.
  describe 'o vocabulário de negócio' do
    it 'acusa bairro que sumiu da fixture' do
      expect { described_class.conferir!('casa no CONTATO-12', original: 'casa no Parque Amazonas', origem: 'x', termos: ['Amazonas']) }
        .to raise_error(described_class::Perdido, /termo Amazonas/)
    end

    it 'aceita quando o termo sobreviveu' do
      expect(described_class.faltantes('casa no Parque Amazonas', 'casa no Parque Amazonas', termos: ['Amazonas']))
        .to be_empty
    end

    # A lista vem da conta inteira e a maioria dos termos não aparece nesta conversa. Cobrar
    # termo ausente dos dois lados acusaria perda que não houve.
    it 'não cobra termo que nunca esteve no original' do
      expect(described_class.faltantes('nada aqui', 'nada aqui', termos: %w[Amazonas Belvedere])).to be_empty
    end

    it 'não confunde o termo com pedaço de outra palavra' do
      expect(described_class.presentes(['Ana'], 'comprei uma banana')).to be_empty
    end
  end

  describe 'o que NÃO é código nem valor' do
    # Sem a palavra-âncora, qualquer quantidade viraria "código" e a checagem acusaria o que ela
    # mesma não precisa — o oposto do problema, mas igualmente inútil.
    it 'ignora número solto sem âncora' do
      expect(described_class.codigos('3 quartos, 2 suítes, 250 m²')).to be_empty
    end

    it 'ignora zero' do
      expect(described_class.valores('R$ 0')).to be_empty
    end

    it 'reconhece as três âncoras de código' do
      expect(described_class.codigos('cód 1111, código 2222, imóvel 3333, Ref. 4444'))
        .to contain_exactly('1111', '2222', '3333', '4444')
    end
  end
end
