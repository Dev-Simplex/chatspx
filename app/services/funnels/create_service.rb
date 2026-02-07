# frozen_string_literal: true

module Funnels
  class CreateService
    attr_reader :account, :params

    def initialize(account:, params:)
      @account = account
      @params = params
    end

    def perform
      funnel = account.funnels.create!(params)

      if params[:default_stages].present?
        params[:default_stages].each_with_index do |stage_name, index|
          funnel.funnel_stages.create!(
            name: stage_name,
            position: index
          )
        end
      end

      funnel
    end
  end
end
