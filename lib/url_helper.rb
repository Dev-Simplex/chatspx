require 'uri'
require 'addressable/uri'

module UrlHelper
  # Chaves em `additional_attributes`. `referer` é o dado bom (URL http(s) válida);
  # `referer_raw` é o que nem escapando virou URL — guardado cru para diagnóstico, nunca
  # servido ao widget nem injetado em prompt de IA (bloco 1.20, asserção 5).
  REFERER_KEY = 'referer'.freeze
  REFERER_RAW_KEY = 'referer_raw'.freeze
  REFERER_RAW_MAX_LENGTH = 2048

  def url_valid?(url)
    url = begin
      URI.parse(url)
    rescue StandardError
      false
    end
    url.is_a?(URI::HTTP) || url.is_a?(URI::HTTPS)
  end

  # Devolve a URL http(s) utilizável, ou `nil` se não houver nenhuma.
  #
  # `URI.parse` (RFC 3986) reprova URL de site real que só está mal escapada: espaço cru no path
  # e colchete cru no path são os dois casos que mais aparecem em CMS e campanha. Reprovar
  # significava apagar a origem do lead (`referer = nil`), e é o que explica os 0 de 3.180 [M12].
  #
  # A URL que já valida sai INTACTA — a normalização só roda no caminho de recuperação, para não
  # reescrever silenciosamente URL boa (case do host, porta default, re-encode do path).
  # E a normalização não muda o esquema: `javascript:`, `data:` e `file:` continuam reprovados.
  def sanitized_url(url)
    return nil if url.blank?
    return url if url_valid?(url)

    escaped = escape_url(url)
    return escaped if escaped.present? && url_valid?(escaped)

    nil
  end

  # Sanea `attributes['referer']` no lugar. Contrato:
  #   URL válida ou recuperável  -> `referer` recebe a versão utilizável e `referer_raw` some
  #   não recuperável            -> `referer` vira nil e o valor cru vai para `referer_raw`
  #   vazio/ausente              -> `referer` vira nil e `referer_raw` NÃO é criado (nada a preservar)
  def sanitize_referer_attribute!(attributes)
    raw = attributes[REFERER_KEY]
    sanitized = sanitized_url(raw)

    if sanitized.present?
      attributes[REFERER_KEY] = sanitized
      attributes.delete(REFERER_RAW_KEY)
    else
      attributes[REFERER_KEY] = nil
      store_raw_referer(attributes, raw)
    end

    attributes
  end

  private

  def store_raw_referer(attributes, raw)
    value = raw.to_s
    return attributes.delete(REFERER_RAW_KEY) if value.blank?

    attributes[REFERER_RAW_KEY] = value[0, REFERER_RAW_MAX_LENGTH]
  end

  def escape_url(url)
    Addressable::URI.parse(url).normalize.to_s
  rescue StandardError
    nil
  end
end
