require 'rails_helper'

RSpec.describe PerformanceGoal do
  let(:account) { create(:account) }

  def goal(**attrs)
    described_class.new({ account: account, month: Date.new(2026, 10, 1), target_type: 'user', target_id: 1,
                          metric: 'resolved_conversations', value: 80 }.merge(attrs))
  end

  describe 'validacoes' do
    it 'aceita os quatro indicadores com valores validos' do
      expect(goal).to be_valid
      expect(goal(metric: 'first_response_time', value: 4.5)).to be_valid
      expect(goal(metric: 'nps', value: 70)).to be_valid
      expect(goal(metric: 'kanban_wins', value: 3)).to be_valid
    end

    it 'recusa valor fora da regra de cada indicador' do
      expect(goal(value: 0)).not_to be_valid
      expect(goal(value: 2.5)).not_to be_valid
      expect(goal(metric: 'nps', value: 101)).not_to be_valid
      expect(goal(metric: 'first_response_time', value: -1)).not_to be_valid
      expect(goal(metric: 'outro')).not_to be_valid
      expect(goal(target_type: 'inbox')).not_to be_valid
    end

    it 'aceita valor nulo (sem meta deste mes em diante) e guarda o mes no dia 1' do
      g = goal(value: nil, month: Date.new(2026, 10, 17))
      expect(g).to be_valid
      expect(g.month).to eq(Date.new(2026, 10, 1))
    end
  end

  describe '.in_force' do
    def gravar(month, value, **attrs)
      goal(month: month, value: value, **attrs).tap(&:save!)
    end

    it 'vale do mes definido em diante, e a alteracao de novembro nao muda outubro' do
      gravar(Date.new(2026, 10, 1), 80)
      gravar(Date.new(2026, 11, 1), 90)

      expect(described_class.in_force(account, Date.new(2026, 9, 1))).to be_empty
      expect(described_class.in_force(account, Date.new(2026, 10, 1))[['user', 1, 'resolved_conversations']])
        .to eq(value: 80.0, since_month: Date.new(2026, 10, 1))
      expect(described_class.in_force(account, Date.new(2026, 11, 1))[['user', 1, 'resolved_conversations']][:value]).to eq(90.0)
      expect(described_class.in_force(account, Date.new(2027, 3, 1))[['user', 1, 'resolved_conversations']])
        .to eq(value: 90.0, since_month: Date.new(2026, 11, 1))
    end

    it 'valor nulo encerra a meta daquele mes em diante' do
      gravar(Date.new(2026, 10, 1), 80)
      gravar(Date.new(2026, 12, 1), nil)

      expect(described_class.in_force(account, Date.new(2026, 11, 1))).to have_key(['user', 1, 'resolved_conversations'])
      expect(described_class.in_force(account, Date.new(2027, 1, 1))).to be_empty
    end

    it 'nao mistura contas' do
      gravar(Date.new(2026, 10, 1), 80)
      expect(described_class.in_force(create(:account), Date.new(2026, 10, 1))).to be_empty
    end
  end
end
