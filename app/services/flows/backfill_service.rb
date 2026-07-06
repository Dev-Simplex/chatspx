# frozen_string_literal: true

# Migra as Macros e AutomationRules de uma conta para Flows equivalentes (cada regra/macro
# vira um Flow LINEAR — caso degenerado sem branch). NÃO desativa nem apaga os originais:
# a coexistência é controlada pela feature flag `flows` (o listener roda um motor OU o
# outro por conta). Idempotente via marcador `trigger_config['backfill_source']`. O modo
# dry_run valida sem gravar, para diff nó-a-nó antes do cutover (mitiga R-3). Ver plano §2.3.
class Flows::BackfillService
  def initialize(account:, dry_run: false)
    @account = account
    @dry_run = dry_run
    @result = { macros: 0, automation_rules: 0, skipped: 0, errors: [] }
  end

  def perform
    @account.macros.find_each { |macro| backfill_macro(macro) }
    @account.automation_rules.find_each { |rule| backfill_rule(rule) }
    @result
  end

  private

  def backfill_macro(macro)
    source = "macro:#{macro.id}"
    return skip if already_backfilled?(source)

    flow = @account.flows.new(
      name: macro.name,
      trigger_type: :manual,
      trigger_config: { 'backfill_source' => source },
      definition: actions_to_definition(macro.actions),
      visibility: macro.visibility,
      created_by_id: macro.created_by_id,
      updated_by_id: macro.updated_by_id,
      active: true
    )
    persist(flow, macro, :macros)
  end

  def backfill_rule(rule)
    source = "automation_rule:#{rule.id}"
    return skip if already_backfilled?(source)

    flow = @account.flows.new(
      name: rule.name,
      description: rule.description,
      trigger_type: :conversation_event,
      trigger_config: { 'event_name' => rule.event_name, 'conditions' => rule.conditions, 'backfill_source' => source },
      definition: actions_to_definition(rule.actions),
      visibility: :global,
      active: rule.active
    )
    persist(flow, rule, :automation_rules)
  end

  # Cada ação (na ordem) vira um nó `action`; as arestas encadeiam linearmente.
  def actions_to_definition(actions)
    nodes = Array(actions).each_with_index.map do |action, index|
      action = action.with_indifferent_access
      { 'id' => "n#{index + 1}", 'type' => 'action', 'action_name' => action[:action_name], 'action_params' => action[:action_params] }
    end
    edges = nodes.each_cons(2).map { |from, to| { 'from' => from['id'], 'to' => to['id'] } }
    { 'nodes' => nodes, 'edges' => edges }
  end

  def already_backfilled?(source)
    @account.flows.exists?(["trigger_config->>'backfill_source' = ?", source])
  end

  def persist(flow, source_record, key)
    if @dry_run
      flow.valid? ? (@result[key] += 1) : record_error(source_record, flow.errors.full_messages)
      return
    end

    flow.save!
    copy_files(source_record, flow)
    @result[key] += 1
  rescue ActiveRecord::RecordInvalid => e
    record_error(source_record, [e.message])
  end

  def copy_files(source_record, flow)
    return unless source_record.respond_to?(:files) && source_record.files.attached?

    source_record.files.each { |file| flow.files.attach(file.blob) }
  end

  def skip
    @result[:skipped] += 1
  end

  def record_error(source_record, messages)
    @result[:errors] << { source: "#{source_record.class.name}:#{source_record.id}", messages: messages }
  end
end
