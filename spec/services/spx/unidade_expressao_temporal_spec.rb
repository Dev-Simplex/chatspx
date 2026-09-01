require 'rails_helper'

# O motivo de esta classe existir é tirar a conta de calendário do modelo de linguagem. Logo, o
# que estes exemplos guardam não é só "resolve amanhã": é que expressão NÃO resolvível volta
# marcada como não resolvida, e nunca vira "hoje" por omissão.
RSpec.describe Spx::UnidadeExpressaoTemporal do
  let(:zona) { ActiveSupport::TimeZone['America/Cuiaba'] }

  # 2026-08-19 é quarta-feira. 14:30 no fuso da unidade.
  def resolver(expressao, agora: '2026-08-19 14:30:00')
    travel_to(zona.parse(agora)) { described_class.resolver(expressao, zona) }
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
      expect(resolver('final de semana', agora: '2026-08-23 10:00:00').datas).to eq([Date.new(2026, 8, 23)])
    end
  end

  describe 'datas explícitas' do
    it 'resolve dia/mês/ano' do
      expect(resolver('25/12/2026').datas).to eq([Date.new(2026, 12, 25)])
    end

    it 'resolve dia/mês escolhendo a ocorrência que ainda não passou' do
      expect(resolver('2/1', agora: '2026-12-28 09:00:00').datas).to eq([Date.new(2027, 1, 2)])
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

  # Medido na prod da BigStore em 01/09/2026: "sem ser nesse, no outro sábado" devolvia o sábado
  # que a pessoa acabara de EXCLUIR, e devolvia marcado como reconhecido. O parser via a palavra
  # `sabado` e ignorava o resto. Errar assim é pior que não responder, porque nada acusa.
  describe 'modificador que muda o sentido e não é modelado' do
    ['sem ser nesse, no outro sábado', 'no outro sábado', 'sábado passado', 'antes do sábado',
     'depois do sábado', 'daqui a 2 semanas', 'na semana retrasada'].each do |expressao|
      it "recusa #{expressao.inspect} em vez de responder pelo dia errado" do
        resultado = resolver(expressao)

        expect(resultado).not_to be_reconhecida
        expect(resultado.datas).to be_empty
      end
    end

    # A recusa é por modificador NÃO modelado. "que vem"/"próximo" são modelados e seguem valendo,
    # e "depois de amanhã" não pode ser confundido com "depois do <dia>".
    # 19/08/2026 é quarta: o sábado seguinte é 22/08. O "+7" do qualificador só entra quando o dia
    # citado é o próprio dia de hoje — semântica que já existia e que esta mudança não toca.
    it 'não recusa o que já sabe resolver' do
      expect(resolver('sábado que vem').datas).to eq([Date.new(2026, 8, 22)])
      expect(resolver('depois de amanhã').datas).to eq([Date.new(2026, 8, 21)])
    end
  end

  # "Daqui meia hora" é pergunta de INSTANTE, não de dia: a resposta é hora contra faixa. Antes
  # caía na recusa, o que era honesto mas deixava a pessoa sem resposta para a pergunta mais
  # comum de quem já está a caminho da loja.
  describe 'deslocamento a partir de agora' do
    it 'resolve "daqui meia hora"' do
      resultado = resolver('daqui meia hora')

      expect(resultado.datas).to eq([Date.new(2026, 8, 19)])
      expect(resultado).to be_instante
      expect(resultado.instante.strftime('%H:%M')).to eq('15:00')
    end

    it 'resolve minutos, horas e quantidade escrita por extenso' do
      expect(resolver('daqui a 30 minutos').instante.strftime('%H:%M')).to eq('15:00')
      expect(resolver('em 1 hora').instante.strftime('%H:%M')).to eq('15:30')
      expect(resolver('daqui a duas horas').instante.strftime('%H:%M')).to eq('16:30')
    end

    # A data do instante não é necessariamente hoje: perto da meia-noite ela vira o dia seguinte,
    # e é o horário DESSE dia que precisa ser consultado.
    it 'atravessa a meia-noite e devolve a data do instante, não a de hoje' do
      resultado = resolver('daqui a 20 minutos', agora: '2026-08-19 23:50:00')

      expect(resultado.datas).to eq([Date.new(2026, 8, 20)])
      expect(resultado.instante.strftime('%H:%M')).to eq('00:10')
    end

    it 'exige a palavra da unidade, pra "em setembro" não virar deslocamento' do
      expect(resolver('em setembro')).not_to be_reconhecida
    end

    it 'não aceita "meia" sem ser de hora' do
      expect(resolver('daqui meia semana')).not_to be_reconhecida
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
