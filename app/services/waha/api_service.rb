# frozen_string_literal: true

module Waha
  class ApiService
    class Error < StandardError; end
    class ConnectionError < Error; end
    class AuthenticationError < Error; end
    class NotFoundError < Error; end

    def initialize
      @base_url = ENV.fetch('WAHA_API_URL', 'http://localhost:3000')
      @api_key = ENV.fetch('WAHA_API_KEY', nil)
      @timeout = 30
    end

    def list_sessions(all: true)
      get('/api/sessions', all: all)
    end

    def create_session(name:, config: {})
      post('/api/sessions', {
        name: name,
        config: config,
        start: false
      })
    end

    def get_session(name)
      get("/api/sessions/#{name}")
    end

    def start_session(name)
      post("/api/sessions/#{name}/start", {})
    end

    def stop_session(name)
      post("/api/sessions/#{name}/stop", {})
    end

    def restart_session(name)
      # Restart endpoint: POST with empty body
      # Use the generic post method with empty hash - it won't send body if params is empty
      post("/api/sessions/#{name}/restart", {})
    end

    def delete_session(name)
      delete("/api/sessions/#{name}")
    end

    def get_qr_code(name, format: 'image')
      response = request(:get, "/api/#{name}/auth/qr", { format: format }, raw: true)
      
      if format == 'image'
        response.body
      else
        JSON.parse(response.body)
      end
    end

    def get_session_me(name)
      get("/api/sessions/#{name}/me")
    end

    def get_lid_phone_number(session_name, lid)
      encoded_lid = URI.encode_www_form_component(lid)
      get("/api/#{session_name}/lids/#{encoded_lid}")
    end

    def create_chatwoot_app(session_name:, config:)
      request_body = {
        enabled: true,
        id: "chatwoot-#{session_name}",
        session: session_name,
        app: 'chatwoot',
        config: config
      }
      
      Rails.logger.info("WAHA API - Creating app with body: #{request_body.to_json}")
      
      post('/api/apps', request_body)
    end

    private

    def get(path, params = {})
      request(:get, path, params)
    end

    def post(path, body = {})
      request(:post, path, body)
    end

    def delete(path)
      request(:delete, path)
    end

    def request(method, path, params = {}, raw: false)
      uri = URI.join(@base_url, path)
      uri.query = URI.encode_www_form(params) if method == :get && params.any?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = @timeout
      http.open_timeout = @timeout

      request_class = case method
                      when :get then Net::HTTP::Get
                      when :post then Net::HTTP::Post
                      when :delete then Net::HTTP::Delete
                      end

      request = request_class.new(uri)
      request['X-Api-Key'] = @api_key if @api_key.present?

      if method == :post
        if params.any?
          request['Content-Type'] = 'application/json'
          json_body = params.to_json
          Rails.logger.info("WAHA API - Sending POST to #{uri.path} with body: #{json_body}")
          request.body = json_body
        end
        # For empty body (like restart), don't set Content-Type or body
        # The request will be sent without body, matching the curl -d '' behavior
      end

      response = http.request(request)

      return response if raw

      handle_response(response)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise ConnectionError, "WAHA API timeout: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED => e
      raise ConnectionError, "Cannot connect to WAHA API: #{e.message}"
    end

    def handle_response(response)
      case response.code.to_i
      when 200..299
        return {} if response.body.blank?

        JSON.parse(response.body)
      when 401
        raise AuthenticationError, 'Invalid WAHA API key'
      when 404
        raise NotFoundError, 'Session not found'
      else
        error_data = begin
          parsed = JSON.parse(response.body)
          error_message = parsed['message'] || parsed['error'] || response.body
          
          # Log detailed error for 400/422 (validation errors)
          if [400, 422].include?(response.code.to_i)
            Rails.logger.error("WAHA API validation error (#{response.code}):")
            Rails.logger.error("Response body: #{response.body}")
            Rails.logger.error("Parsed error: #{parsed.inspect}")
            
            # Include validation details in error message if available
            if parsed['message'].is_a?(Array)
              error_message = parsed['message'].join(', ')
            elsif parsed['message'].is_a?(String)
              error_message = parsed['message']
            end
          end
          
          error_message
        rescue StandardError => e
          Rails.logger.error("Failed to parse error response: #{e.message}")
          response.body
        end
        
        raise Error, "WAHA API error (#{response.code}): #{error_data}"
      end
    end
  end
end

