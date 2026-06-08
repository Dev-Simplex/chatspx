class Captain::Tools::Copilot::GetAccountStatsService < Captain::Tools::BaseTool
  def self.name
    'get_account_stats'
  end
  description 'Get account statistics: open conversations, average response time, CSAT score, online agents'

  def execute
    account = @assistant.account
    open_count = account.conversations.where(status: :open).count
    pending_count = account.conversations.where(status: :pending).count
    online_agents = account.account_users.joins(:user).where(users: { availability: :online }).count
    csat = account.csat_survey_responses.where('created_at > ?', 7.days.ago)
    avg_csat = csat.any? ? (csat.average(:rating).to_f * 100).round(1) : 'N/A'

    <<~STATS
      Account Stats:
      - Open conversations: #{open_count}
      - Pending conversations: #{pending_count}
      - Online agents: #{online_agents}
      - CSAT (7d avg): #{avg_csat}
    STATS
  end

  def active?
    user_has_permission('report_manage')
  end
end
