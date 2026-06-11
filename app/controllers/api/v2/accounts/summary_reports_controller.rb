class Api::V2::Accounts::SummaryReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :prepare_builder_params, only: [:agent, :team, :inbox, :label, :channel]

  def agent
    render_report_with(V2::Reports::AgentSummaryBuilder)
  end

  def team
    render_report_with(V2::Reports::TeamSummaryBuilder)
  end

  def inbox
    render_report_with(V2::Reports::InboxSummaryBuilder)
  end

  def label
    render_report_with(V2::Reports::LabelSummaryBuilder)
  end

  def channel
    return render_could_not_create_error(I18n.t('errors.reports.date_range_too_long')) if date_range_too_long?

    render_report_with(V2::Reports::ChannelSummaryBuilder)
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def prepare_builder_params
    @builder_params = {
      since: permitted_params[:since],
      until: permitted_params[:until],
      business_hours: ActiveModel::Type::Boolean.new.cast(permitted_params[:business_hours])
    }
  end

  def render_report_with(builder_class)
    builder = builder_class.new(account: Current.account, params: @builder_params)
    data = builder.build
    # Enriquece cada linha (entidade) com o semáforo estruturado (aditivo). O TL;DR da
    # média é agregado no frontend a partir destes signals. Channel devolve hash → intacto.
    data = data.map { |row| row.merge(signals: Reports::SummarySignals.for_row(row)) } if data.is_a?(Array)
    render json: data
  end

  def permitted_params
    params.permit(:since, :until, :business_hours)
  end

  def date_range_too_long?
    return false if permitted_params[:since].blank? || permitted_params[:until].blank?

    since_time = Time.zone.at(permitted_params[:since].to_i)
    until_time = Time.zone.at(permitted_params[:until].to_i)
    (until_time - since_time) > 6.months
  end
end
