##############################################
# Helpers to implement date range filtering to APIs
# Include in your controller or service class where params is available
##############################################

module DateRangeHelper
  def range
    # Treat 0 as blank/nil - 0 is not a valid timestamp
    since = params[:since]
    until_param = params[:until]

    return if since.blank? || until_param.blank? || since.to_i.zero? || until_param.to_i.zero?

    parse_date_time(since)...parse_date_time(until_param)
  end

  def parse_date_time(datetime)
    return datetime if datetime.is_a?(DateTime)
    return datetime.to_datetime if datetime.is_a?(Time) || datetime.is_a?(Date)

    DateTime.strptime(datetime, '%s')
  end
end
