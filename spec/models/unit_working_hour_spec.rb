# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UnitWorkingHour do
  # A unidade já nasce com os sete dias (Unit#criar_grade_padrao), então os exemplos
  # trabalham em cima das linhas que existem em vez de criar dia repetido.
  let(:unidade) { create(:unit) }
  let(:segunda) { unidade.working_hours.find_by(day_of_week: 1) }
  let(:domingo) { unidade.working_hours.find_by(day_of_week: 0) }

  describe 'validations' do
    it { is_expected.to belong_to(:unit) }

    it 'recusa dia fora de domingo–sábado' do
      segunda.day_of_week = 7

      expect(segunda).not_to be_valid
      expect(segunda.errors[:day_of_week]).to be_present
    end

    it 'recusa dia repetido na mesma unidade' do
      repetido = build(:unit_working_hour, unit: unidade, day_of_week: 1)

      expect(repetido).not_to be_valid
      expect(repetido.errors[:day_of_week]).to be_present
    end

    it 'dia fechado não precisa de horário' do
      expect(domingo).to be_valid
      expect(domingo.open_hour).to be_nil
    end

    it 'dia aberto precisa de horário' do
      segunda.assign_attributes(open_hour: nil, close_hour: nil)

      expect(segunda).not_to be_valid
    end

    it 'recusa fechar antes de abrir' do
      segunda.assign_attributes(open_hour: 18, close_hour: 8)

      expect(segunda).not_to be_valid
      expect(segunda.errors[:close_hour]).to be_present
    end

    it 'recusa abrir e fechar o dia todo ao mesmo tempo' do
      segunda.assign_attributes(open_all_day: true, closed_all_day: true)

      expect(segunda).not_to be_valid
    end

    it 'normaliza o dia inteiro para 00:00–23:59' do
      segunda.update!(open_all_day: true)

      expect([segunda.open_hour, segunda.open_minutes, segunda.close_hour, segunda.close_minutes]).to eq([0, 0, 23, 59])
    end
  end

  # As mensagens são comparadas pela chave de i18n: a suíte roda em inglês, e o texto
  # em português só apareceria numa conta pt_BR.
  describe 'parada para o almoço' do
    it 'aceita a pausa dentro do expediente' do
      segunda.assign_attributes(break_start_hour: 12, break_start_minutes: 0, break_end_hour: 13, break_end_minutes: 30)

      expect(segunda).to be_valid
      expect(segunda).to be_pausa
    end

    it 'recusa meia pausa' do
      segunda.assign_attributes(break_start_hour: 12, break_start_minutes: 0)

      expect(segunda).not_to be_valid
      expect(segunda.errors[:base]).to include(I18n.t('errors.units.break_incomplete'))
    end

    it 'recusa pausa que termina antes de começar' do
      segunda.assign_attributes(break_start_hour: 14, break_start_minutes: 0, break_end_hour: 13, break_end_minutes: 0)

      expect(segunda).not_to be_valid
      expect(segunda.errors[:base]).to include(I18n.t('errors.units.break_inverted'))
    end

    it 'recusa pausa fora do horário de funcionamento' do
      segunda.assign_attributes(break_start_hour: 19, break_start_minutes: 0, break_end_hour: 20, break_end_minutes: 0)

      expect(segunda).not_to be_valid
      expect(segunda.errors[:base]).to include(I18n.t('errors.units.break_outside_hours'))
    end

    it 'recusa pausa em dia fechado' do
      domingo.assign_attributes(break_start_hour: 12, break_start_minutes: 0, break_end_hour: 13, break_end_minutes: 0)

      expect(domingo).not_to be_valid
      expect(domingo.errors[:base]).to include(I18n.t('errors.units.break_on_closed_day'))
    end

    it 'aceita pausa num dia aberto 24 h, porque ali não há faixa para respeitar' do
      segunda.assign_attributes(open_all_day: true, break_start_hour: 12, break_start_minutes: 0,
                                break_end_hour: 13, break_end_minutes: 0)

      expect(segunda).to be_valid
    end

    it 'dia sem pausa responde que não tem' do
      expect(segunda).not_to be_pausa
    end
  end
end
