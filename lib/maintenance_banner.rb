# frozen_string_literal: true

class MaintenanceBanner
  include Redis::RedisKeys

  class << self
    def enable(message, scheduled_at = nil)
      data = {
        enabled: true,
        message: message.to_s,
        scheduled_at: scheduled_at ? parse_scheduled_at(scheduled_at) : nil
      }.compact

      Redis::Alfred.set(Redis::RedisKeys::MAINTENANCE_BANNER, data.to_json)
      data
    end

    def disable
      Redis::Alfred.delete(Redis::RedisKeys::MAINTENANCE_BANNER)
      { enabled: false }
    end

    def active?
      info[:enabled] == true
    end

    def info
      json_data = Redis::Alfred.get(Redis::RedisKeys::MAINTENANCE_BANNER)
      return { enabled: false } if json_data.blank?

      parsed_data = JSON.parse(json_data)
      {
        enabled: parsed_data['enabled'] || false,
        message: parsed_data['message'] || '',
        scheduled_at: parsed_data['scheduled_at']
      }
    rescue JSON::ParserError, StandardError => e
      Rails.logger.error("Erro ao buscar banner de manutenção: #{e.message}") if defined?(Rails)
      { enabled: false }
    end

    private

    def parse_scheduled_at(scheduled_at)
      return nil if scheduled_at.blank?

      time = case scheduled_at
             when String
               Time.zone.parse(scheduled_at) || Time.parse(scheduled_at)
             when Time, DateTime
               scheduled_at
             else
               nil
             end

      time&.utc&.iso8601
    end
  end
end

