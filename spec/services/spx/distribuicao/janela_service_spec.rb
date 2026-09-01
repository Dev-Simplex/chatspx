require 'rails_helper'

# O relógio do SLA existe porque contar na parede pune quem estava fora do expediente: um lead
# designado 18h50 de sexta estouraria um SLA de 30 min com o corretor em casa.
#
# Este serviço chegou pelo PR #67 sem nenhum teste, e é ele que decide se um lead vence. Os
# exemplos abaixo cobrem o que a auditoria de 26/08 teve de verificar lendo código, mais a
# cobertura herdada do RelogioComercial, que foi removido quando os dois relógios viraram um.
RSpec.describe Spx::Distribuicao::JanelaService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:policy) { create(:distribuicao_policy, account: account, team: team) }

  # Mesmo fuso do app para que os horários escritos aqui signifiquem o que dizem: o objeto de
  # teste é o calendário, não a conversão de fuso.
  def expediente_da_inbox(dias, abre: 9, fecha: 17)
    inbox.update!(working_hours_enabled: true, timezone: Time.zone.name)
    inbox.working_hours.destroy_all
    (0..6).each do |wday|
      inbox.working_hours.create!(
        day_of_week: wday, closed_all_day: dias.exclude?(wday),
        open_hour: abre, open_minutes: 0, close_hour: fecha, close_minutes: 0
      )
    end
  end

  def horario_da_policy(dias, abre: '09:00', fecha: '17:00')
    schedule = dias.map { |d| { 'day' => d, 'ranges' => [{ 'start' => abre, 'end' => fecha }] } }
    policy.update!(horario: { 'timezone' => Time.zone.name, 'schedule' => schedule })
  end

  describe 'de onde vem o expediente' do
    it 'prefere o horario da politica ao da caixa' do
      expediente_da_inbox([1, 2, 3, 4, 5], abre: 8, fecha: 18)
      horario_da_policy([3], abre: '14:00', fecha: '15:00') # quarta, 1h só

      inicio = Time.zone.parse('2026-08-19 14:00') # quarta
      prazo = described_class.new(policy: policy, inbox: inbox).prazo(inicio, 30)

      expect(prazo).to eq(Time.zone.parse('2026-08-19 14:30'))
    end

    it 'cai no expediente da caixa quando a politica nao tem horario' do
      expediente_da_inbox([3], abre: 9, fecha: 17)

      inicio = Time.zone.parse('2026-08-19 08:00') # quarta, antes de abrir
      prazo = described_class.new(policy: policy, inbox: inbox).prazo(inicio, 30)

      expect(prazo).to eq(Time.zone.parse('2026-08-19 09:30'))
    end

    # Desligado, o working_hours carrega os defaults de fábrica do Chatwoot: usá-los seria
    # inventar um expediente que ninguém configurou.
    it 'ignora a caixa com working_hours_enabled desligado' do
      expediente_da_inbox([1, 2, 3, 4, 5])
      inbox.update!(working_hours_enabled: false)

      servico = described_class.new(policy: policy, inbox: inbox, sem_agenda: :parede)
      inicio = Time.zone.parse('2026-08-19 03:00') # madrugada

      expect(servico.prazo(inicio, 90)).to eq(inicio + 90.minutes)
    end
  end

  # A distinção que o spec do RepasseService pegou: "configurado e sempre fechado" NÃO é a mesma
  # coisa que "não configurado". O primeiro é uma resposta ("este time não atende"); o segundo é
  # ausência de resposta, e é só nele que o `sem_agenda` manda.
  describe 'sem faixa aberta' do
    it 'nunca vence quando o expediente existe mas todos os dias estao fechados' do
      expediente_da_inbox([]) # todos closed_all_day

      %i[parede nao_vence].each do |modo|
        servico = described_class.new(policy: policy, inbox: inbox, sem_agenda: modo)
        expect(servico.prazo(Time.zone.parse('2026-08-19 10:00'), 30)).to be_nil
      end
    end

    it 'idem quando a politica declara um schedule sem nenhuma faixa valida' do
      policy.update!(horario: { 'schedule' => [{ 'day' => 3, 'ranges' => [{ 'start' => '17:00', 'end' => '09:00' }] }] })

      servico = described_class.new(policy: policy, inbox: inbox, sem_agenda: :parede)
      expect(servico.prazo(Time.zone.parse('2026-08-19 10:00'), 30)).to be_nil
    end
  end

  describe 'sem expediente configurado em lugar nenhum' do
    # O default. Um time sobre o qual não sabemos nada não deve ter lead circulando de madrugada.
    it 'nao vence com sem_agenda: :nao_vence (default, caminho assignee)' do
      servico = described_class.new(policy: policy, inbox: inbox)

      expect(servico.prazo(Time.zone.parse('2026-08-19 03:00'), 30)).to be_nil
      expect(servico.vencido?(3.days.ago, 30)).to be(false)
    end

    # Preserva o comportamento de vendas em produção desde 19/08. Sem isto a unificação dos dois
    # relógios desligaria o repasse em silêncio em todo time sem expediente configurado.
    it 'corre no relogio de parede com sem_agenda: :parede (caminho designacao)' do
      inicio = Time.zone.parse('2026-08-19 03:00')
      servico = described_class.new(policy: policy, inbox: inbox, sem_agenda: :parede)

      expect(servico.prazo(inicio, 90)).to eq(inicio + 90.minutes)
      expect(servico.vencido?(3.days.ago, 30)).to be(true)
    end

    it 'recusa um sem_agenda que nao existe em vez de escolher um por conta propria' do
      expect { described_class.new(policy: policy, sem_agenda: :talvez) }.to raise_error(ArgumentError)
    end
  end

  # A coluna era gravada pela tela e não era lida por ninguém antes do PR #67: um checkbox que
  # não fazia nada.
  describe 'sla_respeita_horario desligado' do
    before { policy.update!(sla_respeita_horario: false) }

    it 'conta na parede mesmo com expediente configurado' do
      horario_da_policy([1, 2, 3, 4, 5])
      inicio = Time.zone.parse('2026-08-22 23:00') # sábado, fora de qualquer expediente

      expect(described_class.new(policy: policy, inbox: inbox).prazo(inicio, 60))
        .to eq(inicio + 60.minutes)
    end

    # Quem pediu 24/7 explicitamente não deve ser barrado por não ter configurado expediente.
    it 'conta na parede mesmo sem expediente nenhum, e mesmo com o default fail-closed' do
      inicio = Time.zone.parse('2026-08-19 03:00')

      expect(described_class.new(policy: policy, inbox: inbox).prazo(inicio, 45))
        .to eq(inicio + 45.minutes)
    end
  end

  describe 'contagem dentro do expediente' do
    before { horario_da_policy([1, 2, 3, 4, 5]) } # seg..sex 9h-17h

    it 'nao comeca a contar antes de abrir' do
      inicio = Time.zone.parse('2026-08-19 07:00') # quarta, 2h antes de abrir

      expect(described_class.new(policy: policy).prazo(inicio, 30))
        .to eq(Time.zone.parse('2026-08-19 09:30'))
    end

    it 'atravessa a noite e termina no dia seguinte' do
      inicio = Time.zone.parse('2026-08-19 16:30') # quarta, 30 min antes de fechar

      expect(described_class.new(policy: policy).prazo(inicio, 60))
        .to eq(Time.zone.parse('2026-08-20 09:30'))
    end

    it 'pula o fim de semana fechado' do
      inicio = Time.zone.parse('2026-08-21 16:30') # sexta, 30 min antes de fechar

      expect(described_class.new(policy: policy).prazo(inicio, 60))
        .to eq(Time.zone.parse('2026-08-24 09:30')) # segunda
    end

    it 'e falso enquanto o prazo nao correu em expediente' do
      inicio = Time.zone.parse('2026-08-21 16:50') # sexta, 10 min antes de fechar
      servico = described_class.new(policy: policy)

      expect(servico.vencido?(inicio, 30, Time.zone.parse('2026-08-23 12:00'))).to be(false) # domingo
      expect(servico.vencido?(inicio, 30, Time.zone.parse('2026-08-24 09:25'))).to be(true)  # segunda
    end
  end

  describe '#horario_definido?' do
    it 'e falso sem fonte nenhuma' do
      expect(described_class.new(policy: policy, inbox: inbox).horario_definido?).to be(false)
    end

    it 'e verdadeiro com horario na politica' do
      horario_da_policy([1])
      expect(described_class.new(policy: policy).horario_definido?).to be(true)
    end
  end
end
