module Integrations::Openai::KeyValidator
  TIMEOUT_SECONDS = 5
  DEFAULT_ENDPOINT = 'https://api.openai.com/'.freeze

  def self.valid?(api_key)
    return false if api_key.blank?

    connection = Faraday.new do |f|
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = TIMEOUT_SECONDS
    end

    response = connection.get("#{api_base}/models") do |req|
      req.headers['Authorization'] = "Bearer #{api_key}"
    end

    return true if response.status == 401 && custom_endpoint?

    response.status != 401
  rescue Faraday::Error => e
    Rails.logger.warn("[openai-key-validator] #{e.class}: #{e.message}")
    true
  end

  def self.endpoint
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence
  end

  def self.api_base
    "#{(endpoint || DEFAULT_ENDPOINT).chomp('/')}/v1"
  end

  # ChatSPX: fail-open no 401 quando a instalação aponta para um endpoint próprio.
  #
  # Este validador é chamado de DOIS lugares que decidem sobre credencial de cliente:
  # `Integrations::Hook#validate_openai_api_key` (HTTP síncrono DENTRO do save — 401 rejeita a
  # gravação) e `Migration::ValidateOpenaiHooksJob` (401 destrói o hook). Nos dois, o veredito de
  # "chave inválida" sai de um `GET {api_base}/v1/models`.
  #
  # Contra `api.openai.com` isso é confiável. Contra um gateway/proxy próprio não é: é comum um
  # gateway liberar só `/chat/completions` e devolver 401 (ou 403/404 mapeado para 401) em
  # `/models`, com a chave perfeitamente válida. O efeito na frota seria o admin NÃO CONSEGUIR
  # salvar uma chave boa, e o job apagar as integrações de IA da VM inteira.
  #
  # Não se pode assumir que gateway de terceiro implementa `/models`, então quando há endpoint
  # customizado o 401 deixa de ser prova de chave morta: registramos e liberamos. Contra o endpoint
  # default da OpenAI o comportamento do upstream continua igual.
  def self.custom_endpoint?
    custom = endpoint
    return false if custom.blank?

    Rails.logger.warn(
      "[openai-key-validator] 401 em #{api_base}/models com endpoint customizado (#{custom}) — " \
      'tratando como VÁLIDA: gateway próprio pode não implementar /models.'
    )
    true
  end
end
