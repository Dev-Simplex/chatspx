# frozen_string_literal: true

class Waha::ApiService # rubocop:disable Metrics/ClassLength
  class Error < StandardError; end
  class ConnectionError < Error; end
  class AuthenticationError < Error; end
  class NotFoundError < Error; end

  def initialize
    @base_url = ENV.fetch('WAHA_API_URL', 'http://localhost:3000')
    @api_key = ENV.fetch('WAHA_API_KEY', nil)
    # Keep below Rack::Timeout (15s) so Net::ReadTimeout fires first and we
    # surface a friendly error instead of a hard 500.
    @timeout = 8
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

  def edit_message(session_name, chat_id, message_id, new_content)
    put(
      "/api/#{session_name}/chats/#{encode_path_segment(chat_id)}/messages/#{encode_path_segment(message_id)}",
      { text: new_content }
    )
  end

  # Revokes a message for everyone (delete-for-everyone).
  # WAHA: DELETE /api/{session}/chats/{chatId}/messages/{messageId}
  def delete_message(session_name, chat_id, message_id)
    delete("/api/#{session_name}/chats/#{encode_path_segment(chat_id)}/messages/#{encode_path_segment(message_id)}")
  end

  # Fetch chat messages. Optional server-side filters:
  # - timestamp_gte: only messages with timestamp >= value (unix seconds) via filter.timestamp.gte
  # - from_me: when false, only inbound messages via filter.fromMe=false
  # WAHA docs: https://waha.devlike.pro/docs/how-to/messages/
  def get_messages(session_name, chat_id, limit: 20, timestamp_gte: nil, from_me: nil)
    params = { limit: limit }
    params[:'filter.timestamp.gte'] = timestamp_gte.to_i if timestamp_gte.present?
    params[:'filter.fromMe'] = from_me unless from_me.nil?
    get("/api/#{session_name}/chats/#{encode_path_segment(chat_id)}/messages", params)
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

  def check_contact_exists(session_name:, phone:)
    get('/api/contacts/check-exists', phone: phone, session: session_name)
  end

  # GET /api/{session}/lids - list known LID to phone number mappings.
  # Used as fallback when get_lid_phone_number returns pn: null.
  # WAHA docs: https://waha.devlike.pro/docs/how-to/contacts/
  def get_lids_list(session_name, limit: 500, offset: 0)
    get("/api/#{session_name}/lids", limit: limit, offset: offset)
  end

  def get_groups(session_name)
    get("/api/#{session_name}/groups")
  end

  # Sends a WhatsApp location message via WAHA REST.
  # Used as fallback path for outbound location messages when the standard
  # SendReplyJob pipeline doesn't carry the coordinates through.
  # WAHA docs: https://waha.devlike.pro/docs/how-to/send-messages/#location
  def send_location(session:, chat_id:, latitude:, longitude:, accuracy: nil)
    payload = {
      session: session,
      chatId: chat_id,
      latitude: latitude,
      longitude: longitude
    }
    payload[:accuracy] = accuracy if accuracy
    post('/api/sendLocation', payload)
  end

  # Send a saved contact card (vCard) via WAHA when we have the WhatsApp JID
  # (contactId) of the person being shared. WAHA renders this as a tappable
  # contact card in the recipient's WhatsApp.
  #
  # WAHA payload uses `contactsIds` (plural ARRAY) — confirmed via official docs:
  # https://waha.devlike.pro/docs/how-to/send-messages/#contact-vcard
  def send_contact_vcard(session:, chat_id:, contact_ids:)
    ids = Array(contact_ids).compact.reject(&:blank?)
    payload = { session: session, chatId: chat_id, contactsIds: ids }
    post('/api/sendContactVcard', payload)
  end

  # Fallback path for "Telefone livre": we have a name + raw phone number but no
  # WhatsApp JID. We build a vCard 3.0 string and ship it through /api/sendText.
  # The recipient sees the vCard inline; long-press still allows saving on most
  # WhatsApp clients.
  def send_text_with_vcard(session:, chat_id:, name:, phone:)
    payload = {
      session: session,
      chatId: chat_id,
      text: build_vcard(name: name, phone: phone)
    }
    post('/api/sendText', payload)
  end

  # Builds a minimal vCard 3.0 (FN + TEL CELL). Strips CR/LF from name and
  # normalizes phone to E.164-ish. Public so callers (and specs) can verify the
  # exact wire format without going through HTTP.
  def build_vcard(name:, phone:)
    safe_name = name.to_s.tr("\r\n", ' ').strip
    digits = phone.to_s.gsub(/[^\d+]/, '')
    digits = "+#{digits}" unless digits.start_with?('+')
    [
      'BEGIN:VCARD',
      'VERSION:3.0',
      "FN:#{safe_name}",
      "TEL;TYPE=CELL:#{digits}",
      'END:VCARD'
    ].join("\n")
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

  # Encode a path segment but preserve @ so WAHA accepts WhatsApp JIDs like 5511@c.us
  def encode_path_segment(segment)
    CGI.escape(segment.to_s).gsub('%40', '@')
  end

  def get(path, params = {})
    request(:get, path, params)
  end

  def post(path, body = {})
    request(:post, path, body)
  end

  def delete(path)
    request(:delete, path)
  end

  def put(path, body = {})
    request(:put, path, body)
  end

  def request(method, path, params = {}, raw: false) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    uri = URI.join(@base_url, path)
    uri.query = URI.encode_www_form(params) if method == :get && params.any?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = @timeout
    http.open_timeout = @timeout

    request_class = case method
                    when :get then Net::HTTP::Get
                    when :post then Net::HTTP::Post
                    when :put then Net::HTTP::Put
                    when :delete then Net::HTTP::Delete
                    end

    request = request_class.new(uri)
    request['X-Api-Key'] = @api_key if @api_key.present?

    if %i[post put].include?(method) && params.any?
      request['Content-Type'] = 'application/json'
      json_body = params.to_json
      Rails.logger.info("WAHA API - Sending #{method.upcase} to #{uri.path} with body: #{json_body}")
      request.body = json_body
    end

    response = http.request(request)

    return response if raw

    handle_response(response)
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    raise ConnectionError, "WAHA API timeout: #{e.message}"
  rescue SocketError, Errno::ECONNREFUSED => e
    raise ConnectionError, "Cannot connect to WAHA API: #{e.message}"
  end

  def handle_response(response) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
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
