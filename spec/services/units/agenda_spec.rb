require 'rails_helper'

# A semântica tem que ser a MESMA da tela (units/unitSchedule.js): divergir faria a tela e a IA
# responderem coisas diferentes sobre o mesmo dia.
RSpec.describe Units::Agenda do
  let(:account) { create(:account) }
  let(:unit) { Unit.create!(account: account, name: 'Matriz', timezone: 'America/Cuiaba') }

  # O after_create do Unit já cria a grade padrão; os testes ajustam o dia que interessa.
  def grade!(wday, abre: 8, fecha: 18, fechada: false, pausa: nil)
    linha = unit.working_hours.find_or_initialize_by(day_of_week: wday)
    linha.assign_attributes(closed_all_day: fechada, open_all_day: false,
                            open_hour: abre, open_minutes: 0, close_hour: fecha, close_minutes: 0)
    if pausa
      linha.assign_attributes(break_start_hour: pausa[0], break_start_minutes: 0,
                              break_end_hour: pausa[1], break_end_minutes: 0)
    end
    linha.save!
    linha
  end

  def regra!(**attrs)
    unit.exceptions.create!({ name: 'Regra', starts_on: Date.new(2026, 9, 10), closed_all_day: true,
                              frequency: :nao_repete, repeat_interval: 1, category: :feriado,
                              weekdays: [], week_positions: [], month_days: [] }.merge(attrs))
  end

  describe '#dia' do
    it 'devolve a linha da semana quando não há regra' do
      grade!(4, abre: 7, fecha: 17)

      dia = described_class.new(unit.reload).dia(Date.new(2026, 9, 10)) # quinta

      expect(dia.fechada?).to be false
      expect([dia.abre, dia.fecha]).to eq(%w[07:00 17:00])
    end

    # Dia NÃO cadastrado é diferente de dia fechado, e quem lê precisa poder distinguir.
    it 'devolve nil quando o dia não tem linha nem regra' do
      unit.working_hours.destroy_all

      expect(described_class.new(unit.reload).dia(Date.new(2026, 9, 10))).to be_nil
    end

    it 'a regra SUBSTITUI a linha da semana no dia em que cai' do
      grade!(4)
      regra!(name: 'Feriado municipal')

      dia = described_class.new(unit.reload).dia(Date.new(2026, 9, 10))

      expect(dia.fechada?).to be true
      expect(dia.motivo).to eq('Feriado municipal')
    end

    # É assim que uma regra ABRE um domingo que a grade fecha.
    it 'a regra abre um dia que a grade fecha' do
      grade!(0, fechada: true)
      regra!(starts_on: Date.new(2026, 9, 13), closed_all_day: false,
             open_hour: 9, open_minutes: 0, close_hour: 13, close_minutes: 0, name: 'Plantão')

      dia = described_class.new(unit.reload).dia(Date.new(2026, 9, 13)) # domingo

      expect(dia.fechada?).to be false
      expect([dia.abre, dia.fecha]).to eq(%w[09:00 13:00])
    end

    it 'traz a pausa do almoço da grade' do
      grade!(4, abre: 7, fecha: 18, pausa: [11, 13])

      dia = described_class.new(unit.reload).dia(Date.new(2026, 9, 10))

      expect(dia.pausa?).to be true
      expect([dia.pausa_inicio, dia.pausa_fim]).to eq(%w[11:00 13:00])
    end
  end

  describe 'recorrência' do
    it 'semanal, respeitando o intervalo de repetição' do
      grade!(4)
      regra!(frequency: :semanal, weekdays: [4], repeat_interval: 2, starts_on: Date.new(2026, 9, 10))
      agenda = described_class.new(unit.reload)

      expect(agenda.dia(Date.new(2026, 9, 10)).fechada?).to be true   # semana 0
      expect(agenda.dia(Date.new(2026, 9, 17)).fechada?).to be false  # semana 1 — pula
      expect(agenda.dia(Date.new(2026, 9, 24)).fechada?).to be true   # semana 2
    end

    it 'mensal por dia do mês' do
      grade!(4)
      grade!(6) # 10/10/2026 é sábado e 12/10 é segunda: as duas linhas precisam existir e abrir
      grade!(1)
      regra!(frequency: :mensal, month_days: [10], starts_on: Date.new(2026, 9, 10))
      agenda = described_class.new(unit.reload)

      expect(agenda.dia(Date.new(2026, 10, 10)).fechada?).to be true  # dia 10 do mês seguinte
      expect(agenda.dia(Date.new(2026, 10, 12)).fechada?).to be false # dia 12 não casa a regra
    end

    it 'mensal pela posição do dia da semana (1º domingo)' do
      grade!(0, fechada: false)
      regra!(frequency: :mensal, weekdays: [0], week_positions: [1], starts_on: Date.new(2026, 9, 6))
      agenda = described_class.new(unit.reload)

      expect(agenda.dia(Date.new(2026, 10, 4)).fechada?).to be true   # 1º domingo
      expect(agenda.dia(Date.new(2026, 10, 11)).fechada?).to be false # 2º domingo
    end

    it 'anual' do
      grade!(4)
      regra!(frequency: :anual, starts_on: Date.new(2026, 9, 10))

      expect(described_class.new(unit.reload).dia(Date.new(2027, 9, 10)).fechada?).to be true
    end

    # Férias coletivas de 20/12 a 05/01 numa linha só, em vez de dezessete.
    it 'período de uma regra que não repete cobre todos os dias' do
      grade!(1)
      regra!(starts_on: Date.new(2026, 12, 20), ends_on: Date.new(2027, 1, 5), name: 'Férias')
      agenda = described_class.new(unit.reload)

      expect(agenda.dia(Date.new(2026, 12, 28)).fechada?).to be true
      expect(agenda.dia(Date.new(2027, 1, 6))&.fechada?).to be_falsey
    end

    it 'não vale depois do until_date' do
      grade!(4)
      regra!(frequency: :semanal, weekdays: [4], starts_on: Date.new(2026, 9, 10),
             until_date: Date.new(2026, 9, 17))
      agenda = described_class.new(unit.reload)

      expect(agenda.dia(Date.new(2026, 9, 17)).fechada?).to be true
      expect(agenda.dia(Date.new(2026, 9, 24)).fechada?).to be false
    end
  end

  # Nunca prometer ao cliente que a unidade está aberta.
  describe 'precedência' do
    it 'no empate de especificidade, vence a regra que FECHA' do
      grade!(4)
      regra!(name: 'Abre especial', closed_all_day: false, open_hour: 9, open_minutes: 0,
             close_hour: 12, close_minutes: 0)
      regra!(name: 'Feriado', closed_all_day: true)

      dia = described_class.new(unit.reload).dia(Date.new(2026, 9, 10))

      expect(dia.fechada?).to be true
      expect(dia.motivo).to eq('Feriado')
    end

    it 'a regra mais específica vence a mais genérica' do
      grade!(4)
      regra!(name: 'Anual', frequency: :anual, starts_on: Date.new(2026, 9, 10), closed_all_day: true)
      regra!(name: 'Data única', frequency: :nao_repete, starts_on: Date.new(2026, 9, 10),
             closed_all_day: false, open_hour: 10, open_minutes: 0, close_hour: 14, close_minutes: 0)

      dia = described_class.new(unit.reload).dia(Date.new(2026, 9, 10))

      expect(dia.motivo).to eq('Data única')
      expect(dia.fechada?).to be false
    end
  end
end
