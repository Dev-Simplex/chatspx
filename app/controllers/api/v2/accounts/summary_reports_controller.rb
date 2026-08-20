class Api::V2::Accounts::SummaryReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :prepare_builder_params, only: [:agent, :agent_assignment, :team, :inbox, :label, :channel]

  def agent
    render_report_with(V2::Reports::AgentSummaryBuilder, type: :agent)
  end

  # Relatório de Atribuições por Agente (quem atribuiu pra quem). Renderiza o builder direto
  # (contagens, não métricas de tempo) — não passa pelo enriquecimento de signals do #agent.
  # Retorna { rows: contagens por agente, matrix: pares autor→destino }.
  def agent_assignment
    builder = V2::Reports::AgentAssignmentBuilder.new(account: Current.account, params: @builder_params)
    render json: { rows: builder.build, matrix: builder.matrix }
  end

  def team
    render_report_with(V2::Reports::TeamSummaryBuilder, type: :team)
  end

  def inbox
    render_report_with(V2::Reports::InboxSummaryBuilder, type: :inbox)
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
      business_hours: ActiveModel::Type::Boolean.new.cast(permitted_params[:business_hours]),
      team_id: permitted_params[:team_id],
      inbox_id: permitted_params[:inbox_id]
    }
  end

  def render_report_with(builder_class, type: nil)
    builder_params = type.present? ? @builder_params.merge(type: type) : @builder_params
    builder = builder_class.new(account: Current.account, params: builder_params)
    data = builder.build
    # Enriquece cada linha (entidade) com o semáforo estruturado (aditivo). O TL;DR da
    # média é agregado no frontend a partir destes signals. Channel devolve hash → intacto.
    data = data.map { |row| row.merge(signals: Reports::SummarySignals.for_row(row)) } if data.is_a?(Array)
    render json: data
  end

  def permitted_params
    params.permit(:since, :until, :business_hours, :team_id, :inbox_id)
  end

  def date_range_too_long?
    return false if permitted_params[:since].blank? || permitted_params[:until].blank?

    since_time = Time.zone.at(permitted_params[:since].to_i)
    until_time = Time.zone.at(permitted_params[:until].to_i)
    (until_time - since_time) > 6.months
  end
end
