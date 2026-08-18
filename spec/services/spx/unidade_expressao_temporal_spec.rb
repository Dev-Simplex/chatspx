require 'rails_helper'

# O motivo de esta classe existir é tirar a conta de calendário do modelo de linguagem. Logo, o
# que estes exemplos guardam não é só "resolve amanhã": é que expressão NÃO resolvível volta
# marcada como não resolvida, e nunca vira "hoje" por omissão.
RSpec.describe Spx::UnidadeExpressaoTemporal do
  let(:zona) { ActiveSupport::TimeZone['America/Cuiaba'] }

  # 2026-08-19 é quarta-feira. 14:30 no fuso da unidade.
  def resolver(expressao, em: '2026-08-19 14:30:00')
    travel_to(zona.parse(em)) { described_class.resolver(expressao, zona) }
  end

  describe 'expressões relativas' do
    it 'resolve hoje' do
      expect(resolver('hoje').datas).to eq([Date.new(2026, 8, 19)])
    end

    it 'resolve amanhã' do
      expect(resolver('amanhã').datas).to eq([Date.new(2026, 8, 20)])
    end

    it 'resolve depois de amanhã sem cair no amanhã que está dentro dele' do
      expect(resolver('depois de amanhã').datas).to eq([Date.new(2026, 8, 21)])
    end

    it 'não confunde "de manhã" com "amanhã"' do
      expect(resolver('hoje de manhã').datas).to eq([Date.new(2026, 8, 19)])
    end

    it 'marca o instante quando a pergunta é sobre o momento presente' do
      resultado = resolver('agora')

      expect(resultado.datas).to eq([Date.new(2026, 8, 19)])
      expect(resultado).to be_instante
      expect(resultado.instante.hour).to eq(14)
    end

    it 'não marca instante quando a pergunta é só sobre o dia' do
      expect(resolver('amanhã')).not_to be_instante
    end
  end

  describe 'dias da semana' do
    it 'aponta para a próxima ocorrência' do
      expect(resolver('sábado').datas).to eq([Date.new(2026, 8, 22)])
    end

    it 'inclui o próprio dia quando ele é o dia citado' do
      expect(resolver('quarta').datas).to eq([Date.new(2026, 8, 19)])
    end

    it 'empurra para a semana seguinte com "que vem"' do
      expect(resolver('quarta que vem').datas).to eq([Date.new(2026, 8, 26)])
    end

    it 'aceita a forma com -feira' do
      expect(resolver('segunda-feira').datas).to eq([Date.new(2026, 8, 24)])
    end

    it 'devolve os dois dias quando a pessoa cita dois' do
      expect(resolver('sábado ou domingo').datas).to eq([Date.new(2026, 8, 22), Date.new(2026, 8, 23)])
    end
  end

  describe 'fim de semana' do
    it 'devolve sábado e domingo, porque escolher um dos dois seria palpite' do
      expect(resolver('fim de semana').datas).to eq([Date.new(2026, 8, 22), Date.new(2026, 8, 23)])
    end

    it 'num domingo devolve o próprio dia, que é o fim de semana em curso' do
      expect(resolver('final de semana', em: '2026-08-23 10:00:00').datas).to eq([Date.new(2026, 8, 23)])
    end
  end

  describe 'datas explícitas' do
    it 'resolve dia/mês/ano' do
      expect(resolver('25/12/2026').datas).to eq([Date.new(2026, 12, 25)])
    end

    it 'resolve dia/mês escolhendo a ocorrência que ainda não passou' do
      expect(resolver('2/1', em: '2026-12-28 09:00:00').datas).to eq([Date.new(2027, 1, 2)])
    end

    it 'resolve mês por extenso' do
      expect(resolver('25 de dezembro').datas).to eq([Date.new(2026, 12, 25)])
    end

    it 'resolve dia do mês corrente e pula pro mês seguinte quando já passou' do
      expect(resolver('dia 25').datas).to eq([Date.new(2026, 8, 25)])
      expect(resolver('dia 5').datas).to eq([Date.new(2026, 9, 5)])
    end

    it 'não reconhece data que não existe no calendário' do
      expect(resolver('31/02')).not_to be_reconhecida
    end
  end

  # O coração do contrato: o que não dá pra resolver volta como não resolvido, de forma que quem
  # chama seja obrigado a tratar. Nada aqui pode virar "hoje".
  describe 'o que não é resolvível' do
    ['', nil, '   ', 'semana que vem', 'no feriado', 'qualquer dia desses', 'quando der'].each do |expressao|
      it "não resolve #{expressao.inspect} e não cai em hoje" do
        resultado = resolver(expressao)

        expect(resultado).not_to be_reconhecida
        expect(resultado.datas).to be_empty
      end
    end
  end

  describe 'fuso da unidade' do
    it 'resolve o dia no fuso pedido, e não no do servidor' do
      # 2026-08-20 01:30 UTC ainda é dia 19 em Cuiabá (UTC-4).
      utc = ActiveSupport::TimeZone['UTC'].parse('2026-08-20 01:30:00')
      resultado = travel_to(utc) { described_class.resolver('hoje', zona) }

      expect(resultado.datas).to eq([Date.new(2026, 8, 19)])
    end
  end
end
