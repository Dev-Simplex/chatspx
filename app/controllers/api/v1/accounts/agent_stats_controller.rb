class Api::V1::Accounts::AgentStatsController < Api::V1::Accounts::BaseController
  # Returns personal performance stats for the currently logged-in agent.
  # No admin role required — agents can only see their own data.

  def show
    builder = V2::Reports::Conversations::MetricBuilder.new(
      Current.account,
      {
        type: :agent,
        id: current_user.id,
        since: params[:since],
        until: params[:until],
        group_by: params[:group_by],
        business_hours: ActiveModel::Type::Boolean.new.cast(params[:business_hours])
      }
    )

    current_summary = builder.summary
    render json: current_summary
  end
end
