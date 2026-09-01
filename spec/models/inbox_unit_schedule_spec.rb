require 'rails_helper'

# A regra de agenda da unidade passa a valer para a caixa dela — é o que faz o feriado
# da filial fechar o número sem ninguém reeditar caixa por caixa. O interruptor
# `applies_to_inboxes` nasce desligado: sem ele, nada muda.
RSpec.describe Inbox do
  let(:account) { create(:account) }
  let(:unit) { create(:unit, account: account, timezone: 'America/Sao_Paulo') }
  let(:inbox) { create(:inbox, account: account, working_hours_enabled: true) }
  let(:hoje) { Time.current.in_time_zone(unit.timezone).to_date }

  def feriado_hoje
    unit.exceptions.create!(name: 'Feriado', starts_on: hoje, closed_all_day: true)
  end

  describe 'caixa sem unidade' do
    it 'responde pelo próprio horário, como sempre' do
      expect(inbox.out_of_office?).to eq(inbox.working_hours.today.closed_now?)
    end
  end

  describe 'unidade com o interruptor desligado' do
    it 'ignora a regra da unidade' do
      feriado_hoje
      inbox.update!(unit: unit)

      expect(inbox.out_of_office?).to eq(inbox.working_hours.today.closed_now?)
    end
  end

  describe 'unidade com o interruptor ligado' do
    before { unit.update!(applies_to_inboxes: true) }

    it 'fecha a caixa no feriado da unidade' do
      feriado_hoje
      inbox.update!(unit: unit)

      expect(inbox.out_of_office?).to be(true)
    end

    it 'em dia sem regra devolve a resposta de sempre' do
      inbox.update!(unit: unit)

      expect(inbox.out_of_office?).to eq(inbox.working_hours.today.closed_now?)
    end

    it 'abre a caixa quando a regra abre o dia com faixa própria' do
      zona = ActiveSupport::TimeZone[unit.timezone]
      unit.exceptions.create!(name: 'Plantão', starts_on: hoje, closed_all_day: false,
                              open_hour: 0, open_minutes: 0, close_hour: 23, close_minutes: 59)
      inbox.update!(unit: unit)

      travel_to zona.parse("#{hoje} 12:00") do
        expect(inbox.out_of_office?).to be(false)
      end
    end
  end
end
