# frozen_string_literal: true

class UpdateBanner
  include Redis::RedisKeys

  class << self
    def enable(message)
      data = {
        enabled: true,
        message: message.to_s
      }

      Redis::Alfred.set(Redis::RedisKeys::UPDATE_BANNER, data.to_json)
      data
    end

    def disable
      Redis::Alfred.delete(Redis::RedisKeys::UPDATE_BANNER)
      { enabled: false }
    end

    def active?
      info[:enabled] == true
    end

    def info
      json_data = Redis::Alfred.get(Redis::RedisKeys::UPDATE_BANNER)
      return { enabled: false } if json_data.blank?

      parsed_data = JSON.parse(json_data)
      {
        enabled: parsed_data['enabled'] || false,
        message: parsed_data['message'] || ''
      }
    rescue JSON::ParserError, StandardError => e
      Rails.logger.error("Erro ao buscar banner de atualização: #{e.message}") if defined?(Rails)
      { enabled: false }
    end
  end
end

