# frozen_string_literal: true

# Gatilho `schedule` (Fase 2): dispara Flows por TEMPO, não por evento. A cada tick
# (config/schedule.yml, */15) varre os Flows `trigger_type: schedule` ativos de contas com o
# motor ligado e, para cada um cuja janela (cron/intervalo) venceu, dispara o fluxo. Molde:
# Kanban::SlaMonitorJob (varredura periódica + marcador idempotente).
#
# IDEMPOTÊNCIA por JANELA: um marcador `last_fired_at` em `trigger_config` (espelha o
# `custom_attributes["kanban_auto_#{id}"]` do SlaMonitorJob, mas no NÍVEL DO FLOW — um schedule
# é propriedade do flow, não de uma conversa). O `with_lock` + a re-checagem DENTRO do lock
# impedem que dois ticks disparem a mesma janela (espelha o reentrante Flows::ResumeService).
# O marcador é gravado ANTES do disparo (at-most-once por janela): um erro no meio do fan-out
# não re-dispara a janela inteira num retry — o mais seguro quando as ações mandam mensagem.
#
# FORMATO de `trigger_config` (documentado no widget TriggerConfig.vue):
#   { "mode": "cron",     "cron": "0 9 * * 1", "conditions": [...] }   # toda segunda 9h
#   { "mode": "interval", "every": 3, "unit": "days", "conditions": [...] }  # a cada 3 dias
#   `last_fired_at` (ISO8601) é escrito pelo job, não pelo usuário.
# `baseline` = `last_fired_at` ou, na 1ª vez, `created_at` — um schedule recém-criado só
# dispara na PRÓXIMA ocorrência, nunca imediatamente ao salvar.
#
# ALVO SEM CONVERSA (decisão de mínimo-seguro): um schedule nasce sem conversa disparadora, mas
# Flows::RunnerService exige uma (ActionService + FlowRun operam sobre conversa). NÃO criamos
# conversa de sistema (poluiria a inbox e exigiria escolher inbox/contato). Em vez disso, quando
# o flow tem `conditions`, disparamos sobre as conversas ABERTAS da conta que casam com elas —
# mesmo caminho RuleAdapter + ConditionsFilterService + RunnerService dos flows de evento/keyword.
# SEM `conditions` é no-op seguro (loga + marca a janela): NÃO varremos todas as conversas
# (condições vazias casam TODAS e disparar em massa por tick é perigoso).
# TODO(F3): alvo global/conversa-de-sistema (para ações sem conversa) e UI de condições no
# widget de schedule. TODO: o cron é interpretado no fuso da app (Time.zone); sem fuso por conta.
class Flows::ScheduleTriggerJob < ApplicationJob
  queue_as :scheduled_jobs

  INTERVAL_UNITS = %w[minutes hours days].freeze
  DEFAULT_INTERVAL_UNIT = 'days'

  def perform
    now = Time.current
    Flow.active.schedule.includes(:account).find_each do |flow|
      process_flow(flow, now)
    rescue StandardError => e
      Rails.logger.warn("Flows::ScheduleTriggerJob flow #{flow.id} failed: #{e.message}")
    end
  end

  private

  def process_flow(flow, now)
    return unless flow.account.flows_engine_enabled?

    window = claim_due_window(flow, now)
    return if window.nil? # não venceu, ou já reservada por outro tick

    fire(flow)
  end

  # Reserva a janela atomicamente: dentro do lock recalcula se venceu e, se sim, grava o
  # marcador ANTES de qualquer disparo. Dois ticks concorrentes: o segundo relê o marcador
  # dentro do lock e vê a janela já reservada → devolve nil. Retorna a Time canônica ou nil.
  def claim_due_window(flow, now)
    flow.with_lock do
      cfg = flow.trigger_config.to_h
      window = due_window(flow, cfg, now)
      next nil if window.nil?

      flow.update_column(:trigger_config, cfg.merge('last_fired_at' => window.iso8601)) # rubocop:disable Rails/SkipsModelValidations
      window
    end
  end

  # Time canônica da janela vencida ainda não disparada, ou nil.
  def due_window(flow, cfg, now)
    baseline = parse_time(cfg['last_fired_at']) || flow.created_at
    case cfg['mode'].to_s
    when 'interval'
      interval_window(cfg, baseline, now)
    else # 'cron' (padrão)
      cron_window(cfg, baseline, now)
    end
  end

  # Ocorrência de cron <= agora; devida se cair DEPOIS do baseline (marcador da última janela).
  def cron_window(cfg, baseline, now)
    cron = Fugit.parse_cron(cfg['cron'].to_s)
    return nil if cron.nil?

    occurrence = cron.previous_time(now).to_t
    occurrence if occurrence > baseline
  end

  # Devida quando `every` unidades já se passaram desde o baseline.
  def interval_window(cfg, baseline, now)
    every = cfg['every'].to_i
    return nil if every <= 0

    unit = INTERVAL_UNITS.include?(cfg['unit']) ? cfg['unit'] : DEFAULT_INTERVAL_UNIT
    now if now >= baseline + every.public_send(unit)
  end

  # Fan-out sobre as conversas-alvo (ver nota de topo). Sem condições → no-op seguro.
  def fire(flow)
    conditions = Array(flow.trigger_config['conditions'])
    if conditions.blank?
      Rails.logger.info("Flows::ScheduleTriggerJob flow #{flow.id}: janela venceu sem condições de alvo; no-op (TODO alvo global)")
      return
    end

    payload = { trigger: 'schedule' }
    flow.account.conversations.open.find_each do |conversation|
      gate = Flows::RuleAdapter.new(conditions: conditions, flow: flow)
      next unless AutomationRules::ConditionsFilterService.new(gate, conversation, payload).perform

      Flows::RunnerService.new(flow: flow, conversation: conversation, trigger_payload: payload).perform
    rescue StandardError => e
      Rails.logger.warn("Flows::ScheduleTriggerJob flow #{flow.id} conversation #{conversation.id} failed: #{e.message}")
    end
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
