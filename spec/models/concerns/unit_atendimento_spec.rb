require 'rails_helper'

# O domínio de atendimento da unidade — o que a IA lê para responder "onde fica e a que horas abre".
#
# Estes exemplos vieram do `spec/models/spx/unidade_spec.rb`, da implementação irmã aposentada na
# unificação. Ficaram de fora, por não existirem no modelo único, os casos de exceção por ETIQUETA e
# de exceção da CONTA inteira: `unit_exceptions` é sempre de UMA unidade. É a única capacidade que a
# unificação não carrega, e nenhuma conta tinha exceção cadastrada quando ela aconteceu.
RSpec.describe UnitAtendimento do
  let(:account) { create(:account) }
  let(:unidade) { create(:unit, account: account, timezone: 'America/Cuiaba') }

  def grade(dia, **attrs)
    unidade.working_hours.where(day_of_week: dia).destroy_all
    create(:unit_working_hour, { unit: unidade, day_of_week: dia }.merge(attrs))
    unidade.reload
  end

  describe 'horário padrão' do
    it 'devolve a faixa cadastrada para o dia da semana' do
      grade(1, open_hour: 8, open_minutes: 0, close_hour: 18, close_minutes: 0)

      expect(unidade.faixas_padrao(1).map(&:to_s)).to eq(['08:00 às 18:00'])
    end

    it 'fecha quando o dia está cadastrado como fechado' do
      grade(0, closed_all_day: true, open_hour: nil, open_minutes: nil, close_hour: nil, close_minutes: nil)

      expect(unidade.faixas_padrao(0)).to be_empty
      expect(unidade.dia_cadastrado?(0)).to be true
    end

    # Onde a tabela antiga usava DUAS linhas no mesmo dia, esta usa uma com intervalo. O que quem lê
    # recebe tem que ser o mesmo texto — é o horário da Tozi, 07:30-11:30 e 13:30-17:30.
    it 'devolve as duas faixas quando o dia tem intervalo' do
      grade(1, open_hour: 7, open_minutes: 30, close_hour: 17, close_minutes: 30,
               break_start_hour: 11, break_start_minutes: 30, break_end_hour: 13, break_end_minutes: 30)

      expect(unidade.faixas_padrao(1).map(&:to_s)).to eq(['07:30 às 11:30', '13:30 às 17:30'])
    end

    # Ausência de linha NÃO é "fechada": é "não sei". Quem lê precisa distinguir, senão a resposta ao
    # cliente vira invenção com cara de dado.
    it 'distingue dia sem cadastro de dia fechado' do
      unidade.working_hours.destroy_all
      grade(1, open_hour: 8, open_minutes: 0, close_hour: 18, close_minutes: 0)

      expect(unidade.dia_cadastrado?(1)).to be true
      expect(unidade.dia_cadastrado?(6)).to be false
    end
  end

  describe 'relógio de parede' do
    before { grade(1, open_hour: 8, open_minutes: 0, close_hour: 18, close_minutes: 0) }

    it 'diz se o minuto do dia cai dentro de alguma faixa' do
      estado = unidade.estado_em(Date.current.next_occurring(:monday))

      expect(estado.aberta_em?(9 * 60)).to be true
      expect(estado.aberta_em?(19 * 60)).to be false
    end

    it 'fecha no intervalo, e não só fora do expediente' do
      grade(1, open_hour: 7, open_minutes: 30, close_hour: 17, close_minutes: 30,
               break_start_hour: 11, break_start_minutes: 30, break_end_hour: 13, break_end_minutes: 30)
      estado = unidade.estado_em(Date.current.next_occurring(:monday))

      expect(estado.aberta_em?(12 * 60)).to be false
      expect(estado.aberta_em?(14 * 60)).to be true
    end

    it 'trata faixa que atravessa a meia-noite' do
      faixa = described_class::Faixa.new(inicio: 22 * 60, fim: 2 * 60)

      expect(faixa.contem?(23 * 60)).to be true
      expect(faixa.contem?(1 * 60)).to be true
      expect(faixa.contem?(12 * 60)).to be false
    end
  end

  describe 'exceção' do
    let(:dia) { Date.current.next_occurring(:monday) }

    before { grade(1, open_hour: 8, open_minutes: 0, close_hour: 18, close_minutes: 0) }

    it 'fecha o dia quando a exceção fecha, mesmo com horário padrão cadastrado' do
      create(:unit_exception, unit: unidade, name: 'feriado', closed_all_day: true, starts_on: dia)
      estado = unidade.reload.estado_em(dia)

      expect(estado.aberta?).to be false
      expect(estado.por_excecao?).to be true
      expect(estado.motivo).to eq('feriado')
    end

    it 'troca o horário quando a exceção traz um' do
      create(:unit_exception, unit: unidade, name: 'campanha', closed_all_day: false, starts_on: dia,
                              open_hour: 9, open_minutes: 0, close_hour: 15, close_minutes: 0)

      expect(unidade.reload.estado_em(dia).faixas.map(&:to_s)).to eq(['09:00 às 15:00'])
    end

    it 'ignora exceção fora da data' do
      create(:unit_exception, unit: unidade, name: 'feriado', closed_all_day: true, starts_on: dia + 3)
      estado = unidade.reload.estado_em(dia)

      expect(estado.por_excecao?).to be false
      expect(estado.faixas.map(&:to_s)).to eq(['08:00 às 18:00'])
    end

    it 'no empate vence a criada por último' do
      create(:unit_exception, unit: unidade, name: 'primeira', closed_all_day: true, starts_on: dia)
      travel_to(2.minutes.from_now) do
        create(:unit_exception, unit: unidade, name: 'segunda', closed_all_day: true, starts_on: dia)
      end

      expect(unidade.reload.estado_em(dia).motivo).to eq('segunda')
    end

    it 'usa o escopo de exceções já carregado quando ele é passado' do
      create(:unit_exception, unit: unidade, name: 'feriado', closed_all_day: true, starts_on: dia)
      carregadas = UnitException.where(unit_id: unidade.id).to_a

      expect(unidade.reload.estado_em(dia, escopo_excecoes: carregadas).motivo).to eq('feriado')
    end
  end

  describe 'geografia e rótulos' do
    it 'devolve nil quando falta coordenada de um dos lados' do
      expect(unidade.distancia_de(-11.85, -55.50)).to be_nil
    end

    it 'mede a distância quando as duas pontas existem' do
      unidade.update!(latitude: -11.851883, longitude: -55.509187)

      expect(unidade.distancia_de(-11.86, -55.50)).to be_within(0.3).of(1.35)
    end

    it 'casa a etiqueta sem depender de acento nem de caixa' do
      unidade.update!(etiquetas: ['Matriz'])

      expect(unidade.etiqueta?('MATRIZ')).to be true
      expect(unidade.etiqueta?('filial')).to be false
    end
  end
end
