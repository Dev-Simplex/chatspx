require 'rails_helper'

# Duas coisas que estes exemplos protegem, e que valem mais que o formato do texto:
#   1. conta sem unidade não muda de comportamento — a tool nem entra no toolset (active? false);
#   2. ausência e "não entendi a data" saem EXPLÍCITAS, porque guarda que devolve só um código o
#      agente ignora — foi assim que uma IA seguiu qualificando o cliente até ele descobrir no
#      fim que não havia loja.
RSpec.describe Captain::Tools::BuscarUnidadesTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:zona) { ActiveSupport::TimeZone['America/Cuiaba'] }

  # 2026-08-19 é quarta-feira; 22 é sábado e 23 é domingo.
  def em_quarta(&)
    travel_to(zona.parse('2026-08-19 14:30:00'), &)
  end

  def unidade_com_grade(cidade: 'Cuiabá', **attrs)
    unidade = create(:spx_unidade, account: account, cidade: cidade, **attrs)
    (1..5).each { |dia| create(:spx_unidade_horario, unidade: unidade, dia_semana: dia, abre: '08:00', fecha: '18:00') }
    create(:spx_unidade_horario, unidade: unidade, dia_semana: 6, abre: '08:00', fecha: '12:00')
    create(:spx_unidade_horario, unidade: unidade, dia_semana: 0, fechada: true, abre: nil, fecha: nil)
    unidade
  end

  describe '#active?' do
    it 'nega quando a conta não tem unidade — a tool nem entra no toolset' do
      expect(tool).not_to be_active
    end

    it 'nega quando a única unidade está desativada' do
      create(:spx_unidade, account: account, ativa: false)

      expect(tool).not_to be_active
    end

    it 'aceita quando a conta tem unidade ativa' do
      create(:spx_unidade, account: account)

      expect(tool).to be_active
    end

    it 'não enxerga unidade de outra conta' do
      create(:spx_unidade, account: create(:account))

      expect(tool).not_to be_active
    end
  end

  describe 'ausência explícita' do
    it 'diz que a conta não tem unidade, em vez de devolver lista vazia' do
      expect(tool.perform(tool_context)).to include('não tem unidade cadastrada')
    end

    it 'distingue cidade sem unidade de falha de consulta e manda avisar antes de continuar' do
      unidade_com_grade(cidade: 'Cuiabá')

      resposta = tool.perform(tool_context, cidade: 'Sinop')

      expect(resposta).to include('Não há unidade cadastrada em "Sinop"')
      expect(resposta).to include('não falha de consulta')
      expect(resposta).to include('ANTES de continuar')
      expect(resposta).to include('Cuiabá')
    end

    it 'anuncia falha de consulta sem deixar concluir que a unidade não existe' do
      unidade_com_grade
      allow(Spx::Unidade).to receive(:ativas).and_raise(ActiveRecord::StatementInvalid)

      expect(tool.perform(tool_context)).to include('falha de consulta, não ausência')
    end
  end

  describe 'filtro por cidade' do
    before { unidade_com_grade(cidade: 'Cuiabá', nome: 'Loja Centro') }

    it 'casa a cidade sem acento e sem caixa' do
      expect(tool.perform(tool_context, cidade: 'cuiaba')).to include('Loja Centro')
    end

    it 'casa quando a pessoa escreve a cidade com a UF junto' do
      expect(tool.perform(tool_context, cidade: 'Cuiabá MT')).to include('Loja Centro')
    end
  end

  describe 'resolução de data' do
    before { unidade_com_grade(nome: 'Loja Centro') }

    it 'resolve a expressão relativa e devolve o dia com a data absoluta' do
      resposta = em_quarta { tool.perform(tool_context, quando: 'amanhã') }

      expect(resposta).to include('Quinta-feira, 20/08/2026: aberta das 08:00 às 18:00')
    end

    it 'responde sobre o momento presente quando a pergunta é sobre agora' do
      resposta = em_quarta { tool.perform(tool_context, quando: 'agora') }

      expect(resposta).to include('Agora (14:30 no fuso da unidade): aberta')
    end

    it 'não cai em hoje quando não entende a expressão' do
      resposta = em_quarta { tool.perform(tool_context, quando: 'qualquer dia desses') }

      expect(resposta).to include('Não consegui transformar "qualquer dia desses" em data')
      expect(resposta).to include('NÃO trate como hoje')
      expect(resposta).not_to include('19/08/2026')
    end

    it 'mostra o horário habitual condensado quando nenhuma data foi pedida' do
      resposta = tool.perform(tool_context)

      expect(resposta).to include('Horário: seg a sex 08:00 às 18:00 · sáb 08:00 às 12:00 · dom fechada')
      expect(resposta).to include('Nenhuma data foi pedida')
    end
  end

  describe 'exceção aplicada' do
    let!(:unidade) { unidade_com_grade(nome: 'Loja Centro', etiquetas: ['MT']) }

    it 'aplica a exceção de etiqueta e diz por que aquele dia é diferente' do
      create(:spx_unidade_excecao, account: account, etiqueta: 'MT', motivo: 'campanha de aniversário',
                                   data_inicio: Date.new(2026, 8, 23), data_fim: Date.new(2026, 8, 23),
                                   abre: '09:00', fecha: '15:00')

      resposta = em_quarta { tool.perform(tool_context, quando: 'domingo') }

      expect(resposta).to include('Domingo, 23/08/2026: aberta das 09:00 às 15:00')
      expect(resposta).to include('campanha de aniversário')
    end

    it 'fecha o dia quando a exceção fecha, mesmo com horário padrão cadastrado' do
      create(:spx_unidade_excecao, account: account, unidade: unidade, fechada: true, motivo: 'feriado',
                                   data_inicio: Date.new(2026, 8, 20), data_fim: Date.new(2026, 8, 20))

      resposta = em_quarta { tool.perform(tool_context, quando: 'amanhã') }

      expect(resposta).to include('Quinta-feira, 20/08/2026: fechada (exceção nesta data: feriado)')
    end
  end

  describe 'honestidade sobre dado ausente' do
    it 'não afirma que fecha quando a unidade não tem grade cadastrada' do
      create(:spx_unidade, account: account, nome: 'Loja Nova')

      resposta = em_quarta { tool.perform(tool_context, quando: 'amanhã') }

      expect(resposta).to include('horário não cadastrado')
      expect(resposta).not_to include('fechada')
    end

    # Achado no smoke test da carga, não nos testes: a unidade "tinha grade", então o dia sem
    # linha nenhuma saía como fechado. Quem cadastra só os dias úteis não está dizendo que fecha
    # no sábado — está deixando o sábado sem informação.
    it 'não afirma que fecha no dia sem linha, mesmo com o resto da semana cadastrado' do
      unidade = create(:spx_unidade, account: account, nome: 'Loja Útil')
      (1..5).each { |dia| create(:spx_unidade_horario, unidade: unidade, dia_semana: dia, abre: '08:00', fecha: '18:00') }

      resposta = em_quarta { tool.perform(tool_context, quando: 'sábado') }

      expect(resposta).to include('Sábado, 22/08/2026: horário não cadastrado')
      expect(resposta).not_to include('fechada')
    end

    it 'separa dia sem linha de dia fechado no horário habitual' do
      unidade = create(:spx_unidade, account: account, nome: 'Loja Útil')
      (1..5).each { |dia| create(:spx_unidade_horario, unidade: unidade, dia_semana: dia, abre: '08:00', fecha: '18:00') }
      create(:spx_unidade_horario, unidade: unidade, dia_semana: 0, fechada: true, abre: nil, fecha: nil)

      resposta = tool.perform(tool_context)

      expect(resposta).to include('seg a sex 08:00 às 18:00 · sáb não cadastrado · dom fechada')
    end
  end

  describe 'volume' do
    it 'avisa quando corta a lista, em vez de truncar em silêncio' do
      (described_class::LIMITE_UNIDADES + 3).times { |i| create(:spx_unidade, account: account, nome: "Loja #{i}") }

      resposta = tool.perform(tool_context)

      expect(resposta).to include("#{described_class::LIMITE_UNIDADES + 3} de #{described_class::LIMITE_UNIDADES + 3}")
      expect(resposta).to include("Mostrando #{described_class::LIMITE_UNIDADES}")
    end
  end

  describe 'contrato com o registro de tools' do
    it 'é resolvida pelo id plural do tools.yml, que o classify singulariza' do
      expect(Captain::Assistant.resolve_tool_class('buscar_unidades')).to eq(described_class)
    end

    it 'está registrada e disponível para o agente' do
      expect(Captain::Assistant.built_in_tool_ids).to include('buscar_unidades')
    end
  end
end
