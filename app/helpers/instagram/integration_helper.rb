module Instagram::IntegrationHelper
  # O MÍNIMO pra existir canal de Instagram: ler o perfil e trocar DM. Nunca some da tela de
  # consentimento, venha o que vier na configuração.
  REQUIRED_SCOPES = %w[instagram_business_basic instagram_business_manage_messages].freeze

  # Escopo é propriedade do APP da Meta, e o app é POR BOX (`INSTAGRAM_APP_ID` é
  # InstallationConfig). A .232 usa o `Business MW`, que tem a permissão de comentários; a Tozi
  # usa o `SPX Lead Ads Tozi`, que não tem. Enquanto a lista foi uma constante global, as duas
  # pediam a mesma coisa — e escopo que o app não possui faz o OAuth falhar por escopo inválido,
  # ou seja, ninguém mais conecta Instagram naquela box.
  #
  # Consequência prática que isto conserta: em 18/08 a permissão de comentários da BigStore foi
  # obtida montando a URL de consentimento à mão. Reconectar a inbox pelo botão do SPX pedia só
  # os dois escopos daqui e PERDIA a permissão conquistada, em silêncio.
  #
  # A configuração ACRESCENTA; nunca remove. Lista mal preenchida não derruba o DM.
  def instagram_scopes
    extras = GlobalConfigService.load('INSTAGRAM_SCOPES', '').to_s.split(',').map(&:strip).compact_blank

    (REQUIRED_SCOPES + extras).uniq
  end

  # Generates a signed JWT token for Instagram integration
  #
  # @param account_id [Integer] The account ID to encode in the token
  # @return [String, nil] The encoded JWT token or nil if client secret is missing
  def generate_instagram_token(account_id)
    return if client_secret.blank?

    JWT.encode(token_payload(account_id), client_secret, 'HS256')
  rescue StandardError => e
    Rails.logger.error("Failed to generate Instagram token: #{e.message}")
    nil
  end

  def token_payload(account_id)
    {
      sub: account_id,
      iat: Time.current.to_i
    }
  end

  # Verifies and decodes a Instagram JWT token
  #
  # @param token [String] The JWT token to verify
  # @return [Integer, nil] The account ID from the token or nil if invalid
  def verify_instagram_token(token)
    return if token.blank? || client_secret.blank?

    decode_token(token, client_secret)
  end

  private

  def client_secret
    @client_secret ||= GlobalConfigService.load('INSTAGRAM_APP_SECRET', nil)
  end

  def decode_token(token, secret)
    JWT.decode(token, secret, true, {
                 algorithm: 'HS256',
                 verify_expiration: true
               }).first['sub']
  rescue StandardError => e
    Rails.logger.error("Unexpected error verifying Instagram token: #{e.message}")
    nil
  end
end
