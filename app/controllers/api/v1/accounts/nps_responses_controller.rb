class Api::V1::Accounts::NpsResponsesController < Api::V1::Accounts::BaseController
  include Sift
  include DateRangeHelper

  RESULTS_PER_PAGE = 25

  before_action :check_authorization
  before_action :set_nps_responses, only: [:index, :download]
  before_action :set_current_page, only: [:index]
  before_action :set_current_page_responses, only: [:index]

  sort_on :created_at, type: :datetime

  def index
    response.headers['X-Total-Count'] = @nps_responses.total_count.to_s
  end

  # Métricas apuradas sobre UM coorte (por created_at, respeitando agente/inbox/
  # contato) — numerador e denominador da taxa de resposta saem do mesmo coorte,
  # e o cálculo do NPS vem da fonte única Reports::NpsCalculator.
  def metrics
    cohort = metrics_cohort
    responded = cohort.where(status: :responded).where.not(score: nil).trusted
    calculator = Reports::NpsCalculator.new(
      responded_scope: responded,
      sent_count: cohort.where(status: %i[sent responded expired]).count,
      previous_score: previous_period_nps_score
    )
    @metrics = calculator.to_h
    @status_count = cohort.group(:status).count
    assign_blocked_counts(cohort)
    @detractor_followup = Reports::NpsDetractorFollowup.new(responded).to_h
    @signals = Reports::SignalSet.new(entries: [{ metric: :nps, value: @metrics[:nps_score] }]).build
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
    Rails.logger.error e.backtrace.first(5).join("\n")
    render json: { error: 'Failed to fetch NPS response' }, status: :internal_server_error
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

  def assign_blocked_counts(cohort)
    @blocked_count = cohort.where(status: :dismissed).count
    @blocked_by_label_count = cohort.where(status: :dismissed)
                                    .where.not(blocked_by_label: nil)
                                    .group(:blocked_by_label)
                                    .count
  end

  # Base filtrada (agente/inbox/contato), SEM recorte de data — o coorte por
  # created_at é aplicado por cima, tanto no período atual quanto no anterior.
  def metrics_filtered_base
    @metrics_filtered_base ||= begin
      scope = Current.account.nps_responses
                     .filter_by_assigned_agent_id(params[:user_ids])
                     .filter_by_inbox_id(params[:inbox_id])
      scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].present?
      scope
    end
  end

  # Coorte do período: pesquisas criadas dentro do range (ou tudo, se sem range).
  def metrics_cohort
    range.present? ? metrics_filtered_base.where(created_at: range) : metrics_filtered_base
  end

  # NPS do período imediatamente anterior, de mesma duração (nil se não há range
  # ou não há respostas anteriores) — alimenta o delta em pontos.
  def previous_period_nps_score
    return nil if range.blank?

    duration = range.last - range.first
    previous_range = (range.first - duration)...range.first
    counts = metrics_filtered_base.where(created_at: previous_range)
                                  .where(status: :responded).where.not(score: nil).trusted
                                  .group(:score).count
    return nil if counts.values.sum.zero?

    Reports::NpsCalculator.score_from_counts(counts)
  end

  def check_authorization
    authorize NpsResponse
  end

  def set_nps_responses # rubocop:disable Metrics/AbcSize
    base_query = Current.account.nps_responses.includes([:conversation, :assigned_agent, :contact, :inbox])
    filtered_query = filtrate(base_query)
    @nps_responses = filtered_query.filter_by_created_at(range)

    # Apply other filters (response_state takes precedence over status for list view)
    @nps_responses = @nps_responses.filter_by_assigned_agent_id(params[:user_ids])
                                   .filter_by_inbox_id(params[:inbox_id])
    @nps_responses = if params[:response_state].present?
                       @nps_responses.filter_by_response_state(params[:response_state])
                     else
                       @nps_responses.filter_by_status(params[:status])
                     end

    @nps_responses = @nps_responses.where(contact_id: params[:contact_id]) if params[:contact_id].present?
  end

  def set_current_page_responses
    @nps_responses = @nps_responses.page(@current_page).per(RESULTS_PER_PAGE)
  end

  def set_current_page
    @current_page = params[:page] || 1
  end
end
