class Captain::Tools::Copilot::GetCsatDataService < Captain::Tools::BaseTool
  def self.name
    'get_csat_data'
  end
  description 'Get recent CSAT survey scores and feedback'

  param :days, type: :integer, desc: 'Number of days to look back (default 7)'

  def execute(days: 7)
    account = @assistant.account
    responses = account.csat_survey_responses
                       .where('created_at > ?', days.days.ago)
                       .includes(:conversation, :contact)
                       .order(created_at: :desc)
                       .limit(50)

    return "No CSAT data in the last #{days} days" if responses.empty?

    avg = (responses.average(:rating).to_f * 100).round(1)
    lines = responses.map do |r|
      "- Conv ##{r.conversation&.display_id}: #{r.rating}/5 #{r.feedback_text.present? ? "- \"#{r.feedback_text}\"" : ''}"
    end

    <<~DATA
      CSAT Data (last #{days} days):
      Average: #{avg}%
      Total responses: #{responses.size}
      #{lines.join("\n")}
    DATA
  end

  def active?
    user_has_permission('report_manage')
  end
end
