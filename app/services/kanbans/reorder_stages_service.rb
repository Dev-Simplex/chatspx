# frozen_string_literal: true

class Kanbans::ReorderStagesService
  attr_reader :kanban, :stage_ids

  def initialize(kanban:, stage_ids:)
    @kanban = kanban
    @stage_ids = Array(stage_ids).map { |id| id.to_s.to_i }.reject(&:zero?).uniq
  end

  def perform
    return if stage_ids.blank?

    valid_stage_ids = kanban.kanban_stages.where(id: stage_ids).pluck(:id)
    ordered_ids = stage_ids.select { |id| valid_stage_ids.include?(id) }
    return if ordered_ids.blank?

    ActiveRecord::Base.transaction do
      ordered_ids.each_with_index do |stage_id, index|
        kanban.kanban_stages.where(id: stage_id).update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
