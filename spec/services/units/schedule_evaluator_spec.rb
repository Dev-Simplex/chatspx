require 'rails_helper'

# Os casos vêm do MESMO arquivo que o spec do front consome. Se um lado mudar de
# comportamento sem o outro, um dos dois specs quebra — que é exatamente o ponto.
RSpec.describe Units::ScheduleEvaluator do
  fixture = JSON.parse(Rails.root.join('spec/fixtures/units/schedule_cases.json').read)
  padrao = fixture['padrao']

  def self.regra_de(padrao, extras)
    UnitException.new(padrao.merge(extras).except('name'))
  end

  describe '.rule_on?' do
    fixture['casos'].each do |caso|
      context caso['nome'] do
        caso['dias'].each do |dia, esperado|
          it "#{dia} => #{esperado}" do
            regra = UnitException.new(padrao.merge(caso['regra']).except('name'))
            expect(described_class.rule_on?(regra, Date.parse(dia))).to eq(esperado)
          end
        end
      end
    end
  end

  describe '#rule_on (precedência)' do
    fixture['precedencia'].each do |caso|
      it caso['nome'] do
        unit = build(:unit, timezone: 'America/Sao_Paulo')
        unit.exceptions = caso['regras'].map { |regra| UnitException.new(padrao.merge(regra)) }

        vencedora = described_class.new(unit).rule_on(Date.parse(caso['dia']))
        expect(vencedora&.name).to eq(caso['vencedora'])
      end
    end
  end

  describe '#closed_by_rule_now?' do
    let(:unit) { build(:unit, timezone: 'America/Sao_Paulo') }

    it 'devolve nil quando nenhuma regra cai hoje — quem decide é quem perguntou' do
      expect(described_class.new(unit).closed_by_rule_now?).to be_nil
    end

    it 'fecha o dia inteiro quando a regra fecha' do
      hoje = Time.current.in_time_zone(unit.timezone).to_date
      unit.exceptions = [UnitException.new(padrao.merge('starts_on' => hoje.to_s))]

      expect(described_class.new(unit).closed_by_rule_now?).to be(true)
    end

    it 'abre dentro da faixa que a regra definiu e fecha fora dela' do
      zona = ActiveSupport::TimeZone[unit.timezone]
      hoje = zona.today
      unit.exceptions = [
        UnitException.new(padrao.merge(
                            'starts_on' => hoje.to_s, 'closed_all_day' => false,
                            'open_hour' => 9, 'open_minutes' => 0, 'close_hour' => 18, 'close_minutes' => 0
                          ))
      ]
      avaliador = described_class.new(unit)

      expect(avaliador.closed_by_rule_now?(zona.parse("#{hoje} 10:00"))).to be(false)
      expect(avaliador.closed_by_rule_now?(zona.parse("#{hoje} 19:00"))).to be(true)
      expect(avaliador.closed_by_rule_now?(zona.parse("#{hoje} 08:59"))).to be(true)
    end
  end
end
