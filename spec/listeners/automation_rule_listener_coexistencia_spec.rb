require 'rails_helper'

# Os dois motores rodam JUNTOS. Até 28/08/2026 era `if/else`, um excluindo o outro, e o preço era
# alto: numa conta em modo regras os flows apareciam na tela, salvavam e nunca disparavam (a .229
# tinha 21 flows parados assim), e a ação `distribuir` do rodízio, que só existe no canvas, ficava
# inalcançável para quem estava em regras.
#
# O que o `else` protegia era a dupla-execução, e ela continua barrada — só que por dado, não por
# exclusão: o backfill gravou no flow de qual regra ele nasceu.
RSpec.describe AutomationRuleListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def ligar_flows
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
  end

  def regra(nome, etiqueta)
    create(:automation_rule, account: account, name: nome, event_name: 'conversation_created',
                             conditions: [{ attribute_key: 'status', filter_operator: 'equal_to',
                                            values: ['open'], custom_attribute_type: '' }],
                             actions: [{ action_name: 'add_label', action_params: [etiqueta] }])
  end

  def flow(etiqueta, origem: nil)
    trigger = { 'id' => 't1', 'type' => 'trigger' }
    acao = { 'id' => 'a1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [etiqueta] }
    config = { 'event_name' => 'conversation_created' }
    config['backfill_source'] = origem if origem
    create(:flow, account: account, trigger_type: :conversation_event, active: true,
                  trigger_config: config,
                  definition: { 'nodes' => [trigger, acao], 'edges' => [{ 'from' => 't1', 'to' => 'a1' }] })
  end

  def disparar
    Rails.cache.clear
    listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now,
                                                   conversation: conversation))
  end

  describe 'os dois motores juntos' do
    # A regressão principal: antes, ligar a flag silenciava TODAS as regras da conta de uma vez.
    it 'a regra continua rodando mesmo com o motor de flows ligado' do
      ligar_flows
      flow('do-flow')
      regra('so-regra', 'da-regra')

      disparar

      expect(conversation.reload.label_list).to include('da-regra')
    end

    it 'o flow e a regra rodam na mesma conversa' do
      ligar_flows
      flow('do-flow')
      regra('so-regra', 'da-regra')

      disparar

      expect(conversation.reload.label_list).to include('do-flow', 'da-regra')
    end

    # Conta sem a flag: o flow existe, aparece na tela, mas não dispara. É o estado da .229 e da
    # Tozi, e a regra tem de continuar funcionando ali como sempre funcionou.
    it 'sem a flag, so a regra roda' do
      flow('do-flow')
      regra('so-regra', 'da-regra')

      disparar

      etiquetas = conversation.reload.label_list
      expect(etiquetas).to include('da-regra')
      expect(etiquetas).not_to include('do-flow')
    end
  end

  # O backfill criou os flows COPIANDO as regras, e as duas ficaram ativas lado a lado. Rodar os
  # dois sem proteção dispararia a mesma automação duas vezes — medido: 11 pares na Tozi.
  describe 'regra que ja virou flow' do
    it 'e PULADA quando existe um flow ativo nascido dela' do
      ligar_flows
      duplicada = regra('virou-flow', 'da-regra')
      flow('do-flow', origem: "automation_rule:#{duplicada.id}")

      disparar

      etiquetas = conversation.reload.label_list
      expect(etiquetas).to include('do-flow')
      expect(etiquetas).not_to include('da-regra')
    end

    # Some sozinho quando não é mais preciso: é o motivo de a proteção viver no motor e não como
    # `active: false` no banco.
    it 'volta a valer se o flow for desativado' do
      ligar_flows
      duplicada = regra('virou-flow', 'da-regra')
      f = flow('do-flow', origem: "automation_rule:#{duplicada.id}")
      f.update!(active: false)

      disparar

      expect(conversation.reload.label_list).to include('da-regra')
    end

    # Macro é ação MANUAL, não dispara sozinha: nunca houve duplicidade com ela, então uma regra
    # não pode ser calada por causa de um flow que veio de macro.
    it 'flow nascido de MACRO nao cala regra nenhuma' do
      ligar_flows
      regra('so-regra', 'da-regra')
      flow('do-flow', origem: 'macro:7')

      disparar

      expect(conversation.reload.label_list).to include('do-flow', 'da-regra')
    end

    it 'so cala a regra de origem, nao as outras' do
      ligar_flows
      duplicada = regra('virou-flow', 'da-duplicada')
      regra('outra', 'da-outra')
      flow('do-flow', origem: "automation_rule:#{duplicada.id}")

      disparar

      etiquetas = conversation.reload.label_list
      expect(etiquetas).to include('do-flow', 'da-outra')
      expect(etiquetas).not_to include('da-duplicada')
    end

    # Sem a flag o flow não roda; se a regra também fosse pulada, a automação sumiria por completo.
    it 'sem a flag, a regra de origem continua valendo (senao a automacao sumiria)' do
      duplicada = regra('virou-flow', 'da-regra')
      flow('do-flow', origem: "automation_rule:#{duplicada.id}")

      disparar

      expect(conversation.reload.label_list).to include('da-regra')
    end
  end
end
