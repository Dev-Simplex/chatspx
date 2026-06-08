# frozen_string_literal: true

# KANBAN-P2-01: aplica um KanbanTemplate criando 1 Kanban + N KanbanStages.
# Cards-exemplo NAO sao criados aqui (sample_cards do template ficam disponiveis
# em metadata para criacao opcional posterior). Retorna o Kanban persistido.
class Kanbans::ApplyTemplateService
  attr_reader :account, :template, :options, :user

  def initialize(account:, template:, options: {}, user: nil)
    @account = account
    @template = template
    @options = options.with_indifferent_access
    @user = user
  end

  def perform
    raise ArgumentError, 'template required' if template.blank?
    raise ArgumentError, 'account required' if account.blank?

    kanban = nil
    Kanban.transaction do
      kanban = create_kanban
      seed_stages(kanban)
    end
    kanban
  end

  private

  def create_kanban # rubocop:disable Metrics/AbcSize
    account.kanbans.create!(
      name: options[:name].presence || template.name,
      description: options[:description].presence || template.description,
      color: options[:color].presence || template.color,
      team_id: options[:team_id],
      inbox_ids: Array(options[:inbox_ids]).compact.map(&:to_i),
      created_by_id: user&.id,
      template_id: template.id,
      position: next_position
    )
  end

  def seed_stages(kanban)
    stages = Array(template.stages_config)
    stages.each_with_index do |cfg, idx|
      cfg = cfg.with_indifferent_access
      kanban.kanban_stages.create!(
        name: cfg[:name],
        color: cfg[:color],
        position: cfg[:position] || idx,
        automation_type: cfg[:automation_type],
        rot_after_days: cfg[:rot_after_days],
        wip_limit: cfg[:wip_limit],
        won_loss_type: cfg[:won_loss_type],
        probability: cfg[:probability]
      )
    end
  end

  def next_position
    (account.kanbans.maximum(:position) || -1) + 1
  end
end
