class Api::V1::Accounts::CsatSurveyResponsesController < Api::V1::Accounts::BaseController
  include Sift
  include DateRangeHelper

  RESULTS_PER_PAGE = 25

  before_action :check_authorization
  before_action :set_csat_survey_responses, only: [:index, :metrics, :download]
  before_action :set_current_page, only: [:index]
  before_action :set_current_page_surveys, only: [:index]
  before_action :set_total_sent_messages_count, only: [:metrics]

  sort_on :created_at, type: :datetime

  def index; end

  def metrics
    @total_count = @csat_survey_responses.count
    @total_response_count_for_rate = @csat_survey_responses_for_rate.count
    @ratings_count = @csat_survey_responses.group(:rating).count
    # Sem resposta nao ha satisfacao para julgar: o 0% viraria "Atencao" no veredito.
    entries = @total_count.zero? ? [] : [{ metric: :csat, value: csat_satisfaction_score }]
    @signals = Reports::SignalSet.new(entries: entries).build
  end

  def download
    response.headers['Content-Type'] = 'text/csv'
    response.headers['Content-Disposition'] = 'attachment; filename=csat_report.csv'
    render layout: false, template: 'api/v1/accounts/csat_survey_responses/download', formats: [:csv]
  end

  private

  # Satisfação = % de respostas com nota 4 ou 5 (mesma definição do PDF e do frontend).
  def csat_satisfaction_score
    return 0 if @total_count.zero?

    satisfied = @ratings_count.values_at(4, 5).compact.sum
    ((satisfied.to_f / @total_count) * 100).round
  end

  def set_total_sent_messages_count
    @csat_messages = Current.account.messages.input_csat
    @csat_messages = @csat_messages.where(created_at: range) if range.present?
    @csat_messages = filter_sent_csat_messages(@csat_messages)
    @total_sent_messages_count = @csat_messages.count
  end

  def filter_sent_csat_messages(messages)
    messages = messages.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    messages = messages.joins(:conversation).where(conversations: { team_id: params[:team_id] }) if params[:team_id].present?
    # Sent surveys use the conversation's current assignee as the agent proxy; responses store assigned_agent_id at response time.
    messages = messages.joins(:conversation).where(conversations: { assignee_id: params[:user_ids] }) if params[:user_ids].present?
    messages
  end

  def set_csat_survey_responses
    base_query = Current.account.csat_survey_responses.includes([:conversation, :assigned_agent, :contact])
    @csat_survey_responses_for_rate = filtrate(base_query).filter_by_created_at(range)
                                                          .filter_by_assigned_agent_id(params[:user_ids])
                                                          .filter_by_inbox_id(params[:inbox_id])
                                                          .filter_by_team_id(params[:team_id])
    @csat_survey_responses = @csat_survey_responses_for_rate.filter_by_rating(params[:rating])
  end

  def set_current_page_surveys
    @csat_survey_responses = @csat_survey_responses.page(@current_page).per(RESULTS_PER_PAGE)
  end

  def set_current_page
    @current_page = params[:page] || 1
  end
end

Api::V1::Accounts::CsatSurveyResponsesController.prepend_mod_with('Api::V1::Accounts::CsatSurveyResponsesController')
