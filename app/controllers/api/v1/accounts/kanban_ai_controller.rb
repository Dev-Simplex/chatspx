# frozen_string_literal: true

# Kanban v2 (Fase 7) — tells the board UI whether AI actions (summarize, reply,
# sentiment, labels) can be offered. The actions themselves reuse the existing
# Captain task endpoints; this only gates the UI.
class Api::V1::Accounts::KanbanAiController < Api::V1::Accounts::BaseController
  def status
    render json: {
      available: Kanban::Ai::AvailabilityService.new(account: Current.account).available?
    }
  end
end
