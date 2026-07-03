# Lists the funnel placements (Kanban) of a single conversation, so the
# conversation sidebar can show "which funnel/stage is this contact in".
# Read-only; one row per funnel the conversation belongs to (unique per funnel).
class Api::V1::Accounts::Conversations::FunnelItemsController < Api::V1::Accounts::Conversations::BaseController
  def index
    @funnel_items = @conversation.funnel_items
                                 .includes(:funnel, :funnel_stage)
                                 .order(moved_at: :desc)
  end
end
