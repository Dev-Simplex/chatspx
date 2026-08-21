class Webhooks::InstagramController < ActionController::API
  include MetaTokenVerifyConcern

  def events
    Rails.logger.info('Instagram webhook received events')
    if params['object'].casecmp('instagram').zero?
      entry_params = params.to_unsafe_hash[:entry]

      if contains_echo_event?(entry_params)
        # Add delay to prevent race condition where echo arrives before send message API completes
        # This avoids duplicate messages when echo comes early during API processing
        ::Webhooks::InstagramEventsJob.set(wait: 2.seconds).perform_later(entry_params)
      else
        ::Webhooks::InstagramEventsJob.perform_later(entry_params)
      end

      render json: :ok
    else
      Rails.logger.warn("Message is not received from the instagram webhook event: #{params['object']}")
      head :unprocessable_entity
    end
  end

  private

  def contains_echo_event?(entry_params)
    return false unless entry_params.is_a?(Array)

    entry_params.any? do |entry|
      # Check messaging array for echo events
      messaging_events = entry[:messaging] || []
      messaging_events.any? { |messaging| messaging.dig(:message, :is_echo).present? }
    end
  end

  # Valida contra IG_VERIFY_TOKEN (canal Instagram via pagina do Facebook) e
  # INSTAGRAM_VERIFY_TOKEN (canal Instagram via login direto).
  #
  # As guardas abaixo NAO sao zelo: sem elas a verificacao passava SEM TOKEN NENHUM.
  # `GlobalConfigService.load('IG_VERIFY_TOKEN', '')` devolve nil quando a variavel esta
  # ausente ou vazia (e o .env desta VM a tem vazia), e `params['hub.verify_token']` tambem e
  # nil quando nao vem na query. `nil == nil` e true — entao um GET limpo em
  # /webhooks/instagram, numa instalacao que nao configurou o verify token, recebia 200 com o
  # challenge ecoado, completando o handshake da Meta para quem quisesse.
  #
  # Mesmo formato ja usado em `Meta::LeadAds::TokenVerifier`: recusa token vazio, ignora
  # esperado vazio e compara em tempo constante.
  def valid_token?(token)
    return false if token.blank?

    esperados = [
      GlobalConfigService.load('IG_VERIFY_TOKEN', nil),
      GlobalConfigService.load('INSTAGRAM_VERIFY_TOKEN', nil)
    ].compact_blank

    esperados.any? { |esperado| ActiveSupport::SecurityUtils.secure_compare(esperado.to_s, token.to_s) }
  end
end
