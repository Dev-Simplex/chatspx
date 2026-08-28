# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Unit do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:working_hours).class_name('UnitWorkingHour').dependent(:destroy) }
    it { is_expected.to have_many(:exceptions).class_name('UnitException').dependent(:destroy) }
    it { is_expected.to have_many(:inboxes).dependent(:nullify) }
  end

  describe 'validations' do
    let(:account) { create(:account) }

    it 'exige nome' do
      expect(described_class.new(account: account, timezone: 'UTC')).not_to be_valid
    end

    it 'recusa nome repetido na mesma conta, ignorando maiúsculas' do
      create(:unit, account: account, name: 'Sinop')
      repetida = build(:unit, account: account, name: 'sinop')

      expect(repetida).not_to be_valid
      expect(repetida.errors[:name]).to be_present
    end

    it 'aceita o mesmo nome em contas diferentes' do
      create(:unit, account: account, name: 'Sinop')

      expect(build(:unit, account: create(:account), name: 'Sinop')).to be_valid
    end

    it 'recusa fuso que não existe' do
      unidade = build(:unit, account: account, timezone: 'Marte/Olympus')

      expect(unidade).not_to be_valid
      expect(unidade.errors[:timezone]).to be_present
    end

    it 'aceita os fusos do Brasil que a tela oferece' do
      %w[America/Cuiaba America/Sao_Paulo America/Manaus America/Noronha].each do |fuso|
        expect(build(:unit, account: account, timezone: fuso)).to be_valid
      end
    end
  end

  describe 'grade padrão ao criar' do
    let(:account) { create(:account) }

    it 'nasce com a semana inteira: seg-sex das 8 às 18, fim de semana fechado' do
      unidade = create(:unit, account: account)

      expect(unidade.working_hours.count).to eq(7)
      expect(unidade.working_hours.where(closed_all_day: true).pluck(:day_of_week)).to contain_exactly(0, 6)
      segunda = unidade.working_hours.find_by(day_of_week: 1)
      expect([segunda.open_hour, segunda.close_hour]).to eq([8, 18])
    end

    # A tela SEMPRE manda a grade, inclusive ao criar. Sem a guarda, o callback
    # gravava sete linhas por cima das sete do nested attributes e o índice único
    # (unidade, dia) recusava — criar unidade nova falhava sempre.
    it 'não duplica a grade quando ela vem junto no cadastro' do
      unidade = account.units.create!(
        name: 'Com grade', timezone: 'America/Cuiaba',
        working_hours_attributes: [
          { day_of_week: 0, closed_all_day: true },
          { day_of_week: 1, closed_all_day: false, open_hour: 9, open_minutes: 0, close_hour: 13, close_minutes: 0 }
        ]
      )

      expect(unidade.working_hours.count).to eq(2)
      expect(unidade.working_hours.find_by(day_of_week: 1).close_hour).to eq(13)
    end
  end

  describe 'ao apagar' do
    it 'leva horários e regras junto, mas solta a caixa de entrada' do
      unidade = create(:unit)
      create(:unit_exception, unit: unidade)
      caixa = create(:inbox, account: unidade.account)
      caixa.update!(unit_id: unidade.id)

      expect { unidade.destroy! }.to change(UnitWorkingHour, :count).by(-7)
                                                                    .and change(UnitException, :count).by(-1)
      expect(caixa.reload).to be_persisted
      expect(caixa.unit_id).to be_nil
    end
  end
end
