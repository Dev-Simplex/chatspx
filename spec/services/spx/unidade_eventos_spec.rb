require 'rails_helper'

# Nasceu do feriado municipal de 14/09/2026 (Aniversário de Sinop), cadastrado e fechando o dia:
# o serviço excluía `feriado` de propósito — "a linha de horário já responde por ele" — e a linha
# de horário só responde para uma data RESOLVIDA. Quem pergunta "posso passar aí?" não cita data,
# e nesse caminho a IA recebia a grade da semana comum e marcou hora com o cliente.
RSpec.describe Spx::UnidadeEventos, type: :model do
  let(:account) { create(:account) }
  let(:unidade) { create(:unit, account: account, timezone: 'America/Cuiaba') }

  def hoje
    Time.now.in_time_zone(unidade.timezone).to_date
  end

  def linhas_com(*excecoes)
    described_class.new(unidade, excecoes).linhas
  end

  describe 'feriado que fecha o dia' do
    let(:feriado) do
      create(:unit_exception, unit: unidade, name: 'Aniversário da cidade', category: :feriado,
                              closed_all_day: true, starts_on: hoje)
    end

    it 'aparece, e diz que a unidade não abre' do
      linha = linhas_com(feriado).first

      expect(linha).to include('Aniversário da cidade')
      expect(linha).to include('unidade FECHADA nesse período')
    end

    it 'é rotulado como feriado, não como evento' do
      expect(linhas_com(feriado).first).to start_with('Feriado na unidade:')
    end

    # O caso das convs 11212 e 41997: a visita foi combinada na VÉSPERA, então enxergar só o dia
    # corrente não bastaria.
    it 'aparece na véspera' do
      amanha = create(:unit_exception, unit: unidade, name: 'Feriado de amanhã', category: :feriado,
                                       closed_all_day: true, starts_on: hoje + 1)

      expect(linhas_com(amanha).first).to include('Feriado de amanhã')
    end

    it 'some depois da janela' do
      distante = create(:unit_exception, unit: unidade, name: 'Natal', category: :feriado,
                                         closed_all_day: true, starts_on: hoje + described_class::JANELA_DIAS + 1)

      expect(linhas_com(distante)).to be_empty
    end
  end

  describe 'evento segue como estava (não-regressão)' do
    it 'mantém o rótulo de evento e o horário de sempre' do
      evento = create(:unit_exception, unit: unidade, name: 'Feirão', category: :evento,
                                       closed_all_day: false, open_hour: nil, close_hour: nil,
                                       starts_on: hoje)

      linha = linhas_com(evento).first
      expect(linha).to start_with('Evento na unidade:')
      expect(linha).to include('no horário de funcionamento de sempre')
    end

    it 'mantém o rótulo de manutenção' do
      obra = create(:unit_exception, unit: unidade, name: 'Troca do piso', category: :manutencao,
                                     closed_all_day: true, starts_on: hoje)

      expect(linhas_com(obra).first).to start_with('Manutenção na unidade:')
    end
  end

  describe '#fechamentos' do
    it 'traz só o que FECHA, sem rótulo de categoria' do
      fechado = create(:unit_exception, unit: unidade, name: 'Aniversário da cidade', category: :feriado,
                                        closed_all_day: true, starts_on: hoje)
      aberto = create(:unit_exception, unit: unidade, name: 'Feirão', category: :evento,
                                       closed_all_day: false, starts_on: hoje)

      linhas = described_class.new(unidade, [fechado, aberto]).fechamentos(2)

      expect(linhas.join).to include('Aniversário da cidade')
      expect(linhas.join).not_to include('Feirão')
      expect(linhas.join).not_to include('Feriado na unidade')
    end

    it 'respeita a janela curta de quem vai retirar a chave' do
      longe = create(:unit_exception, unit: unidade, name: 'Feriado distante', category: :feriado,
                                      closed_all_day: true, starts_on: hoje + 5)

      expect(described_class.new(unidade, [longe]).fechamentos(2)).to be_empty
    end

    it 'não opina quando não há fechamento' do
      expect(described_class.new(unidade, []).fechamentos(2)).to be_empty
    end
  end
end
