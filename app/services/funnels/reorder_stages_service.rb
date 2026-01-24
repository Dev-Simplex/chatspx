# frozen_string_literal: true

module Funnels
  class ReorderStagesService
    attr_reader :funnel, :stage_ids

    def initialize(funnel:, stage_ids:)
      @funnel = funnel
      @stage_ids = stage_ids
    end

    def perform
      return if stage_ids.blank?

      ActiveRecord::Base.transaction do
        stage_ids.each_with_index do |stage_id, index|
          stage = funnel.funnel_stages.find_by(id: stage_id)
          next unless stage

          stage.update!(position: index)
        end
      end
    end
  end
end


