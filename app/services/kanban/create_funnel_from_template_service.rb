# frozen_string_literal: true

# Kanban v2 (Fase 8) — materialize a funnel (stages + custom fields) for an
# account from a template blueprint, in one transaction.
class Kanban::CreateFunnelFromTemplateService
  def initialize(account:, template:, name: nil)
    @account = account
    @template = template
    @name = name
  end

  def perform
    ActiveRecord::Base.transaction do
      funnel = @account.funnels.create!(
        name: @name.to_s.strip.presence || @template.name,
        color: @template.definition['color'].presence || '#3b82f6',
        position: next_position
      )
      create_stages(funnel)
      create_custom_fields(funnel)
      funnel
    end
  end

  private

  def next_position
    (@account.funnels.maximum(:position) || -1) + 1
  end

  def create_stages(funnel)
    @template.stages.each_with_index do |stage, index|
      funnel.funnel_stages.create!(
        name: stage['name'],
        color: stage['color'],
        position: index,
        automation_type: stage['automation_type'].presence
      )
    end
  end

  def create_custom_fields(funnel)
    @template.custom_fields.each_with_index do |field, index|
      funnel.funnel_custom_fields.create!(
        key: field['key'],
        label: field['label'],
        field_type: field['field_type'],
        show_on_card: field.fetch('show_on_card', false),
        options: field['options'] || {},
        position: index
      )
    end
  end
end
