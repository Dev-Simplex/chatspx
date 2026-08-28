# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UnitException do
  let(:unidade) { create(:unit) }

  def regra(extras = {})
    build(:unit_exception, { unit: unidade, starts_on: Date.new(2026, 9, 1) }.merge(extras))
  end

  describe 'associations' do
    it { is_expected.to belong_to(:unit) }
  end

  describe 'validations' do
    it 'exige motivo e data de início' do
      vazia = described_class.new(unit: unidade)

      expect(vazia).not_to be_valid
      expect(vazia.errors.attribute_names).to include(:name, :starts_on)
    end

    it 'aceita a regra simples de uma data só' do
      expect(regra).to be_valid
    end

    it 'exige horário quando não fecha o dia' do
      expect(regra(closed_all_day: false)).not_to be_valid
      expect(regra(closed_all_day: false, open_hour: 8, open_minutes: 0, close_hour: 12, close_minutes: 0)).to be_valid
    end

    it 'recusa intervalo de repetição zero ou negativo' do
      expect(regra(repeat_interval: 0)).not_to be_valid
      expect(regra(repeat_interval: -1)).not_to be_valid
    end
  end

  # As mensagens são comparadas pela chave de i18n: a suíte roda em inglês.
  describe 'repetição' do
    it 'semanal exige ao menos um dia da semana' do
      semanal = regra(frequency: :semanal)

      expect(semanal).not_to be_valid
      expect(semanal.errors[:base]).to include(I18n.t('errors.units.weekday_required'))
      expect(regra(frequency: :semanal, weekdays: [0, 3])).to be_valid
    end

    it 'mensal exige dia do mês OU posição com dia da semana' do
      expect(regra(frequency: :mensal)).not_to be_valid
      expect(regra(frequency: :mensal, week_positions: [1])).not_to be_valid
      expect(regra(frequency: :mensal, weekdays: [0])).not_to be_valid

      expect(regra(frequency: :mensal, month_days: [10])).to be_valid
      expect(regra(frequency: :mensal, month_days: [-1])).to be_valid
      expect(regra(frequency: :mensal, weekdays: [0], week_positions: [1, 3])).to be_valid
    end

    it 'anual não precisa de mais nada além da data' do
      expect(regra(frequency: :anual)).to be_valid
    end

    it 'recusa dia da semana, posição ou dia do mês fora da faixa' do
      expect(regra(frequency: :semanal, weekdays: [9])).not_to be_valid
      expect(regra(frequency: :mensal, weekdays: [0], week_positions: [7])).not_to be_valid
      expect(regra(frequency: :mensal, month_days: [45])).not_to be_valid
    end
  end

  describe 'período e término' do
    it 'só a regra que não repete pode durar um período' do
      com_periodo = regra(ends_on: Date.new(2026, 9, 5))
      expect(com_periodo).to be_valid

      repetindo = regra(frequency: :semanal, weekdays: [0], ends_on: Date.new(2026, 9, 5))
      expect(repetindo).not_to be_valid
      expect(repetindo.errors[:base]).to include(I18n.t('errors.units.range_only_without_repeat'))
    end

    it 'recusa fim antes do início' do
      expect(regra(ends_on: Date.new(2026, 8, 1))).not_to be_valid
      expect(regra(frequency: :semanal, weekdays: [0], until_date: Date.new(2020, 1, 1))).not_to be_valid
    end

    it 'aceita término no mesmo dia do início' do
      expect(regra(frequency: :semanal, weekdays: [0], until_date: Date.new(2026, 9, 1))).to be_valid
    end
  end

  describe 'categorias e frequências' do
    it 'guarda as quatro categorias' do
      described_class.categories.each_key do |categoria|
        expect(regra(category: categoria)).to be_valid
      end
    end

    it 'nasce como feriado que não se repete' do
      nova = described_class.new(unit: unidade, name: 'x', starts_on: Date.current)

      expect(nova.category).to eq('feriado')
      expect(nova.frequency).to eq('nao_repete')
      expect(nova.repeat_interval).to eq(1)
    end
  end
end
