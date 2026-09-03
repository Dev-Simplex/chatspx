# frozen_string_literal: true

# Bloco 5.19 — o JWT de identidade do visitante, formato ADICIONAL ao HMAC (decisao I2).
#
# QUEM ASSINA E O SERVIDOR DO CLIENTE, com o mesmo segredo do HMAC de hoje
# (`channel_web_widgets.hmac_token`). O visitante nao assina nada: ele carrega um token que ja
# recebeu pronto. Isso e deliberado e nao pode mudar — exigir assinatura do visitante desligaria a
# coleta de e-mail do pre-chat inteira em toda inbox estrita, porque o segredo nao esta no navegador.
#
# O que o JWT resolve que o HMAC nao resolve: o HMAC prova UM campo (`identifier`) e nada mais, entao
# email, nome e telefone chegam sempre sem prova. No JWT eles vao dentro do payload assinado, e por
# isso passam a ser atributos AUTENTICADOS.
#
# Este servico nao decide nada sobre a requisicao. Ele responde uma pergunta so — "este token prova
# uma identidade?" — e quem decide o que fazer com a resposta e a maquina de estados do bloco 4.15
# (`desativado` / `observado` / `obrigatorio`). Um segundo caminho de decisao aqui seria a receita do
# defeito de juncao que este plano ja pagou uma vez.
class Widget::IdentityTokenService
  # `sub` e a identidade; `exp` e obrigatorio porque, sem validade, um token vazado vale para sempre.
  REQUIRED_CLAIMS = %w[sub exp].freeze

  # O que o cliente pode afirmar sobre a pessoa dentro do token assinado. Fora desta lista, nada
  # atravessa: um `role` ou um `account_id` no payload nao pode virar atributo do contato.
  AUTHENTICATED_ATTRIBUTES = %w[email name phone_number avatar_url].freeze

  # Fixo. Aceitar o algoritmo que o token declara e a armadilha classica de JWT: o atacante escolhe
  # `none` e assina o que quiser.
  ALGORITHM = 'HS256'

  Result = Struct.new(:status, :identifier, :attributes, keyword_init: true) do
    # :verified e o unico estado que prova identidade. :absent, :expired e :invalid nao provam nada —
    # e nenhum deles e erro por si: quem decide se a ausencia de prova recusa a requisicao e o 4.15.
    def verified?
      status == :verified
    end
  end

  def initialize(token:, hmac_token:)
    @token = token.to_s
    @hmac_token = hmac_token
  end

  def perform
    return failure(:absent) if @token.blank?
    return failure(:invalid) if @hmac_token.blank?

    payload = decode
    return failure(:invalid) if payload.nil?

    subject = payload['sub'].to_s.strip
    return failure(:invalid) if subject.blank?

    Result.new(status: :verified, identifier: subject, attributes: authenticated_attributes(payload))
  rescue JWT::ExpiredSignature
    failure(:expired)
  rescue JWT::DecodeError
    failure(:invalid)
  end

  private

  def decode
    JWT.decode(@token, @hmac_token, true, algorithm: ALGORITHM, required_claims: REQUIRED_CLAIMS).first
  end

  # Escalar apenas: um hash ou array aqui viraria estrutura dentro de um campo de contato que espera
  # texto, e o erro apareceria longe daqui.
  def authenticated_attributes(payload)
    payload.slice(*AUTHENTICATED_ATTRIBUTES)
           .select { |_key, value| value.is_a?(String) || value.is_a?(Numeric) }
           .transform_values(&:to_s)
  end

  def failure(status)
    Result.new(status: status, identifier: nil, attributes: {})
  end
end
