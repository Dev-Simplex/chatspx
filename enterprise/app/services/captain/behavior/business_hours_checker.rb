class Captain::Behavior::BusinessHoursChecker
  def initialize(assistant:)
    @assistant = assistant
    @config = assistant.behavior['business_hours'] || {}
  end

  def status
    return :inside unless @config['enabled']

    now = Time.current.in_time_zone(resolved_timezone)
    inside_hours?(now) ? :inside : :outside
  end

  private

  def resolved_timezone
    ActiveSupport::TimeZone[@config['timezone'] || 'UTC']
  end

  def inside_hours?(now)
    day_entry = (@config['schedule'] || []).find { |d| d['day'] == now.wday }
    return false if day_entry.blank?

    (day_entry['ranges'] || []).any? do |range|
      now.between?(parse_time(range['start'], now), parse_time(range['end'], now))
    end
  end

  def parse_time(time_str, reference)
    hours, minutes = time_str.split(':').map(&:to_i)
    reference.change(hour: hours, min: minutes, sec: 0)
  end
end
