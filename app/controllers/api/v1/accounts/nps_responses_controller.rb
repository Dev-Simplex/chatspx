class Api::V1::Accounts::NpsResponsesController < Api::V1::Accounts::BaseController
  include Sift
  include DateRangeHelper

  RESULTS_PER_PAGE = 25

  before_action :check_authorization
  before_action :set_nps_responses, only: [:index, :metrics, :download]
  before_action :set_current_page, only: [:index]
  before_action :set_current_page_responses, only: [:index]
  before_action :set_total_sent_count, only: [:metrics]

  sort_on :created_at, type: :datetime

  def index; end

  def metrics
    Rails.logger.info "NPS Responses Controller: Metrics - Total responses: #{@nps_responses.count}"
    
    # Get only responded NPS responses for metrics calculation
    responded_responses = @nps_responses.where(status: :responded).where.not(score: nil)
    
    Rails.logger.info "NPS Responses Controller: Metrics - Responded count: #{responded_responses.count}"
    
    @total_count = responded_responses.count
    @scores_count = responded_responses.group(:score).count
    @status_count = @nps_responses.group(:status).count
    @promoters_count = responded_responses.promoters.count
    @passives_count = responded_responses.passives.count
    @detractors_count = responded_responses.detractors.count
    @blocked_count = @nps_responses.where(status: :dismissed).count
    @blocked_by_label_count = @nps_responses.where(status: :dismissed)
                                            .where.not(blocked_by_label: nil)
                                            .group(:blocked_by_label)
                                            .count
    delay_relation = responded_responses
                     .where.not(sent_at: nil)
                     .where.not(answered_at: nil)
    delay_expression = Arel.sql('EXTRACT(EPOCH FROM answered_at - sent_at)')
    if delay_relation.exists?
      @average_response_delay_seconds = delay_relation.average(delay_expression)&.to_f
      @fastest_response_delay_seconds = delay_relation.minimum(delay_expression)&.to_f
      @slowest_response_delay_seconds = delay_relation.maximum(delay_expression)&.to_f
    else
      @average_response_delay_seconds = nil
      @fastest_response_delay_seconds = nil
      @slowest_response_delay_seconds = nil
    end

    Rails.logger.info "NPS Responses Controller: Metrics - Total: #{@total_count}, Promoters: #{@promoters_count}, Passives: #{@passives_count}, Detractors: #{@detractors_count}"
  end

  def download
    response.headers['Content-Type'] = 'text/csv'
    response.headers['Content-Disposition'] = 'attachment; filename=nps_report.csv'
    render layout: false, template: 'api/v1/accounts/nps_responses/download', formats: [:csv]
  end

  def show_by_conversation
    conversation = Current.account.conversations.find(params[:conversation_id])
    authorize conversation, :show?
    
    # Get the latest NPS response for this conversation
    @nps_response = conversation.nps_responses.order(created_at: :desc).first
    if @nps_response
      render 'api/v1/models/nps_response'
    else
      render json: nil, status: :not_found
    end
  rescue StandardError => e
    Rails.logger.error "Error fetching NPS response for conversation #{params[:conversation_id]}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: e.message }, status: :internal_server_error
  end

  def send_survey
    conversation = Current.account.conversations.find(params[:conversation_id])
    authorize conversation, :show?
    authorize NpsResponse, :send_survey?

    NpsSurveyService.new(conversation: conversation, mode: 'manual').perform

    render json: { message: 'NPS survey sent successfully' }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize NpsResponse
  end

  def set_total_sent_count
    @nps_messages = Current.account.messages.input_nps
    @nps_messages = @nps_messages.where(created_at: range) if range.present?
    @total_sent_count = @nps_messages.count
  end

  def set_nps_responses
    base_query = Current.account.nps_responses.includes([:conversation, :assigned_agent, :contact, :inbox])
    
    Rails.logger.info "NPS Responses Controller: Base query count: #{base_query.count}"
    Rails.logger.info "NPS Responses Controller: Range: #{range.inspect}"
    Rails.logger.info "NPS Responses Controller: Params: #{params.inspect}"
    
    # Apply filtrate first (for sorting)
    filtered_query = filtrate(base_query)
    Rails.logger.info "NPS Responses Controller: After filtrate count: #{filtered_query.count}"
    
    # Then apply date range filter
    @nps_responses = filtered_query.filter_by_created_at(range)
    Rails.logger.info "NPS Responses Controller: After date filter count: #{@nps_responses.count}"
    
    # Apply other filters
    @nps_responses = @nps_responses.filter_by_assigned_agent_id(params[:user_ids])
                                    .filter_by_inbox_id(params[:inbox_id])
                                    .filter_by_status(params[:status])
    
    Rails.logger.info "NPS Responses Controller: After all filters count: #{@nps_responses.count}"
    
    # Filter by contact_id if provided
    if params[:contact_id].present?
      @nps_responses = @nps_responses.where(contact_id: params[:contact_id])
      Rails.logger.info "NPS Responses Controller: After contact_id filter count: #{@nps_responses.count}"
    end
  end

  def set_current_page_responses
    @nps_responses = @nps_responses.page(@current_page).per(RESULTS_PER_PAGE)
  end

  def set_current_page
    @current_page = params[:page] || 1
  end
end
