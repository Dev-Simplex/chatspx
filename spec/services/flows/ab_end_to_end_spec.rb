# frozen_string_literal: true

require 'rails_helper'

# 6.05 — O ACEITE INTEIRO, numa corrida só: "duas variantes do mesmo fluxo recebem tráfego e
# o relatório mostra conversão e abandono por etapa nas duas".
#
# POR QUE ESTE ARQUIVO EXISTE ALÉM DOS OUTROS QUATRO. Os specs de unidade provam cada peça
# sozinha: a designação designa, o emissor emite, o relatório calcula. O defeito que eles
# não pegam é o de JUNÇÃO — cada lado certo e incompatível no encontro, verde nos dois. Aqui
# nada é dublado no meio do caminho: resolvem-se variantes de verdade, roda-se o motor de
# verdade, gravam-se eventos de verdade e lê-se o relatório de verdade.
# rubocop:disable RSpec/DescribeClass -- o assunto deste arquivo NAO e uma classe: e a
# juncao entre quatro delas (resolver, motor, emissor e relatorio). Nomea-lo por uma so
# esconderia que o defeito que ele existe para pegar mora exatamente entre elas.
RSpec.describe 'Teste A/B de fluxo, de ponta a ponta' do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  # VARIANTE A — curta: dois passos e acaba. Todo visitante que entra, converte.
  let!(:curta) do
    create(:flow, account: account, trigger_type: :widget_prechat, name: 'Captura curta',
                  trigger_config: { 'experiment' => { 'key' => 'captura' } },
                  definition: { 'nodes' => [acao('a1', 'ola'), acao('a2', 'nome')],
                                'edges' => [{ 'from' => 'a1', 'to' => 'a2' }] })
  end

  # VARIANTE B — longa: um `wait` no meio. O visitante para ali, e o walk suspende sem
  # chegar ao fim: exposição sim, etapa sim, conversão NÃO. É o abandono que o relatório
  # precisa saber mostrar.
  let!(:longa) do
    create(:flow, account: account, trigger_type: :widget_prechat, name: 'Captura longa',
                  trigger_config: { 'experiment' => { 'key' => 'captura' } },
                  definition: { 'nodes' => [acao('b1', 'ola'),
                                            { 'id' => 'bw', 'type' => 'wait', 'wait' => { 'value' => 1, 'unit' => 'hours' } },
                                            acao('b2', 'nome')],
                                'edges' => [{ 'from' => 'b1', 'to' => 'bw' }, { 'from' => 'bw', 'to' => 'b2' }] })
  end

  before do
    web_widget.update!(pre_chat_form_enabled: true,
                       pre_chat_form_options: web_widget.pre_chat_form_options.merge('mode' => 'flow'))
  end

  def acao(id, rotulo)
    { 'id' => id, 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [rotulo], 'label' => rotulo }
  end

  # Um visitante de verdade: contato próprio, `source_id` próprio (a chave de estabilidade),
  # conversa própria. O `source_id` é o que o widget guarda no navegador.
  def visitante(numero)
    contact = create(:contact, account: account)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: "navegador-#{numero}")
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  # Exatamente o que o AutomationRuleListener faz em `conversation_created`.
  def atender(conversation)
    flow = Flows::WidgetPrechatResolver.for_conversation(conversation)&.perform
    return nil if flow.blank?

    Flows::RunnerService.new(flow: flow, conversation: conversation, trigger_payload: {}).perform
    flow
  end

  def relatorio
    Flows::AbReportService.new(account: account, experiment: 'captura').perform
  end

  def variante_no_relatorio(flow)
    relatorio['variants'].find { |v| v['variant'] == flow.id }
  end

  # 40 e nao 60 de proposito, e o numero tem consequencia: com 40 visitantes divididos em
  # dois bracos, NENHUM braco alcanca as 30 exposicoes minimas, entao o veredito estatistico
  # e sempre `amostra_insuficiente` — deterministico, em vez de depender de onde a divisao
  # caiu. Tambem corta um terco do tempo do arquivo (2m18s -> ~1m30s), que e caro para uma
  # suite que roda inteira.
  context 'when 40 real visitors go through the engine' do
    let!(:entregues) { (1..40).map { |n| atender(visitante(n)) } }

    it 'entrega as DUAS variantes — sem isso não há teste nenhum' do
      expect(entregues.map(&:id).uniq.sort).to eq([curta.id, longa.id].sort)
    end

    it 'conta cada visitante como UMA exposição, e a soma fecha com o total atendido' do
      expostos = relatorio['variants'].sum { |v| v['exposures'] }

      expect(expostos).to eq(40)
    end

    it 'credita a exposição à variante que o visitante realmente recebeu' do
      recebidos = entregues.count { |flow| flow.id == curta.id }

      expect(variante_no_relatorio(curta)['exposures']).to eq(recebidos)
    end

    it 'converte quem chegou ao fim e NÃO converte quem parou no wait' do
      expect(variante_no_relatorio(curta)['conversion_rate']).to eq(100.0)
      expect(variante_no_relatorio(longa)['conversions']).to eq(0)
    end

    it 'mostra o funil por etapa nas duas variantes, na ordem da definição' do
      etapas_curta = variante_no_relatorio(curta)['steps']
      etapas_longa = variante_no_relatorio(longa)['steps']

      expect(etapas_curta.map { |e| e['node_id'] }).to eq(%w[a1 a2])
      # A variante longa vai até o `wait` e para. O nó do wait ENTRA no funil com
      # `reached: 0` — é ele que carrega o abandono, e omiti-lo esconderia justamente a
      # etapa onde o visitante desistiu. O `b2`, depois dele, some: linha vazia atrás de
      # linha vazia é ruído, não informação.
      expect(etapas_longa.map { |e| e['node_id'] }).to eq(%w[b1 bw])
    end

    it 'credita o abandono da variante longa AO NÓ onde o visitante parou' do
      expostos = variante_no_relatorio(longa)['exposures']
      primeira, parada = variante_no_relatorio(longa)['steps']

      expect(primeira['reached']).to eq(expostos)
      expect(primeira['abandoned']).to eq(0)
      expect(parada['node_id']).to eq('bw')
      expect(parada['reached']).to eq(0)
      expect(parada['abandoned']).to eq(expostos)
      expect(variante_no_relatorio(longa)['conversion_rate']).to eq(0.0)
    end

    it 'não crava vencedor com 40 visitantes divididos em dois, mesmo com 100% contra 0%' do
      comparacao = relatorio['comparisons'].first

      # A diferença é a maior possível — 100% contra 0% — e mesmo assim o relatório se
      # recusa a eleger uma vencedora, porque a amostra não sustenta. É o aceite inteiro
      # numa asserção: declarar o que não dá para saber vale mais que exibir o maior número.
      expect(comparacao['verdict']).to eq('inconclusivo')
      expect(comparacao['reason']).to eq('amostra_insuficiente')
    end
  end

  context 'when the same visitor comes back' do
    it 'recebe SEMPRE a mesma variante em conversas diferentes do mesmo navegador' do
      contact = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'navegador-fixo')

      recebidos = Array.new(3) do
        conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
        Flows::WidgetPrechatResolver.for_conversation(conversa)&.perform
      end

      expect(recebidos.map(&:id).uniq.size).to eq(1)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
