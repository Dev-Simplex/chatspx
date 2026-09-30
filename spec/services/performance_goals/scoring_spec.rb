require 'rails_helper'

RSpec.describe PerformanceGoals::Scoring do
  describe '.attainment' do
    it 'maior e melhor: realizado / meta (sem limite na coluna)' do
      expect(described_class.attainment('resolved_conversations', 92, 80)).to be_within(0.001).of(1.15)
      expect(described_class.attainment('kanban_wins', 6, 3)).to eq(2.0)
    end

    it 'menor e melhor: meta / realizado' do
      expect(described_class.attainment('first_response_time', 4.2, 5)).to be_within(0.001).of(5 / 4.2)
    end

    it 'NPS negativo conta como 0' do
      expect(described_class.attainment('nps', -20, 70)).to eq(0)
    end

    it 'sem meta ou sem dado fica de fora (nil), nunca 0%' do
      expect(described_class.attainment('nps', nil, 70)).to be_nil
      expect(described_class.attainment('resolved_conversations', 10, nil)).to be_nil
    end
  end

  describe '.overall' do
    it 'media dos presentes, com cada um limitado a 150% dentro da media' do
      expect(described_class.overall([1.15, 5 / 4.2, nil])).to be_within(0.005).of(1.17)
      expect(described_class.overall([3.0, 1.0])).to eq(1.25)
    end

    it 'nil quando nenhum indicador entrou' do
      expect(described_class.overall([nil, nil])).to be_nil
    end
  end

  describe '.rank' do
    def row(name, resolved:, goal: 80)
      { id: name, name: name, metrics: { 'resolved_conversations' => { actual: resolved, goal: goal } } }
    end

    it 'ordena pela nota, desempata por resolvidas e nome, e separa quem nao tem meta' do
      rows = [row('Bia', resolved: 40), row('Ana', resolved: 80), row('Caio', resolved: 60, goal: 60),
              row('Davi', resolved: 99, goal: nil)]

      ranked, without_goal = described_class.rank(rows)

      expect(ranked.map { |r| [r[:name], r[:position]] }).to eq([['Ana', 1], ['Caio', 2], ['Bia', 3]])
      expect(ranked.first[:overall]).to eq(1.0)
      expect(without_goal.pluck(:name)).to eq(['Davi'])
    end

    it 'empate na nota: mais resolvidas primeiro' do
      ranked, = described_class.rank([row('A', resolved: 50, goal: 50), row('B', resolved: 80, goal: 80)])
      expect(ranked.pluck(:name)).to eq(%w[B A])
    end
  end
end
