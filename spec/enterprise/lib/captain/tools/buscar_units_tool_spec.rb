require 'rails_helper'

RSpec.describe Captain::Tools::BuscarUnitsTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }

  def criar_unidade!(nome: 'Matriz', cidade: 'Sinop', ativa: true, **attrs)
    Unit.create!({ account: account, name: nome, city: cidade, state: 'MT', active: ativa,
                   timezone: 'America/Cuiaba', address: 'Av. das Figueiras, 1646 - Centro',
                   phone: '+55 66 3531-7222' }.merge(attrs))
  end

  # Gate multi-tenant: conta sem unidade não muda de comportamento — a tool nem entra no toolset.
  describe '#active?' do
    it 'é falso quando a conta não tem unidade' do
      expect(tool.active?).to be false
    end

    it 'é falso quando só há unidade inativa' do
      criar_unidade!(ativa: false)

      expect(tool.active?).to be false
    end

    it 'é verdadeiro com unidade ativa' do
      criar_unidade!

      expect(tool.active?).to be true
    end
  end

  describe '#perform' do
    it 'diz que não há cadastro em vez de devolver vazio' do
      expect(tool.perform(nil)).to include('não tem unidade cadastrada')
    end

    it 'devolve endereço e telefone da unidade' do
      criar_unidade!

      resultado = tool.perform(nil)

      expect(resultado).to include('Av. das Figueiras, 1646', '+55 66 3531-7222', 'Matriz')
    end

    it 'sem data pedida, devolve o horário habitual e diz que é o habitual' do
      criar_unidade!

      resultado = tool.perform(nil)

      expect(resultado).to include('Horário:', 'horário habitual')
    end

    # A conta de calendário é feita em Ruby — é o ponto do desenho, não um detalhe.
    it 'resolve a expressão de tempo e responde pelo dia' do
      unidade = criar_unidade!
      alvo = Date.new(2026, 9, 10)
      unidade.exceptions.create!(name: 'Feriado municipal', starts_on: alvo, closed_all_day: true,
                                 frequency: :nao_repete, repeat_interval: 1, category: :feriado,
                                 weekdays: [], week_positions: [], month_days: [])
      allow(Spx::UnidadeExpressaoTemporal).to receive(:resolver)
        .and_return(Spx::UnidadeExpressaoTemporal::Resultado.new(datas: [alvo], instante: nil, reconhecida: true))

      resultado = tool.perform(nil, quando: 'dia 10')

      expect(resultado).to include('10/09/2026', 'fechada', 'Feriado municipal')
    end

    # Expressão não resolvível NUNCA cai em "hoje" por omissão — silêncio que vira palpite é a
    # falha que esta base já pagou caro.
    it 'quando não entende a expressão, diz que devolveu o horário habitual' do
      criar_unidade!
      allow(Spx::UnidadeExpressaoTemporal).to receive(:resolver)
        .and_return(Spx::UnidadeExpressaoTemporal::Resultado.new(datas: [], instante: nil, reconhecida: false))

      resultado = tool.perform(nil, quando: 'sei lá quando')

      expect(resultado).to include('horário habitual')
      expect(resultado).not_to include('fechada em')
    end

    context 'when the account has units in more than one city' do
      before do
        criar_unidade!(nome: 'Matriz', cidade: 'Sinop')
        criar_unidade!(nome: 'Filial', cidade: 'Sorriso')
      end

      it 'filtra pela cidade citada' do
        resultado = tool.perform(nil, cidade: 'Sorriso')

        expect(resultado).to include('Filial')
        expect(resultado).not_to include('Matriz')
      end

      it 'ignora acento e caixa' do
        expect(tool.perform(nil, cidade: 'SORRISO')).to include('Filial')
      end

      # "Não temos unidade nessa cidade" é diferente de "não temos unidade nenhuma", e a segunda
      # seria mentira.
      it 'sem unidade na cidade, diz onde existe' do
        resultado = tool.perform(nil, cidade: 'Cuiabá')

        expect(resultado).to include('Nenhuma unidade em Cuiabá', 'Sinop', 'Sorriso')
      end
    end

    it 'ignora unidade inativa' do
      criar_unidade!(nome: 'Fechada', ativa: false)

      expect(tool.perform(nil)).to include('não tem unidade cadastrada')
    end

    # Falha de consulta não pode virar "a unidade não existe".
    it 'distingue falha de ausência' do
      criar_unidade!
      allow(Unit).to receive(:where).and_raise(StandardError, 'boom')

      expect(tool.perform(nil)).to include('falha de consulta')
    end
  end
end
