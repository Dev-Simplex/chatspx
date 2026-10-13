# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Concerns::Agentable do
  let(:dummy_class) do
    Class.new do
      include Concerns::Agentable

      # `assistant` e exigido por #prompt_cache_system_enabled? e por #time_awareness; sem
      # ele o dummy quebrava com NameError em todo #agent_instructions.
      attr_accessor :temperature, :account, :assistant

      def initialize(name: 'Test Agent', temperature: 0.8)
        @name = name
        @temperature = temperature
      end

      def self.name
        'DummyClass'
      end

      private

      def agent_name
        @name
      end

      def prompt_context
        { base_key: 'base_value' }
      end
    end
  end

  let(:dummy_instance) { dummy_class.new }
  let(:mock_agents_agent) { instance_double(Agents::Agent) }
  let(:mock_account) { double('Account', captain_assistant_model: 'gpt-4-turbo') }

  before do
    allow(Agents::Agent).to receive(:new).and_return(mock_agents_agent)
    allow(Captain::PromptRenderer).to receive(:render).and_return('rendered_template')
    dummy_instance.account = mock_account
  end

  describe '#agent' do
    it 'creates an Agents::Agent with correct parameters' do
      expect(Agents::Agent).to receive(:new).with(
        name: 'Test Agent',
        instructions: instance_of(Proc),
        tools: [],
        model: 'gpt-4-turbo',
        temperature: 0.8,
        response_schema: Captain::ResponseSchema
      )

      dummy_instance.agent
    end

    # `temperature.to_f || 0.7` era default MORTO (to_f nunca devolve nil), entao agente
    # sem temperatura configurada rodava em 0.0, deterministico, e nao no 0.7 pretendido.
    it 'falls back to the default temperature when it is missing' do
      dummy_instance.temperature = nil

      expect(Agents::Agent).to receive(:new).with(
        hash_including(temperature: 0.7)
      )

      dummy_instance.agent
    end

    it 'falls back to the default temperature when the config holds an empty string' do
      dummy_instance.temperature = ''

      expect(Agents::Agent).to receive(:new).with(
        hash_including(temperature: 0.7)
      )

      dummy_instance.agent
    end

    it 'keeps an explicit zero instead of replacing it with the default' do
      dummy_instance.temperature = 0

      expect(Agents::Agent).to receive(:new).with(
        hash_including(temperature: 0.0)
      )

      dummy_instance.agent
    end

    it 'converts temperature to float' do
      dummy_instance.temperature = '0.5'

      expect(Agents::Agent).to receive(:new).with(
        hash_including(temperature: 0.5)
      )

      dummy_instance.agent
    end
  end

  describe '#agent_instructions' do
    it 'calls Captain::PromptRenderer with base context' do
      expect(Captain::PromptRenderer).to receive(:render).with(
        'dummy_class',
        hash_including(base_key: 'base_value')
      )

      dummy_instance.agent_instructions
    end

    it 'merges context state when provided' do
      context_double = instance_double(Agents::RunContext,
                                       context: {
                                         state: {
                                           assistant_config: { 'feature_contact_attributes' => true },
                                           conversation: { id: 123 },
                                           contact: { name: 'John' }
                                         }
                                       })

      expected_context = {
        base_key: 'base_value',
        conversation: { id: 123 },
        contact: { name: 'John' },
        campaign: {}
      }

      expect(Captain::PromptRenderer).to receive(:render).with(
        'dummy_class',
        hash_including(expected_context)
      )

      dummy_instance.agent_instructions(context_double)
    end

    it 'merges campaign data from context state' do
      context_double = instance_double(Agents::RunContext,
                                       context: {
                                         state: {
                                           conversation: { id: 123 },
                                           contact: { name: 'John' },
                                           campaign: { id: 10, title: 'Summer Sale', message: 'Check it out' }
                                         }
                                       })

      expect(Captain::PromptRenderer).to receive(:render).with(
        'dummy_class',
        hash_including(
          campaign: { id: 10, title: 'Summer Sale', message: 'Check it out' }
        )
      )

      dummy_instance.agent_instructions(context_double)
    end

    it 'handles context without state' do
      context_double = instance_double(Agents::RunContext, context: {})

      expect(Captain::PromptRenderer).to receive(:render).with(
        'dummy_class',
        hash_including(
          base_key: 'base_value',
          conversation: {},
          contact: nil,
          campaign: {}
        )
      )

      dummy_instance.agent_instructions(context_double)
    end
  end

  describe '#template_name' do
    it 'returns underscored class name' do
      expect(dummy_instance.send(:template_name)).to eq('dummy_class')
    end
  end

  describe '#agent_tools' do
    it 'returns empty array by default' do
      expect(dummy_instance.send(:agent_tools)).to eq([])
    end
  end

  describe '#agent_model' do
    it 'returns value from account captain_assistant_model when present' do
      expect(dummy_instance.send(:agent_model)).to eq('gpt-4-turbo')
    end

    it 'returns default model when account is nil' do
      dummy_instance.account = nil

      expect(dummy_instance.send(:agent_model)).to eq('gpt-4.1')
    end

    it 'returns default model when captain_assistant_model is nil' do
      allow(mock_account).to receive(:captain_assistant_model).and_return(nil)

      expect(dummy_instance.send(:agent_model)).to eq('gpt-4.1')
    end
  end

  describe '#agent_response_schema' do
    it 'returns Captain::ResponseSchema' do
      expect(dummy_instance.send(:agent_response_schema)).to eq(Captain::ResponseSchema)
    end
  end

  describe 'required methods' do
    let(:incomplete_class) do
      Class.new do
        include Concerns::Agentable
      end
    end

    let(:incomplete_instance) { incomplete_class.new }

    describe '#agent_name' do
      it 'raises NotImplementedError when not implemented' do
        expect { incomplete_instance.send(:agent_name) }
          .to raise_error(NotImplementedError, /must implement agent_name/)
      end
    end

    describe '#prompt_context' do
      it 'raises NotImplementedError when not implemented' do
        expect { incomplete_instance.send(:prompt_context) }
          .to raise_error(NotImplementedError, /must implement prompt_context/)
      end
    end
  end
  # O gate da coleta de contato alternativo. O bloco vive no assistant.liquid, que e o molde de
  # TODOS os clientes — conduta nova nao pode nascer ligada pra ninguem. Sao TRES condicoes, e o
  # spec exige as tres: canal que nao retoma + conta que ligou + canal alternativo configurado.

  describe 'canal atual no prompt' do
    it 'repassa ao template o canal atual que veio no state' do
      canal = { 'tipo' => 'WhatsApp', 'caixa' => 'Linha da loja', 'papel' => 'Atendimento geral' }
      contexto = Struct.new(:context).new({ state: { canal_atual: canal } })

      expect(Captain::PromptRenderer).to receive(:render).with('dummy_class', hash_including(canal_atual: canal))

      dummy_instance.agent_instructions(contexto)
    end
  end

  describe 'contato alternativo no prompt' do
    let(:coleta_ligada) { { 'coleta_contato_alternativo' => { 'ativo' => true, 'canal' => 'WhatsApp' } } }

    # Captura o contexto entregue ao renderer, que e onde a variavel do gate aparece.
    def contexto_renderizado(state)
      capturado = nil
      allow(Captain::PromptRenderer).to receive(:render) do |_tpl, ctx|
        capturado ||= ctx
        'rendered_template'
      end
      contexto = Struct.new(:context).new({ state: state })
      dummy_instance.agent_instructions(contexto)
      capturado
    end

    it 'expoe o canal alternativo quando o canal nao retoma e a conta ligou' do
      ctx = contexto_renderizado({ assistant_config: coleta_ligada, canal_retoma: false,
                                   janela_horas_restantes: 6.5 })

      expect(ctx['contato_alternativo']).to eq('WhatsApp')
      expect(ctx['janela_horas_restantes']).to eq(6.5)
    end

    # A trava que impede a conduta de vazar pro WhatsApp e pros outros clientes.
    it 'NAO expoe nada em canal que retoma, mesmo com a conta ligada' do
      ctx = contexto_renderizado({ assistant_config: coleta_ligada, canal_retoma: true,
                                   janela_horas_restantes: 6.5 })

      expect(ctx['contato_alternativo']).to be_nil
      expect(ctx['janela_horas_restantes']).to be_nil
    end

    it 'NAO expoe nada quando a conta nao ligou a coleta' do
      ctx = contexto_renderizado({ assistant_config: {}, canal_retoma: false,
                                   janela_horas_restantes: 6.5 })

      expect(ctx['contato_alternativo']).to be_nil
      expect(ctx['janela_horas_restantes']).to be_nil
    end

    it 'NAO expoe nada com a coleta ligada mas sem canal alternativo definido' do
      ctx = contexto_renderizado({ assistant_config: { 'coleta_contato_alternativo' => { 'ativo' => true } },
                                   canal_retoma: false })

      expect(ctx['contato_alternativo']).to be_nil
    end

    # Canal que nao responde a `supports_reengagement?` chega sem a chave: o silencio nao pode
    # ligar conduta nova.
    it 'NAO expoe nada quando o state nem traz a informacao de canal' do
      ctx = contexto_renderizado({ assistant_config: coleta_ligada })

      expect(ctx['contato_alternativo']).to be_nil
    end
  end

  # A unidade (/units) e a fonte do horario quando a caixa tem uma: em 12/10/2026 (feriado,
  # segunda) a IA leu so o `business_hours` do assistente e confirmou retirada de chave as 10h.
  describe 'horario vindo da unidade da caixa' do
    let(:account) { create(:account) }
    let(:unidade) { create(:unit, account: account) }
    let(:inbox) { create(:inbox, account: account, unit: unidade) }
    let(:cuiaba) { ActiveSupport::TimeZone['America/Cuiaba'] }

    before do
      unidade.working_hours.where(day_of_week: 1..5).find_each do |dia|
        dia.update!(open_hour: 7, open_minutes: 30, close_hour: 17, close_minutes: 30,
                    break_start_hour: 11, break_start_minutes: 30, break_end_hour: 13, break_end_minutes: 30)
      end
      unidade.working_hours.find_by(day_of_week: 6)
             .update!(closed_all_day: false, open_hour: 9, open_minutes: 0, close_hour: 11, close_minutes: 30)
      create(:unit_exception, unit: unidade, name: 'Nossa Senhora Aparecida', starts_on: Date.new(2026, 10, 12),
                              frequency: :anual, closed_all_day: true)
    end

    def contexto_em(instante, inbox_id: inbox.id)
      capturado = nil
      allow(Captain::PromptRenderer).to receive(:render) do |_tpl, ctx|
        capturado ||= ctx
        'rendered_template'
      end
      travel_to(cuiaba.parse(instante)) do
        dummy_instance.agent_instructions(Struct.new(:context).new({ state: { conversation: { inbox_id: inbox_id } } }))
      end
      capturado
    end

    it 'diz que esta fechado no feriado e que volta no proximo dia util' do
      ctx = contexto_em('2026-10-12 08:41')

      expect(ctx['business_status']).to start_with('fechado hoje (Nossa Senhora Aparecida); os atendentes voltam amanhã')
      expect(ctx['business_status']).to include('terça-feira, 13/10) às 07:30')
      expect(ctx['business_status']).not_to include('dentro do horário')
    end

    it 'no sabado antes do feriado, pula a segunda e avisa o feriado' do
      ctx = contexto_em('2026-10-10 14:10')

      expect(ctx['business_status']).to include('os atendentes só voltam terça-feira, 13/10, às 07:30')
      expect(ctx['business_status']).to include('segunda-feira, 12/10: fechado o dia todo (Nossa Senhora Aparecida)')
    end

    it 'num dia aberto, avisa do feriado que vem pela frente' do
      ctx = contexto_em('2026-10-09 10:00')

      expect(ctx['business_status']).to start_with('dentro do horário comercial')
      expect(ctx['business_status']).to include('segunda-feira, 12/10: fechado o dia todo')
    end

    it 'na pausa do almoco, volta hoje' do
      ctx = contexto_em('2026-10-13 12:00')

      expect(ctx['business_status']).to include('voltam HOJE às 13:30')
    end

    it 'monta o horario de funcionamento a partir da grade da unidade' do
      ctx = contexto_em('2026-10-13 12:00')

      expect(ctx['business_hours_text'])
        .to eq('segunda a sexta, das 7h30 às 11h30 e das 13h30 às 17h30; sábado, das 9h às 11h30')
    end

    it 'sem unidade na conta, segue o business_hours do assistente' do
      outra = create(:inbox)
      dummy_instance.assistant = instance_double(Captain::Assistant, account: nil, behavior: {
                                          'business_hours' => {
                                            'enabled' => true, 'timezone' => 'America/Cuiaba',
                                            'schedule' => [{ 'day' => 1, 'ranges' => [{ 'start' => '07:30', 'end' => '17:30' }] }]
                                          }
                                        })

      ctx = contexto_em('2026-10-12 08:41', inbox_id: outra.id)

      expect(ctx['business_status']).to start_with('dentro do horário comercial')
      expect(ctx['business_hours_text']).to eq('segunda, das 7h30 às 17h30')
    end
  end
end
