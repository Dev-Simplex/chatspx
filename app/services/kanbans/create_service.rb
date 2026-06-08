# frozen_string_literal: true

class Kanbans::CreateService
  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def perform
    kanban = account.kanbans.create!(params)

    if params[:default_stages].present?
      params[:default_stages].each_with_index do |stage_name, index|
        kanban.kanban_stages.create!(
          name: stage_name,
          position: index
        )
      end
    end

    kanban
  end
end
