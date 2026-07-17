require 'rails_helper'

describe AutomationRuleListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:created_event) do
    Events::Base.new('conversation_created', Time.zone.now, { conversation: conversation, changed_attributes: {} })
  end

  def event_flow(action_name = 'add_label', params = ['auto'])
    node = { 'id' => 'n1', 'type' => 'action', 'action_name' => action_name, 'action_params' => params }
    create(:flow, account: account, trigger_type: :conversation_event,
                  trigger_config: { 'event_name' => 'conversation_created', 'conditions' => [] },
                  definition: { 'nodes' => [node], 'edges' => [] })
  end

  def enable_flows_engine
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
  end

  before { Rails.cache.clear }

  describe 'engine gating by the `flows` feature flag' do
    context 'when the flows feature is enabled' do
      before do
        event_flow
        enable_flows_engine
      end

      it 'runs the Flow engine and the Flow acts on the conversation' do
        listener.conversation_created(created_event)
        expect(conversation.reload.label_list).to include('auto')
      end

      it 'does not run the legacy AutomationRule engine (R-1: no double execution)' do
        create(:automation_rule, event_name: 'conversation_created', account: account)
        allow(AutomationRules::ActionService).to receive(:new)
        listener.conversation_created(created_event)
        expect(AutomationRules::ActionService).not_to have_received(:new)
      end
    end

    context 'when the flows feature is disabled (default)' do
      before { event_flow }

      it 'does not run the Flow engine' do
        allow(Flows::RunnerService).to receive(:new)
        listener.conversation_created(created_event)
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'still runs the legacy AutomationRule engine' do
        create(:automation_rule, event_name: 'conversation_created', account: account, conditions: [])
        allow(AutomationRules::ActionService).to receive(:new).and_return(instance_double(AutomationRules::ActionService, perform: nil))
        listener.conversation_created(created_event)
        expect(AutomationRules::ActionService).to have_received(:new)
      end
    end

    # Fix da revisão adversarial: flag ON sem flows (backfill não rodado) NÃO pode silenciar
    # as automations — cai de volta no motor legado até existirem flows.
    context 'when flows is enabled but no flows exist yet (pre-backfill)' do
      before { enable_flows_engine }

      it 'falls back to the legacy engine instead of silencing automations' do
        create(:automation_rule, event_name: 'conversation_created', account: account, conditions: [])
        allow(AutomationRules::ActionService).to receive(:new).and_return(instance_double(AutomationRules::ActionService, perform: nil))
        allow(Flows::RunnerService).to receive(:new)
        listener.conversation_created(created_event)
        expect(AutomationRules::ActionService).to have_received(:new)
        expect(Flows::RunnerService).not_to have_received(:new)
      end
    end
  end

  describe 'anti-loop for engine-generated messages' do
    before { enable_flows_engine }

    it 'ignores message_created events carrying a flow_id (no re-trigger)' do
      allow(Flows::RunnerService).to receive(:new)
      message = create(:message, conversation: conversation, account: account, content_attributes: { 'flow_id' => 42 })
      event = Events::Base.new('message_created', Time.zone.now, { message: message })
      listener.message_created(event)
      expect(Flows::RunnerService).not_to have_received(:new)
    end
  end

  describe 'keyword trigger' do
    before { enable_flows_engine }

    after { Current.reset }

    def keyword_flow(keywords, match: 'contains', active: true, label: 'kw-hit')
      node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [label] }
      create(:flow, account: account, active: active, trigger_type: :keyword,
                    trigger_config: { 'keywords' => keywords, 'match' => match },
                    definition: { 'nodes' => [node], 'edges' => [] })
    end

    def deliver(message)
      listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message }))
    end

    def incoming(content)
      create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :incoming, content: content)
    end

    context 'with contains match (default)' do
      before { keyword_flow(%w[suporte ajuda]) }

      it 'fires when the message contains a keyword' do
        deliver(incoming('preciso de suporte agora'))
        expect(conversation.reload.label_list).to include('kw-hit')
      end

      it 'does not fire when no keyword is present' do
        deliver(incoming('bom dia'))
        expect(conversation.reload.label_list).not_to include('kw-hit')
      end

      it 'matches case-insensitively' do
        deliver(incoming('QUERO AJUDA'))
        expect(conversation.reload.label_list).to include('kw-hit')
      end

      it 'matches accent-insensitively (keyword accented, message not)' do
        keyword_flow(['horário'], label: 'accent-hit')
        deliver(incoming('qual o horario de atendimento?'))
        expect(conversation.reload.label_list).to include('accent-hit')
      end

      it 'matches accent-insensitively (message accented, keyword not)' do
        keyword_flow(['horario'], label: 'accent-hit')
        deliver(incoming('qual o horário?'))
        expect(conversation.reload.label_list).to include('accent-hit')
      end
    end

    context 'with exact match' do
      before { keyword_flow(%w[oi], match: 'exact') }

      it 'fires when the whole message equals a keyword (normalized)' do
        deliver(incoming('Oi'))
        expect(conversation.reload.label_list).to include('kw-hit')
      end

      it 'does not fire when the keyword is only a substring of the message' do
        deliver(incoming('oi, tudo bem?'))
        expect(conversation.reload.label_list).not_to include('kw-hit')
      end
    end

    context 'with ineligible messages' do
      before { keyword_flow(%w[suporte]) }

      it 'ignores outgoing messages' do
        allow(Flows::RunnerService).to receive(:new)
        deliver(create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :outgoing, content: 'suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'ignores private notes' do
        allow(Flows::RunnerService).to receive(:new)
        deliver(create(:message, conversation: conversation, inbox: inbox, account: account,
                                 message_type: :outgoing, private: true, content: 'suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'ignores activity messages' do
        allow(Flows::RunnerService).to receive(:new)
        deliver(create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :activity, content: 'suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end
    end

    context 'with guards' do
      it 'does not re-trigger on a message the flow itself generated (flow_id anti-loop)' do
        keyword_flow(%w[suporte])
        allow(Flows::RunnerService).to receive(:new)
        deliver(create(:message, conversation: conversation, inbox: inbox, account: account,
                                 message_type: :incoming, content: 'suporte', content_attributes: { 'flow_id' => 7 }))
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'does not fire an inactive keyword flow' do
        keyword_flow(%w[suporte], active: false)
        allow(Flows::RunnerService).to receive(:new)
        deliver(incoming('quero suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'does not fire when the keyword list is empty' do
        keyword_flow([])
        allow(Flows::RunnerService).to receive(:new)
        deliver(incoming('quero suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end

      it 'does not fire when the flows engine is disabled for the account' do
        account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => false))
        keyword_flow(%w[suporte])
        allow(Flows::RunnerService).to receive(:new)
        deliver(incoming('quero suporte'))
        expect(Flows::RunnerService).not_to have_received(:new)
      end
    end
  end

  # Filtro de DIREÇÃO do gatilho (trigger_config['direction'] = inbound|outbound|both). Resolve o
  # bug real: uma regra "ao criar conversa → atribuir ao time X" também disparava quando o AGENTE
  # iniciava a conversa (saída). Critério: para eventos de conversa, a direção é a da 1ª mensagem
  # não-activity da conversa (incoming = entrada, senão saída); para message_created/keyword é a da
  # própria mensagem. Ver AutomationRuleListener#conversation_direction / #message_direction.
  describe 'trigger direction filter' do
    before { enable_flows_engine }

    after { Current.reset }

    # Flow por-evento com direção em trigger_config E no nó `trigger` (como o canvas persiste).
    def directional_flow(direction, event_name: 'conversation_created', label: 'dir-hit')
      action = { 'id' => 'a1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [label] }
      trigger = { 'id' => 't1', 'type' => 'trigger', 'direction' => direction }
      create(:flow, account: account, trigger_type: :conversation_event,
                    trigger_config: { 'event_name' => event_name, 'conditions' => [], 'direction' => direction },
                    definition: { 'nodes' => [trigger, action], 'edges' => [{ 'from' => 't1', 'to' => 'a1' }] })
    end

    def add_message(type, content: 'oi')
      create(:message, conversation: conversation, inbox: inbox, account: account, message_type: type, content: content)
    end

    def fire_created
      listener.conversation_created(created_event)
    end

    context 'when the trigger is a conversation event (direction from the first message)' do
      context "when the flow wants 'inbound'" do
        before { directional_flow('inbound') }

        it 'fires when the contact started the conversation (first message incoming)' do
          add_message(:incoming)
          fire_created
          expect(conversation.reload.label_list).to include('dir-hit')
        end

        it 'does NOT fire when an agent started the conversation (first message outgoing) — the reported bug' do
          add_message(:outgoing)
          fire_created
          expect(conversation.reload.label_list).not_to include('dir-hit')
        end
      end

      context "when the flow wants 'outbound'" do
        before { directional_flow('outbound') }

        it 'fires when an agent started the conversation (first message outgoing)' do
          add_message(:outgoing)
          fire_created
          expect(conversation.reload.label_list).to include('dir-hit')
        end

        it 'does NOT fire on an inbound conversation (first message incoming)' do
          add_message(:incoming)
          fire_created
          expect(conversation.reload.label_list).not_to include('dir-hit')
        end
      end

      context "when the flow wants 'both' (explicit)" do
        before { directional_flow('both') }

        it 'fires on an outbound conversation' do
          add_message(:outgoing)
          fire_created
          expect(conversation.reload.label_list).to include('dir-hit')
        end

        it 'fires on an inbound conversation' do
          add_message(:incoming)
          fire_created
          expect(conversation.reload.label_list).to include('dir-hit')
        end
      end

      # Não-regressão: flows legados não têm `direction` — devem disparar como antes (== 'both').
      context 'when direction is absent (legacy flows)' do
        it 'fires regardless of direction, as before' do
          event_flow
          add_message(:outgoing)
          fire_created
          expect(conversation.reload.label_list).to include('auto')
        end
      end

      context 'when the conversation has no directional message yet' do
        before { directional_flow('inbound') }

        it "treats it as inbound (fail-open) so an 'inbound' flow still fires" do
          fire_created
          expect(conversation.reload.label_list).to include('dir-hit')
        end
      end

      # Fallback self-contained: mesmo se a projeção do FlowCanvasView ainda não copiar `direction`
      # para trigger_config, o backend lê a direção do próprio nó `trigger` da definition.
      context 'when direction lives only on the trigger node (trigger_config not yet projected)' do
        it 'reads the fallback from the definition and still filters out the outbound conversation' do
          action = { 'id' => 'a1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['node-dir'] }
          trigger = { 'id' => 't1', 'type' => 'trigger', 'direction' => 'inbound' }
          create(:flow, account: account, trigger_type: :conversation_event,
                        trigger_config: { 'event_name' => 'conversation_created', 'conditions' => [] },
                        definition: { 'nodes' => [trigger, action], 'edges' => [{ 'from' => 't1', 'to' => 'a1' }] })
          add_message(:outgoing)
          fire_created
          expect(conversation.reload.label_list).not_to include('node-dir')
        end
      end
    end

    # Bug real (AGN, conta 1, conversa display 110): conversa nascida INCOMING ha 9 dias e resolvida;
    # a AGENTE reabre o assunto com o template `iniciar_conversa` (outgoing) e SO ENTAO o contato
    # responde "Boa tarde" — reabrindo a conversa e disparando conversation_opened. A direcao lia a
    # 1a mensagem da CONVERSA (a incoming de 9 dias atras) e concluia 'inbound', disparando um flow
    # "Entrada (contato inicia)" num ciclo que quem iniciou foi a agente. A pergunta certa e "quem
    # iniciou o CICLO ATUAL?" — o ciclo que comeca na ultima resolucao.
    context 'when the conversation was reopened (conversation_opened)' do
      def fire_opened
        listener.conversation_opened(
          Events::Base.new('conversation_opened', Time.zone.now,
                           { conversation: conversation, changed_attributes: { status: %w[Resolved Open] } })
        )
      end

      # A resolucao so existe como ReportingEvent 'conversation_resolved' (nao ha coluna resolved_at).
      def resolve_at(time)
        create(:reporting_event, name: 'conversation_resolved', account: account, inbox: inbox,
                                 conversation: conversation, event_start_time: time, event_end_time: time)
      end

      def add_message_at(type, time, content: 'oi', **attrs)
        create(:message, conversation: conversation, inbox: inbox, account: account,
                         message_type: type, content: content, created_at: time, **attrs)
      end

      # Mensagem de SISTEMA (outgoing): a pergunta do NPS, o agradecimento do NPS, a fala de um flow
      # ou de uma automation rule. Marcada pelos mesmos content_attributes que o listener já usa.
      def add_system_message_at(time, content_attributes, content: 'msg do sistema')
        add_message_at(:outgoing, time, content: content, content_attributes: content_attributes)
      end

      context "when the flow wants 'inbound'" do
        before { directional_flow('inbound', event_name: 'conversation_opened') }

        it 'does NOT fire when the AGENT reopened the cycle (template) and the contact merely replied' do
          add_message_at(:incoming, 9.days.ago, content: 'primeira mensagem da conversa')
          resolve_at(2.days.ago)
          add_message_at(:outgoing, 2.hours.ago, content: 'iniciar_conversa (template da agente)')
          add_message_at(:incoming, 1.minute.ago, content: 'Boa tarde')

          fire_opened
          expect(conversation.reload.label_list).not_to include('dir-hit')
        end

        # Contraprova de que "direcao da mensagem ANTERIOR" nao serve: aqui a anterior tambem e
        # outgoing (a resposta da agente ha 8 dias), mas ela e do ciclo PASSADO — quem iniciou o
        # ciclo atual foi o contato, espontaneamente, e o flow tem de disparar.
        it 'fires when the CONTACT reopened the cycle spontaneously (no agent message after the resolution)' do
          add_message_at(:incoming, 9.days.ago, content: 'primeira mensagem da conversa')
          add_message_at(:outgoing, 8.days.ago, content: 'resposta da agente')
          resolve_at(2.days.ago)
          add_message_at(:incoming, 1.minute.ago, content: 'oi, voltei')

          fire_opened
          expect(conversation.reload.label_list).to include('dir-hit')
        end

        # Nao-regressao: sem resolucao registrada nao ha ciclo anterior (ex.: pending -> open do bot),
        # entao o ciclo atual comeca na criacao da conversa — a leitura de hoje.
        it 'falls back to the first message of the conversation when it was never resolved' do
          add_message_at(:incoming, 1.hour.ago)

          fire_opened
          expect(conversation.reload.label_list).to include('dir-hit')
        end
      end

      context "when the flow wants 'outbound'" do
        before { directional_flow('outbound', event_name: 'conversation_opened') }

        it 'fires when the AGENT reopened the cycle, even though the conversation was born inbound' do
          add_message_at(:incoming, 9.days.ago, content: 'primeira mensagem da conversa')
          resolve_at(2.days.ago)
          add_message_at(:outgoing, 2.hours.ago, content: 'iniciar_conversa (template da agente)')
          add_message_at(:incoming, 1.minute.ago, content: 'Boa tarde')

          fire_opened
          expect(conversation.reload.label_list).to include('dir-hit')
        end
      end

      # Logo apos uma resolucao quem fala primeiro e quase sempre o SISTEMA (a pesquisa NPS, as
      # boas-vindas de um flow) — e tudo isso e outgoing. Contar essas mensagens como "inicio do
      # ciclo" faria TODO ciclo nascer 'outbound' e barraria o flow 'inbound' de quem voltou
      # espontaneamente: cliente sem menu, sem atendimento. Falso negativo pior que o bug original.
      # Casos reais AGN: conv 424 (1a do ciclo = pergunta do NPS) e conv 449 (1a = fala do flow).
      context 'when the cycle starts with SYSTEM messages (NPS / automation)' do
        before { directional_flow('inbound', event_name: 'conversation_opened') }

        # Conv 424 (real, AGN): ultima resolucao 16/07 07:18, 1a msg do ciclo 07:18 outgoing
        # "De 0 a 10, qual e a nota..." — a pergunta do NPS, nao um humano.
        it 'fires when the cycle opens with the NPS question and the contact came back on their own' do
          add_message_at(:incoming, 9.days.ago, content: 'primeira mensagem da conversa')
          resolve_at(2.days.ago)
          add_system_message_at(2.days.ago + 1.second, { nps_survey: true },
                                content: 'De 0 a 10, qual e a nota que voce avalia o atendimento?')
          add_message_at(:incoming, 2.days.ago + 5.minutes, content: '10')
          add_message_at(:incoming, 1.minute.ago, content: 'Bom dia')

          fire_opened
          expect(conversation.reload.label_list).to include('dir-hit')
        end

        it 'fires when the cycle opens with an NPS system message (agradecimento/encerramento)' do
          add_message_at(:incoming, 9.days.ago, content: 'primeira mensagem da conversa')
          resolve_at(2.days.ago)
          add_system_message_at(2.days.ago + 1.second, { nps_survey_system: true }, content: 'Obrigado pela sua avaliacao!')
          add_message_at(:incoming, 1.minute.ago, content: 'Bom dia')

          fire_opened
          expect(conversation.reload.label_list).to include('dir-hit')
        end

        # Conv 449 (real, AGN): 1a msg do ciclo = "Ola! Bem-vindo(a) a AGN Imobiliaria..." — do
        # PROPRIO flow. O motor nao pode se auto-declarar iniciador do ciclo.
        it 'fires when the cycle opens with a message the flow engine itself sent (flow_id)' do
          add_message_at(:incoming, 9.days.ago, content: 'primeira mensagem da conversa')
          resolve_at(2.days.ago)
          add_system_message_at(2.days.ago + 1.second, { flow_id: 7 }, content: 'Ola! Bem-vindo(a) a AGN Imobiliaria')
          add_message_at(:incoming, 1.minute.ago, content: 'Bom dia')

          fire_opened
          expect(conversation.reload.label_list).to include('dir-hit')
        end

        it 'fires when the cycle opens with a message the legacy rule engine sent (automation_rule_id)' do
          add_message_at(:incoming, 9.days.ago, content: 'primeira mensagem da conversa')
          resolve_at(2.days.ago)
          add_system_message_at(2.days.ago + 1.second, { automation_rule_id: 3 }, content: 'Resposta automatica')
          add_message_at(:incoming, 1.minute.ago, content: 'Bom dia')

          fire_opened
          expect(conversation.reload.label_list).to include('dir-hit')
        end

        # A iniciativa humana da AGENTE vem DEPOIS do ruido do sistema: pulamos o NPS e achamos o
        # template dela. Continua sendo um ciclo 'outbound' — o flow 'inbound' nao dispara.
        it 'still does NOT fire when a human agent spoke after the system noise (conv 110 with NPS before it)' do
          add_message_at(:incoming, 9.days.ago, content: 'primeira mensagem da conversa')
          resolve_at(2.days.ago)
          add_system_message_at(2.days.ago + 1.second, { nps_survey: true }, content: 'De 0 a 10...')
          add_message_at(:outgoing, 2.hours.ago, content: 'iniciar_conversa (template da agente)',
                                                 sender: create(:user, account: account))
          add_message_at(:incoming, 1.minute.ago, content: 'Boa tarde')

          fire_opened
          expect(conversation.reload.label_list).not_to include('dir-hit')
        end

        # Ciclo so com sistema e mais nada: nao ha iniciativa humana para ler — cai no fallback
        # (comportamento de hoje), sem crash e sem inventar 'outbound'.
        it 'falls back to the conversation origin when the cycle has only system messages' do
          add_message_at(:incoming, 9.days.ago, content: 'primeira mensagem da conversa')
          resolve_at(2.days.ago)
          add_system_message_at(2.days.ago + 1.second, { nps_survey: true }, content: 'De 0 a 10...')

          fire_opened
          expect(conversation.reload.label_list).to include('dir-hit')
        end
      end

      # Multiplos ciclos: so a ULTIMA resolucao delimita o ciclo atual.
      context 'with more than one resolution in the history' do
        before { directional_flow('inbound', event_name: 'conversation_opened') }

        it 'uses only the latest resolution as the cycle boundary' do
          add_message_at(:incoming, 9.days.ago, content: 'primeira mensagem da conversa')
          resolve_at(8.days.ago)
          add_message_at(:outgoing, 7.days.ago, content: 'template do ciclo antigo')
          resolve_at(2.days.ago)
          add_message_at(:incoming, 1.minute.ago, content: 'oi, voltei')

          fire_opened
          expect(conversation.reload.label_list).to include('dir-hit')
        end
      end
    end

    context 'when the trigger is message_created (direction from the message itself)' do
      def deliver(message)
        listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message }))
      end

      it "an 'outbound' flow fires on an outgoing message but not an incoming one" do
        directional_flow('outbound', event_name: 'message_created', label: 'msg-out')
        deliver(add_message(:incoming))
        expect(conversation.reload.label_list).not_to include('msg-out')
        deliver(add_message(:outgoing))
        expect(conversation.reload.label_list).to include('msg-out')
      end

      it "an 'inbound' flow fires on an incoming message but not an outgoing one" do
        directional_flow('inbound', event_name: 'message_created', label: 'msg-in')
        deliver(add_message(:outgoing))
        expect(conversation.reload.label_list).not_to include('msg-in')
        deliver(add_message(:incoming))
        expect(conversation.reload.label_list).to include('msg-in')
      end
    end

    context 'when the trigger is a keyword flow (inbound by nature)' do
      def kw_flow(direction, label: 'kw-dir')
        action = { 'id' => 'a1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [label] }
        trigger = { 'id' => 't1', 'type' => 'trigger', 'direction' => direction }
        create(:flow, account: account, trigger_type: :keyword,
                      trigger_config: { 'keywords' => ['suporte'], 'match' => 'contains', 'direction' => direction },
                      definition: { 'nodes' => [trigger, action], 'edges' => [{ 'from' => 't1', 'to' => 'a1' }] })
      end

      def deliver_incoming(content)
        message = create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :incoming, content: content)
        listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message }))
      end

      it "fires an 'inbound' keyword flow on a matching incoming message" do
        kw_flow('inbound')
        deliver_incoming('quero suporte')
        expect(conversation.reload.label_list).to include('kw-dir')
      end

      it "never fires an 'outbound' keyword flow (a keyword only matches inbound messages)" do
        kw_flow('outbound')
        allow(Flows::RunnerService).to receive(:new)
        deliver_incoming('quero suporte')
        expect(Flows::RunnerService).not_to have_received(:new)
      end
    end
  end
end
