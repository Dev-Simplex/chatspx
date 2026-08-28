class V2::Reports::Timeseries::BaseTimeseriesBuilder
  include TimezoneHelper
  include DateRangeHelper
  DEFAULT_GROUP_BY = 'day'.freeze

  pattr_initialize :account, :params

  def scope
    case params[:type].to_sym
    when :account
      account
    when :inbox
      inbox
    when :agent
      user
    when :label
      label
    when :team
      team
    end
  end

  def inbox
    @inbox ||= account.inboxes.find(params[:id])
  end

  def user
    @user ||= account.users.find(params[:id])
  end

  def label
    @label ||= account.labels.find(params[:id])
  end

  def team
    @team ||= account.teams.find(params[:id])
  end

  # Recorte por caixa de entrada (o numero). E ortogonal ao type/id: permite pedir
  # "o agente X, so no numero de vendas". conversations, messages e reporting_events
  # tem a coluna inbox_id, e o Rails qualifica a condicao com a tabela da relacao.
  def inbox_ids
    @inbox_ids ||= Array(params[:inbox_id]).reject(&:blank?).map(&:to_i)
  end

  def with_inbox_filter(relation)
    return relation if inbox_ids.blank?

    relation.where(inbox_id: inbox_ids)
  end

  def group_by
    @group_by ||= %w[day week month year hour].include?(params[:group_by]) ? params[:group_by] : DEFAULT_GROUP_BY
  end

  def timezone
    @timezone ||= timezone_name_from_offset(params[:timezone_offset])
  end
end
