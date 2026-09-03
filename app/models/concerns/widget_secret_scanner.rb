# Bloco 5.01 — a varredura de segredo da config publica do widget.
#
# Mora fora de `WidgetConfigurable` porque e responsabilidade propria: recebe um no de config e
# devolve o NOME da chave ofensora, ou nil. Quem decide a mensagem e quem chama.
#
# Duas camadas, e cada uma pega o que a outra deixa passar:
#   por NOME  — `access_token`, `apiKey`, `password`... o disfarce obvio
#   por VALOR — chave de nome inocente carregando um token de verdade
#
# A terceira camada, e a principal, nao esta aqui: e o `additionalProperties: false` do schema, que
# recusa TUDO que nao foi declarado publico. Esta aqui e a rede que continua valendo se um schema
# futuro afrouxar.
module WidgetSecretScanner
  # `(\z|_)` no fim pega o termo no MEIO do nome (`access_token_v2`), nao so no fim. `session` e
  # `cookie` ficam FORA de proposito: sao palavras de tracking legitimo (`session_timeout`), e
  # falso positivo aqui recusa config de quem nao fez nada errado.
  SECRET_KEY_TERMS = %w[
    token secret password passwd pwd credential credentials
    api_key apikey private_key privatekey auth authorization signature salt bearer
  ].freeze
  SECRET_KEY_PATTERN = /(\A|_)(#{SECRET_KEY_TERMS.join('|')})(\z|_)/i

  # Prefixos publicados pelas proprias plataformas — nunca heuristica de "string longa aleatoria",
  # que barraria `google_ads_send_to` e outros identificadores publicos compridos e legitimos.
  SECRET_VALUE_PATTERNS = [
    /\Aey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\./,  # JWT
    /\AEAA[A-Za-z0-9]{20,}/,                         # Meta (user/system token)
    /\A(sk|rk)_(live|test)_[A-Za-z0-9]{16,}/,        # Stripe
    /\AAIza[A-Za-z0-9_-]{30,}/,                      # Google API key
    /\Agh[pousr]_[A-Za-z0-9]{20,}/,                  # GitHub
    /\Axox[baprs]-[A-Za-z0-9-]{10,}/,                # Slack
    /\ABearer\s+\S{10,}/i,                           # cabecalho colado no campo
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/             # PEM
  ].freeze

  module_function

  # `apiKey` e `api_key` sao o mesmo segredo com duas grafias.
  def normalize_key(key)
    key.to_s.gsub(/([a-z0-9])([A-Z])/, '\1_\2').downcase
  end

  # Varre em profundidade: segredo dentro de objeto aninhado ou de array vaza igual ao de topo.
  def offending_key_name(node)
    case node
    when Hash then node.lazy.filter_map { |key, value| offending_in_pair(key, value) }.first
    when Array then node.lazy.filter_map { |item| offending_key_name(item) }.first
    end
  end

  # Devolve o NOME da chave que carrega o valor suspeito — nunca o valor: a mensagem vai para a
  # tela e para o log, e ecoar o segredo ali seria publica-lo num terceiro lugar.
  def offending_value_holder(node, owner = nil)
    case node
    when Hash then node.lazy.filter_map { |key, value| offending_value_holder(value, key) }.first
    when Array then node.lazy.filter_map { |item| offending_value_holder(item, owner) }.first
    when String then owner.to_s if secret_value?(node)
    end
  end

  def secret_value?(value)
    SECRET_VALUE_PATTERNS.any? { |pattern| value.match?(pattern) }
  end

  def offending_in_pair(key, value)
    return key.to_s if normalize_key(key).match?(SECRET_KEY_PATTERN)

    offending_key_name(value)
  end
end
