require 'rails_helper'

# O relógio existe porque contar na parede pune quem estava fora do expediente: um lead
# designado 18h50 de sexta estouraria um SLA de 30 min com o corretor em casa.
RSpec.describe Spx::Distribuicao::RelogioComercial do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def expediente(dias, abre: 9, fecha: 17)
    # Mesmo fuso do app (America/Manaus por padrão) para que os horários escritos no teste
    # signifiquem exatamente o que dizem — o objeto de teste aqui é o calendário, não o fuso.
    inbox.update!(working_hours_enabled: true, timezone: Time.zone.name)
    inbox.working_hours.destroy_all
    (0..6).each do |wday|
      inbox.working_hours.create!(
        day_of_week: wday, closed_all_day: dias.exclude?(wday),
        open_hour: abre, open_minutes: 0, close_hour: fecha, close_minutes: 0
      )
    end
  end

  describe '#minutos_decorridos' do
    context 'without expediente configurado' do
      it 'cai no relógio de parede (quem atende 24/7 não configurou nada)' do
        inicio = Time.zone.parse('2026-08-19 03:00')
        expect(described_class.new(inbox).minutos_decorridos(inicio, inicio + 90.minutes)).to eq(90)
      end
    end

    context 'with expediente' do
      before { expediente([1, 2, 3, 4, 5]) } # seg..sex 9h-17h

      it 'conta só o trecho dentro da janela' do
        inicio = Time.zone.parse('2026-08-19 08:30') # quarta, antes de abrir
        decorrido = described_class.new(inbox).minutos_decorridos(inicio, Time.zone.parse('2026-08-19 09:30'))
        expect(decorrido).to eq(30)
      end

      it 'não conta nada fora do expediente' do
        inicio = Time.zone.parse('2026-08-19 18:00')
        decorrido = described_class.new(inbox).minutos_decorridos(inicio, Time.zone.parse('2026-08-19 23:00'))
        expect(decorrido).to eq(0)
      end

      # O caso que motivou o relógio: 20h de parede viram poucas horas de expediente.
      it 'atravessa a noite somando só o dia seguinte' do
        inicio = Time.zone.parse('2026-08-19 16:30') # quarta 16h30
        decorrido = described_class.new(inbox).minutos_decorridos(inicio, Time.zone.parse('2026-08-20 09:30'))
        expect(decorrido).to eq(60) # 30 min na quarta + 30 min na quinta
      end

      it 'pula o fim de semana fechado' do
        inicio = Time.zone.parse('2026-08-21 16:30') # sexta 16h30
        decorrido = described_class.new(inbox).minutos_decorridos(inicio, Time.zone.parse('2026-08-24 09:15'))
        expect(decorrido).to eq(45) # 30 min sexta + 15 min segunda
      end
    end
  end

  describe '#vencido?' do
    before { expediente([1, 2, 3, 4, 5]) }

    it 'é falso quando o prazo correu fora do expediente' do
      inicio = Time.zone.parse('2026-08-19 18:50')
      expect(described_class.new(inbox).vencido?(inicio, 30, Time.zone.parse('2026-08-19 19:30'))).to be(false)
    end

    it 'é verdadeiro quando o prazo correu dentro do expediente' do
      inicio = Time.zone.parse('2026-08-19 10:00')
      expect(described_class.new(inbox).vencido?(inicio, 30, Time.zone.parse('2026-08-19 10:31'))).to be(true)
    end
  end
end
