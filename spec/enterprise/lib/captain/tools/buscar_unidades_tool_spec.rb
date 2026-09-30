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

  # `Unit` ja nasce com a grade da semana no after_create, entao a grade do teste substitui a padrao
  # em vez de somar — o indice unico (unidade, dia) recusaria a segunda linha do mesmo dia.
  def unidade_com_grade(cidade: 'Cuiabá', **attrs)
    unidade = create(:unit, account: account, city: cidade, **attrs)
    unidade.working_hours.destroy_all
    (1..5).each do |dia|
      create(:unit_working_hour, unit: unidade, day_of_week: dia, open_hour: 8, open_minutes: 0, close_hour: 18, close_minutes: 0)
    end
    create(:unit_working_hour, unit: unidade, day_of_week: 6, open_hour: 8, open_minutes: 0, close_hour: 12, close_minutes: 0)
    create(:unit_working_hour, unit: unidade, day_of_week: 0, closed_all_day: true,
                               open_hour: nil, open_minutes: nil, close_hour: nil, close_minutes: nil)
    unidade.reload
  end

  describe '#active?' do
    it 'nega quando a conta não tem unidade — a tool nem entra no toolset' do
      expect(tool).not_to be_active
    end

    it 'nega quando a única unidade está desativada' do
      create(:unit, account: account, ativa: false)

      expect(tool).not_to be_active
    end

    it 'aceita quando a conta tem unidade ativa' do
      create(:unit, account: account)

      expect(tool).to be_active
    end

    it 'não enxerga unidade de outra conta' do
      create(:unit, account: create(:account))

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
      allow(Unit).to receive(:ativas).and_raise(ActiveRecord::StatementInvalid)

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
      create(:unit_exception, unit: unidade, name: 'campanha de aniversário', closed_all_day: false,
                              starts_on: Date.new(2026, 8, 23), ends_on: Date.new(2026, 8, 23),
                              open_hour: 9, open_minutes: 0, close_hour: 15, close_minutes: 0)

      resposta = em_quarta { tool.perform(tool_context, quando: 'domingo') }

      expect(resposta).to include('Domingo, 23/08/2026: aberta das 09:00 às 15:00')
      expect(resposta).to include('campanha de aniversário')
    end

    it 'fecha o dia quando a exceção fecha, mesmo com horário padrão cadastrado' do
      create(:unit_exception, unit: unidade, name: 'feriado', closed_all_day: true,
                              starts_on: Date.new(2026, 8, 20), ends_on: Date.new(2026, 8, 20))

      resposta = em_quarta { tool.perform(tool_context, quando: 'amanhã') }

      expect(resposta).to include('Quinta-feira, 20/08/2026: fechada (exceção nesta data: feriado)')
    end
  end

  describe 'honestidade sobre dado ausente' do
    it 'não afirma que fecha quando a unidade não tem grade cadastrada' do
      # `Unit` cria a semana inteira no after_create; para simular unidade SEM grade é preciso
      # limpar — e o caso continua valendo, porque apagar linha é possível na tela.
      unidade = create(:unit, account: account, nome: 'Loja Nova')
      unidade.working_hours.destroy_all

      resposta = em_quarta { tool.perform(tool_context, quando: 'amanhã') }

      expect(resposta).to include('horário não cadastrado')
      expect(resposta).not_to include('fechada')
    end

    # Achado no smoke test da carga, não nos testes: a unidade "tinha grade", então o dia sem
    # linha nenhuma saía como fechado. Quem cadastra só os dias úteis não está dizendo que fecha
    # no sábado — está deixando o sábado sem informação.
    it 'não afirma que fecha no dia sem linha, mesmo com o resto da semana cadastrado' do
      unidade = create(:unit, account: account, nome: 'Loja Útil')
      unidade.working_hours.destroy_all
      (1..5).each { |dia| create(:unit_working_hour, unit: unidade, day_of_week: dia) }

      resposta = em_quarta { tool.perform(tool_context, quando: 'sábado') }

      expect(resposta).to include('Sábado, 22/08/2026: horário não cadastrado')
      expect(resposta).not_to include('fechada')
    end

    it 'separa dia sem linha de dia fechado no horário habitual' do
      unidade = create(:unit, account: account, nome: 'Loja Útil')
      unidade.working_hours.destroy_all
      (1..5).each { |dia| create(:unit_working_hour, unit: unidade, day_of_week: dia) }
      create(:unit_working_hour, unit: unidade, day_of_week: 0, closed_all_day: true,
                                 open_hour: nil, open_minutes: nil, close_hour: nil, close_minutes: nil)

      resposta = tool.perform(tool_context)

      expect(resposta).to include('seg a sex 08:00 às 18:00 · sáb não cadastrado · dom fechada')
    end
  end

  describe 'volume' do
    it 'avisa quando corta a lista, em vez de truncar em silêncio' do
      (described_class::LIMITE_UNIDADES + 3).times { |i| create(:unit, account: account, nome: "Loja #{i}") }

      resposta = tool.perform(tool_context)

      expect(resposta).to include("#{described_class::LIMITE_UNIDADES + 3} de #{described_class::LIMITE_UNIDADES + 3}")
      expect(resposta).to include("Mostrando #{described_class::LIMITE_UNIDADES}")
    end
  end

  # Regra de 29/09: com a ferramenta de envio de contato armada, o número sai do cadastro pelo
  # sistema e não passa pela IA. Sem ela, o telefone continua aqui, senão a conta perde o contato.
  describe 'telefone da unidade' do
    before do
      create(:unit, account: account, nome: 'Loja Centro',
                    contacts: [{ 'label' => 'Comercial', 'phone' => '(66) 3531-7222' },
                               { 'label' => 'Suporte', 'phone' => '66 99635-0491' }])
    end

    it 'mostra o telefone como hoje quando a ferramenta de envio não está armada' do
      resposta = tool.perform(tool_context)

      expect(resposta).to include('Telefone: (66) 3531-7222')
    end

    it 'troca o número pelos rótulos quando a ferramenta de envio está armada' do
      assistant.update!(config: assistant.config.merge('tools' => %w[buscar_unidades enviar_contato_unidade]))

      resposta = tool.perform(tool_context)

      expect(resposta).not_to include('3531', '99635')
      expect(resposta).to include('"Comercial"', '"Suporte"', 'enviar_contato_unidade')
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

  # A distância só existe quando a pessoa MANDOU o pin. Não há geocoding aqui de propósito: a
  # conta da BigStore não tem chave do Google, e geocoding não avisa quando erra — devolve
  # homônimo (medido na Tozi: 26% dos bairros a mais de 3 km, um a 518 km).
  describe 'distância a partir do pin que a pessoa enviou' do
    let(:conversation) { create(:conversation, account: account) }
    let(:contexto) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

    def pin_da_pessoa(lat, lng)
      msg = create(:message, conversation: conversation, account: account, message_type: :incoming)
      msg.attachments.create!(account_id: account.id, file_type: :location,
                              coordinates_lat: lat, coordinates_long: lng)
    end

    before do
      unidade_com_grade(cidade: 'Sorriso', nome: 'Loja Sorriso', latitude: -12.545, longitude: -55.711)
      unidade_com_grade(cidade: 'Cuiabá', nome: 'Loja Cuiabá', latitude: -15.601, longitude: -56.098)
    end

    it 'não fala de distância quando a pessoa não mandou pin' do
      resposta = em_quarta { tool.perform(contexto) }

      expect(resposta).not_to include('Distância')
    end

    it 'ordena pela distância e informa quanto é, quando há pin' do
      pin_da_pessoa(-11.860, -55.502) # Sinop: perto de Sorriso, longe de Cuiabá
      resposta = em_quarta { tool.perform(contexto) }

      expect(resposta).to include('Distância')
      expect(resposta.index('Loja Sorriso')).to be < resposta.index('Loja Cuiabá')
    end

    # Sem coordenada a unidade vai pro FIM. Tratar distância desconhecida como zero colocaria a
    # loja errada em primeiro — a única resposta que esta ferramenta não pode dar.
    it 'joga para o fim a unidade sem coordenada, em vez de tratá-la como distância zero' do
      unidade_com_grade(cidade: 'Vera', nome: 'Loja Vera')
      pin_da_pessoa(-11.860, -55.502)
      resposta = em_quarta { tool.perform(contexto) }

      expect(resposta.index('Loja Vera')).to be > resposta.index('Loja Sorriso')
    end

    it 'aponta a mais próxima quando a cidade pedida não tem unidade' do
      pin_da_pessoa(-11.860, -55.502)
      resposta = em_quarta { tool.perform(contexto, cidade: 'Rondonópolis') }

      expect(resposta).to include('Não há unidade cadastrada')
      expect(resposta).to include('mais próxima é Loja Sorriso')
    end

    # Sem pin, convida a mandar a localização — mas só porque há unidade com coordenada. Prometer
    # cálculo que não dá pra fazer é a mesma classe de erro de inventar endereço.
    it 'convida a mandar a localização quando não tem pin mas dá pra calcular' do
      resposta = em_quarta { tool.perform(contexto, cidade: 'Rondonópolis') }

      expect(resposta).to include('envie a localização')
    end

    it 'não convida quando nenhuma unidade tem coordenada' do
      Unit.where(account_id: account.id).find_each { |u| u.update!(latitude: nil, longitude: nil) }
      resposta = em_quarta { tool.perform(contexto, cidade: 'Rondonópolis') }

      expect(resposta).not_to include('envie a localização')
    end
  end

  # O que a pessoa pergunta SEM citar data: "tem alguma coisa acontecendo aí?", "vocês vão ter
  # feirão?". Antes, nenhuma exceção era carregada quando não havia data pedida — um evento marcado
  # pra depois de amanhã só existia pro agente se o cliente por acaso perguntasse pelo dia exato.
  describe 'evento em curso ou próximo, sem data pedida' do
    let!(:unidade) { unidade_com_grade(nome: 'Loja Centro') }

    def evento!(**attrs)
      create(:unit_exception, unit: unidade, name: 'feirão de aniversário', category: :evento,
                              closed_all_day: false, starts_on: Date.new(2026, 8, 21),
                              ends_on: Date.new(2026, 8, 22), open_hour: 8, open_minutes: 0,
                              close_hour: 18, close_minutes: 0, **attrs)
    end

    it 'anuncia o evento sem que ninguém tenha pedido data' do
      evento!

      resposta = em_quarta { tool.perform(tool_context) }

      expect(resposta).to include('Evento na unidade: feirão de aniversário')
    end

    it 'diz os dias e o horário do evento' do
      evento!

      resposta = em_quarta { tool.perform(tool_context) }

      expect(resposta).to include('sex 21/08', 'sáb 22/08', 'das 08:00 às 18:00')
    end

    # O caso mais comum, e o que quase saiu sem resposta: o evento acontece e a loja abre como
    # sempre. Omitir o horário aqui faria a diferença entre "é no horário normal" e "não sei que
    # horas é" desaparecer bem na pergunta que a pessoa faz.
    it 'diz que é no horário de sempre quando o evento não tem horário próprio' do
      evento!(open_hour: nil, open_minutes: nil, close_hour: nil, close_minutes: nil)

      resposta = em_quarta { tool.perform(tool_context) }

      expect(resposta).to include('no horário de funcionamento de sempre')
    end

    it 'avisa quando o período fecha a unidade, em vez de só dar horário' do
      evento!(name: 'reforma da fachada', category: :manutencao, closed_all_day: true,
              open_hour: nil, open_minutes: nil, close_hour: nil, close_minutes: nil)

      resposta = em_quarta { tool.perform(tool_context) }

      expect(resposta).to include('Manutenção na unidade: reforma da fachada')
      expect(resposta).to include('unidade FECHADA nesse período')
    end

    # Feriado só muda horário, e a linha de horário já responde por ele. Anunciá-lo aqui encheria
    # toda consulta com calendário que ninguém perguntou.
    it 'NÃO anuncia feriado como evento' do
      evento!(name: 'feriado municipal', category: :feriado, closed_all_day: true,
              starts_on: Date.new(2026, 8, 21), ends_on: Date.new(2026, 8, 21),
              open_hour: nil, open_minutes: nil, close_hour: nil, close_minutes: nil)

      resposta = em_quarta { tool.perform(tool_context) }

      expect(resposta).not_to include('Evento na unidade')
    end

    it 'ignora evento fora da janela — agenda distante não é notícia de hoje' do
      evento!(starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 2))

      resposta = em_quarta { tool.perform(tool_context) }

      expect(resposta).not_to include('Evento na unidade')
    end

    it 'ignora evento que já passou' do
      evento!(starts_on: Date.new(2026, 8, 1), ends_on: Date.new(2026, 8, 2))

      resposta = em_quarta { tool.perform(tool_context) }

      expect(resposta).not_to include('Evento na unidade')
    end

    it 'não vaza evento de outra unidade da mesma conta' do
      outra = unidade_com_grade(nome: 'Loja Norte', cidade: 'Sinop')
      create(:unit_exception, unit: outra, name: 'evento da outra loja', category: :evento,
                              closed_all_day: false, starts_on: Date.new(2026, 8, 21),
                              ends_on: Date.new(2026, 8, 21), open_hour: 8, open_minutes: 0,
                              close_hour: 18, close_minutes: 0)

      resposta = em_quarta { tool.perform(tool_context, cidade: 'Cuiabá') }

      expect(resposta).not_to include('evento da outra loja')
    end
  end

  # As condições de atendimento da unidade — o que o time cadastra e a IA repassa como fato. Elas
  # já eram impressas; o que faltava era o time conseguir editá-las (ver units_controller).
  describe 'condições de atendimento' do
    it 'devolve cada condição como linha nomeada' do
      unidade_com_grade(nome: 'Loja Centro',
                        atributos: { 'retirada de chaves' => 'até as 16h30 nos dias úteis' })

      resposta = em_quarta { tool.perform(tool_context) }

      expect(resposta).to include('Retirada de chaves: até as 16h30 nos dias úteis')
    end
  end
end
