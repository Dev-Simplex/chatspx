require 'rails_helper'

# A asserção de um cenário não é "o preço bateu". A mesma fala da conv 41803 afirma preço,
# quartos, suíte e vagas — quatro fatos sobre um imóvel que nenhuma busca do atendimento
# devolveu. Assertar só o preço deixaria três invenções passarem no verde.
RSpec.describe Spx::Harness::Afirmacoes do
  describe '.extrair' do
    it 'pega as quatro afirmações da fala real da 41803' do
      fala = 'esse fica em R$ 2.400 por mês, são 3 quartos sendo 1 suíte e 2 vagas de garagem'

      expect(described_class.extrair(fala)).to contain_exactly(
        { 'tipo' => 'preco', 'valor' => 2400.0 },
        { 'tipo' => 'dormitorios', 'valor' => 3.0 },
        { 'tipo' => 'suites', 'valor' => 1.0 },
        { 'tipo' => 'vagas', 'valor' => 2.0 }
      )
    end

    it 'pega código de imóvel e área' do
      afirmacoes = described_class.extrair('o cód 9412 tem 250 m²')

      expect(afirmacoes).to include({ 'tipo' => 'codigo', 'valor' => '9412' },
                                    { 'tipo' => 'area', 'valor' => 250.0 })
    end

    # Número sem âncora não é afirmação sobre o imóvel — mesmo critério da Preservacao. Sem
    # isso, "das 7h30 às 17h30" viraria quatro fatos inventados e o cenário acusaria fantasma.
    it 'não transforma horário, data e telefone em afirmação' do
      expect(described_class.extrair('atendemos das 7h30 às 17h30, dia 02/09, no (66) 3531-7222')).to be_empty
    end

    it 'não inventa afirmação em fala sem fato' do
      expect(described_class.extrair('claro, já vou verificar com o time')).to be_empty
    end
  end

  describe '.evidencia_antes' do
    let(:chamadas) do
      [{ 'tool' => 'atualizar_resumo', 'em' => '2026-09-11T17:10:00' },
       { 'tool' => 'buscar_imovel', 'em' => '2026-09-11T17:13:00' }]
    end

    # O caso da 41803: as cinco chamadas do atendimento são registro, transferência e envio —
    # nenhuma é busca. O agente afirmou sem ter o que consultar.
    it 'devolve vazio quando nenhuma busca precedeu a fala' do
      expect(described_class.evidencia_antes(chamadas, '2026-09-11T17:11:00')).to be_empty
    end

    it 'devolve a busca que veio antes' do
      expect(described_class.evidencia_antes(chamadas, '2026-09-11T17:14:00')).to eq(['buscar_imovel'])
    end

    # Resumo, handoff e observação não comprovam preço nenhum. A lista é por NOME de propósito.
    it 'não conta ferramenta que não produz evidência sobre imóvel' do
      apenas_resumo = [{ 'tool' => 'atualizar_resumo', 'em' => '2026-09-11T17:10:00' }]

      expect(described_class.evidencia_antes(apenas_resumo, '2026-09-11T17:20:00')).to be_empty
    end
  end
end
