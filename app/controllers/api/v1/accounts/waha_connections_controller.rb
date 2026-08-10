# frozen_string_literal: true

class Api::V1::Accounts::WahaConnectionsController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  # Inbox apontando para uma sessão que não existe mais no WAHA (apagada,
  # renomeada, nunca criada). É o pior estado possível — nada entrega — e antes
  # era o único invisível, porque a lista era montada a partir das sessões.
  MISSING_STATUS = 'MISSING'
  HEALTH_CACHE_TTL = 30.seconds

  before_action :check_authorization
  before_action :set_waha_service
  before_action :find_account_inbox!, only: %i[show qr_code connect disconnect restart destroy]

  def index
    @inboxes = waha_inboxes
    sessions_by_name = @waha_service.list_sessions(all: true).index_by { |session| session['name'] }

    # Itera as INBOXES (não as sessões): assim a inbox sem sessão correspondente
    # aparece como MISSING em vez de sumir da lista.
    @connections = @inboxes.map do |inbox|
      session = sessions_by_name[inbox.waha_session_name]
      session ? format_connection(session, inbox) : format_missing_connection(inbox)
    end

    render json: @connections
  rescue Waha::ApiService::Error => e
    Rails.logger.error("WAHA API error listing connections: #{e.message}")
    render json: { error: 'Failed to fetch WAHA connections' }, status: :service_unavailable
  end

  # Saúde por inbox, liberada para qualquer usuário da conta (ver policy).
  # Carga leve e cacheada: todo agente logado consulta isso em ciclo.
  def health
    sessions_by_name = cached_sessions_by_name
    # WAHA inacessível não é prova de linha caída — silêncio é melhor que alarme falso.
    return render json: [] if sessions_by_name.nil?

    render json: waha_inboxes.map { |inbox|
      { inbox_id: inbox.id, inbox_name: inbox.name, status: session_status(sessions_by_name, inbox) }
    }
  end

  def show
    session = @waha_service.get_session(params[:id])

    render json: format_connection(session, @inbox)
  rescue Waha::ApiService::NotFoundError
    render json: { error: 'Session not found' }, status: :not_found
  rescue Waha::ApiService::Error => e
    Rails.logger.error("WAHA API error fetching session #{params[:id]}: #{e.message}")
    render json: { error: 'Failed to fetch WAHA session' }, status: :service_unavailable
  end

  def create # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    session_name = params[:session_name]
    inbox_name = params[:inbox_name]

    if session_name.blank? || inbox_name.blank?
      return render json: { error: 'Session name and inbox name are required' }, status: :unprocessable_entity
    end

    # Create WAHA session
    @waha_service.create_session(name: session_name)

    # Create inbox with API channel
    channel = nil
    ActiveRecord::Base.transaction do
      channel = Channel::Api.create!(
        account: Current.account
      )

      @inbox = Current.account.inboxes.create!(
        name: inbox_name,
        channel: channel,
        waha_session_name: session_name,
        lock_to_single_conversation: true
      )
    end

    # Create Chatwoot App in WAHA
    chatwoot_base_url = ENV.fetch('FRONTEND_URL', request.base_url).to_s.chomp('/')

    # Ensure user has an access token
    unless current_user.access_token
      current_user.create_access_token
      current_user.reload
    end

    # Validate all required fields
    raise StandardError, 'Failed to create access token for user' if current_user.access_token&.token.blank?

    raise StandardError, 'Channel identifier is missing' if channel.identifier.blank?

    app_config = {
      url: chatwoot_base_url,
      accountId: Current.account.id.to_i,
      accountToken: current_user.access_token.token,
      inboxId: @inbox.id.to_i,
      inboxIdentifier: channel.identifier,
      locale: 'pt-BR',
      agentSignatureEnabled: true
    }

    Rails.logger.info("Creating Chatwoot app in WAHA with config: #{app_config.except(:accountToken).inspect}")

    begin
      @waha_service.create_chatwoot_app(
        session_name: session_name,
        config: app_config
      )

      # Configure webhook URL in channel (WAHA endpoint where Chatwoot sends messages)
      waha_base_url = ENV.fetch('WAHA_API_URL', 'http://localhost:3000').to_s.chomp('/')
      app_id = "chatwoot-#{session_name}"
      webhook_url = "#{waha_base_url}/webhooks/chatwoot/#{session_name}/#{app_id}"
      channel.update!(webhook_url: webhook_url)

      Rails.logger.info('Chatwoot app created successfully in WAHA')
      Rails.logger.info("Webhook URL configured: #{webhook_url}")
    rescue Waha::ApiService::Error => e
      error_message = e.message
      Rails.logger.error("Failed to create Chatwoot app in WAHA: #{error_message}")
      Rails.logger.error("Error details: #{e.inspect}")
      Rails.logger.error("Config that failed: #{app_config.except(:accountToken).inspect}")

      render json: {
        error: 'Failed to create Chatwoot app in WAHA'
      }, status: :unprocessable_entity
      return
    end

    # Start the session
    @waha_service.start_session(session_name)

    session = @waha_service.get_session(session_name)
    render json: format_connection(session, @inbox), status: :created
  rescue Waha::ApiService::Error => e
    Rails.logger.error("WAHA API Error during create: #{e.message}")
    render json: { error: 'Failed to create WAHA connection' }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    # Clean up WAHA session if inbox creation failed
    begin
      @waha_service.delete_session(session_name)
    rescue StandardError
      nil
    end
    Rails.logger.error("Record invalid during WAHA create: #{e.message}")
    render json: { error: 'Failed to create inbox for WAHA connection' }, status: :unprocessable_entity
  end

  def qr_code
    session_name = params[:id]

    # Sempre retorna imagem PNG diretamente
    qr_image = @waha_service.get_qr_code(session_name, format: 'image')
    send_data qr_image, type: 'image/png', disposition: 'inline'
  rescue Waha::ApiService::NotFoundError
    render json: { error: 'Session not found' }, status: :not_found
  rescue Waha::ApiService::Error => e
    Rails.logger.error("WAHA API error fetching QR code: #{e.message}")
    render json: { error: 'Failed to fetch QR code' }, status: :service_unavailable
  end

  def connect
    session_name = params[:id]
    @waha_service.start_session(session_name)

    session = @waha_service.get_session(session_name)

    render json: format_connection(session, @inbox)
  rescue Waha::ApiService::Error => e
    Rails.logger.error("WAHA API error connecting session #{params[:id]}: #{e.message}")
    render json: { error: 'Failed to connect WAHA session' }, status: :unprocessable_entity
  end

  def disconnect
    session_name = params[:id]
    @waha_service.stop_session(session_name)

    session = @waha_service.get_session(session_name)

    render json: format_connection(session, @inbox)
  rescue Waha::ApiService::Error => e
    Rails.logger.error("WAHA API error disconnecting session #{params[:id]}: #{e.message}")
    render json: { error: 'Failed to disconnect WAHA session' }, status: :unprocessable_entity
  end

  def restart # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    session_name = params[:id]

    begin
      Rails.logger.info('=== RESTART START ===')
      Rails.logger.info("Session name: #{session_name}")
      Rails.logger.info("Inbox found: #{@inbox.id}")

      # Use WAHA's native restart endpoint
      Rails.logger.info('Calling restart_session...')
      restart_result = @waha_service.restart_session(session_name)
      Rails.logger.info("Restart result: #{restart_result.inspect}")
      Rails.logger.info("Restart result class: #{restart_result.class}")

      # Brief wait for session to be ready
      sleep(0.5)

      # Get updated session
      Rails.logger.info('Getting session after restart...')
      session = @waha_service.get_session(session_name)
      Rails.logger.info("Session after restart: #{session.inspect}")

      if session.blank?
        Rails.logger.error('Session is nil or empty after restart')
        return render json: { error: 'Session not found after restart' }, status: :unprocessable_entity
      end

      # Format and return
      Rails.logger.info('Calling format_connection...')
      formatted = format_connection(session, @inbox)
      Rails.logger.info("Formatted connection: #{formatted.inspect}")
      Rails.logger.info('=== RESTART SUCCESS ===')

      render json: formatted
    rescue Waha::ApiService::NotFoundError => e
      Rails.logger.error("WAHA session not found: #{e.message}")
      render json: { error: 'Session not found' }, status: :not_found
    rescue Waha::ApiService::Error => e
      Rails.logger.error("WAHA restart error: #{e.message}")
      render json: { error: 'Failed to restart WAHA session' }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("WAHA restart unexpected error: #{e.class} - #{e.message}")
      Rails.logger.error("Backtrace: #{e.backtrace.first(5).join("\n")}")
      render json: { error: 'Internal error restarting connection' }, status: :internal_server_error
    end
  end

  def destroy
    session_name = params[:id]

    # Delete WAHA session
    @waha_service.delete_session(session_name)

    # Delete associated inbox
    @inbox.destroy

    head :ok
  rescue Waha::ApiService::Error => e
    Rails.logger.error("WAHA API error deleting session #{params[:id]}: #{e.message}")
    render json: { error: 'Failed to delete WAHA connection' }, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize :waha_connection
  end

  def set_waha_service
    @waha_service = Waha::ApiService.new
  end

  def find_account_inbox!
    @inbox = Current.account.inboxes.find_by(waha_session_name: params[:id])
    render json: { error: 'Connection not found' }, status: :not_found unless @inbox
  end

  def waha_inboxes
    Current.account.inboxes.where.not(waha_session_name: nil)
  end

  def session_status(sessions_by_name, inbox)
    session = sessions_by_name[inbox.waha_session_name]
    return MISSING_STATUS if session.nil?

    (session['status'] || session[:status] || 'UNKNOWN').to_s
  end

  # O `index` do admin NÃO usa este cache: lá o status precisa refletir na hora
  # o que o próprio admin acabou de conectar/desconectar.
  def cached_sessions_by_name
    Rails.cache.fetch('waha/sessions_by_name', expires_in: HEALTH_CACHE_TTL) do
      @waha_service.list_sessions(all: true).index_by { |session| session['name'] }
    end
  rescue Waha::ApiService::Error => e
    Rails.logger.error("WAHA API error fetching session health: #{e.message}")
    nil
  end

  def format_missing_connection(inbox)
    {
      id: inbox.waha_session_name,
      session_name: inbox.waha_session_name,
      status: MISSING_STATUS,
      inbox_id: inbox.id,
      inbox_name: inbox.name,
      phone_number: nil,
      created_at: inbox.created_at,
      updated_at: inbox.updated_at
    }
  end

  def format_connection(session, inbox) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    # Ensure we have a hash
    session_hash = if session.is_a?(Hash)
                     session
                   elsif session.respond_to?(:to_h)
                     session.to_h
                   else
                     {}
                   end

    # Try to get session name from various possible keys
    session_name = session_hash['name'] || session_hash[:name] ||
                   session_hash['session'] || session_hash[:session]

    unless session_name
      Rails.logger.error("Invalid session format: #{session_hash.inspect}")
      raise StandardError, 'Invalid session format: session name not found'
    end

    session_name_str = session_name.to_s

    # Fetch me_info safely
    me_info = nil
    begin
      me_info = fetch_me_info(session_name_str)
    rescue StandardError => e
      Rails.logger.warn("Failed to fetch me_info for #{session_name_str}: #{e.message}")
      me_info = nil
    end

    {
      id: session_name_str,
      session_name: session_name_str,
      status: (session_hash['status'] || session_hash[:status] || 'UNKNOWN').to_s,
      inbox_id: inbox&.id,
      inbox_name: inbox&.name,
      phone_number: format_phone_number(me_info&.dig('id')),
      created_at: session_hash['createdAt'] || session_hash[:createdAt] ||
        (session_hash['timestamps'].is_a?(Hash) ? session_hash['timestamps']['created'] : nil) ||
        (session_hash[:timestamps].is_a?(Hash) ? session_hash[:timestamps][:created] : nil) ||
        inbox&.created_at,
      updated_at: session_hash['updatedAt'] || session_hash[:updatedAt] ||
        (session_hash['timestamps'].is_a?(Hash) ? session_hash['timestamps']['updated'] : nil) ||
        (session_hash[:timestamps].is_a?(Hash) ? session_hash[:timestamps][:updated] : nil) ||
        inbox&.updated_at
    }
  rescue StandardError => e
    Rails.logger.error("Error in format_connection: #{e.message}")
    Rails.logger.error("Session data: #{session.inspect}")
    Rails.logger.error("Inbox data: #{inbox.inspect}")
    raise
  end

  def fetch_me_info(session_name)
    return nil unless session_name

    @waha_service.get_session_me(session_name)
  rescue Waha::ApiService::Error
    nil
  end

  def format_phone_number(phone)
    return nil unless phone

    # Remove sufixo @c.us do formato do WhatsApp
    phone.to_s.split('@').first
  end
end
