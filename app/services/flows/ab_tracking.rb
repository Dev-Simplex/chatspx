# frozen_string_literal: true

# Os três fatos do teste A/B de fluxo (bloco 6.05), gravados pelo registro do 5.03.
#
# ─── POR QUE AQUI NÃO HÁ CONTAGEM PRÓPRIA ────────────────────────────────────────────
# Conversão e abandono já têm onde morar: `tracking_events`, com o contrato versionado em
# docs/tracking/contrato-de-eventos.md. Uma tabela de contadores só para o A/B criaria uma
# SEGUNDA fonte para o mesmo número, e duas fontes divergem no primeiro retry. Aqui só se
# chama `Tracking::EventRecorder.record!`.
#
# ─── A TRAVA QUE HERDAMOS DO 5.03, E POR QUE ELA É O BLOCO ───────────────────────────
# O job do dispatcher é RETENTADO (§4.2 do contrato). Sem chave natural, a derivação
# padrão cai em `occurred_at.to_i` e o retry no segundo seguinte vira um segundo fato.
# Num A/B isso não é ruído: é **a variante errada ganhando**, porque quem retenta mais é
# quem falhou mais. Por isso os três eventos passam `dedup_key` EXPLÍCITA, montada sobre
# a chave natural do fato — (variante, conversa, o quê) — e o índice único
# (account_id, name, dedup_key) faz o resto.
#
# Consequência que é aceite: o mesmo visitante que passa duas vezes pelo mesmo nó (uma
# retomada depois de um `wait`, um retry do job) conta UMA vez. O denominador é
# "visitantes que viram a variante", não "vezes que o motor rodou".
#
# ─── BEST-EFFORT ABSOLUTO ────────────────────────────────────────────────────────────
# Nada aqui pode derrubar o fluxo do visitante. Medir o experimento é menos importante que
# atender quem está do outro lado — é a mesma regra do `record_step` do 4.11 e do
# guardrail do 6.01: em erro, registra e segue.
module Flows::AbTracking
  PREFIX = 'chatspx_flow_variant_'
  ASSIGNED = "#{PREFIX}assigned".freeze
  STEP = "#{PREFIX}step".freeze
  CONVERTED = "#{PREFIX}converted".freeze
  NAMES = [ASSIGNED, STEP, CONVERTED].freeze

  module_function

  # A exposição — o DENOMINADOR. Emitida quando o motor começa a rodar a variante para
  # este visitante, e não na hora da designação: designar sem rodar não é ter visto nada,
  # e um denominador inflado faz toda taxa de conversão parecer pior do que é.
  def record_assignment(flow:, conversation:)
    record(flow: flow, conversation: conversation, name: ASSIGNED, suffix: 'assigned')
  end

  # Uma ETAPA alcançada. "Etapa" aqui é o nó EXECUTADO pelo motor — é a unidade que o
  # próprio walker já conhece (Flows::StepInstrumentation) e a única que não precisa de um
  # segundo conceito para existir. A ORDEM das etapas não viaja no evento: quem ordena é o
  # relatório, pela posição do nó em `flow.definition` — assim uma retomada não reinicia
  # contagem nenhuma e ramos diferentes não disputam o mesmo número de etapa.
  def record_step(flow:, conversation:, node_id:)
    return if node_id.blank?

    record(flow: flow, conversation: conversation, name: STEP,
           suffix: "step:#{node_id}", extra: { 'node_id' => node_id.to_s })
  end

  # A conversão: o walk chegou ao fim. É a definição que o motor já tem (`finish_run`), e
  # não uma nova — inventar "meta" aqui colidiria com `flows.goal_conditions`, que está
  # dormente e é assunto de outro bloco.
  def record_conversion(flow:, conversation:)
    record(flow: flow, conversation: conversation, name: CONVERTED, suffix: 'converted')
  end

  # `nil` quando este fluxo não está em experimento nenhum — que é o estado de toda a
  # frota hoje, e o motivo de nenhum evento ser emitido por ela.
  def experiment_key(flow)
    Flow::AbExperiment.key_for(flow)
  end

  def record(flow:, conversation:, name:, suffix:, extra: {})
    key = experiment_key(flow)
    return if key.blank?
    return if conversation.blank?

    Tracking::EventRecorder.record!(
      name: name,
      account: flow.account,
      inbox: conversation.inbox,
      conversation: conversation,
      contact: conversation.contact,
      properties: properties(flow, key).merge(extra),
      source: :server,
      dedup_key: "flow_ab:#{flow.id}:#{conversation.id}:#{suffix}"
    )
  rescue StandardError => e
    Rails.logger.warn("[flow-ab] nao registrou #{name} do flow=#{flow&.id}: #{e.class} #{e.message}")
    nil
  end

  # Vocabulário FECHADO: tudo aqui vem da configuração e do próprio fluxo, nada de texto
  # livre do visitante. `variant_version` é o que faz o aceite "publicar uma variante nova
  # não invalida o histórico da anterior" valer — a linha antiga guarda a versão sob a qual
  # aquele número foi obtido, e continua legível depois da republicação.
  def properties(flow, key)
    {
      'experiment' => key,
      'variant' => flow.id,
      'variant_version' => flow.version
    }
  end
end
