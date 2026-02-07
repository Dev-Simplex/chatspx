# frozen_string_literal: true

module Funnels
  class ReorderStagesService
    attr_reader :funnel, :stage_ids

    def initialize(funnel:, stage_ids:)
      @funnel = funnel
      @stage_ids = Array(stage_ids).map { |id| id.to_s.to_i }.reject(&:zero?).uniq
    end

    def perform
      return if stage_ids.blank?

      valid_stage_ids = funnel.funnel_stages.where(id: stage_ids).pluck(:id)
      ordered_ids = stage_ids.select { |id| valid_stage_ids.include?(id) }
      return if ordered_ids.blank?

      ActiveRecord::Base.transaction do
        ordered_ids.each_with_index do |stage_id, index|
          funnel.funnel_stages.where(id: stage_id).update_all(position: index)
        end
      end
    end
  end
end
