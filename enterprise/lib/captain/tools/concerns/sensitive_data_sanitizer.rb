module Captain::Tools::SensitiveDataSanitizer
  REDACTED = '[REDACTED]'.freeze
  REDACTED_CPF = '[REDACTED_CPF]'.freeze
  REDACTED_PHONE = '[REDACTED_PHONE]'.freeze
  REDACTED_SIGNED_URL = '[REDACTED_SIGNED_URL]'.freeze

  CPF_KEY_PATTERN = /(?:^|[_-])cpf(?:$|[_-])/i
  PHONE_KEY_PATTERN = /(?:^|[_-])(?:phone(?:_number)?|telefone|fone\d*|whatsapp|mobile)(?:$|[_-])/i
  SIGNED_URL_KEY_PATTERN = /(?:^|[_-])signed[_-]?url(?:$|[_-])/i
  SECRET_KEY_PATTERN = /(?:authorization|password|passwd|secret|token|api[_-]?key|signature|credential|hmac)/i
  SIGNED_QUERY_PATTERN = /(?:(?:[?&]|&amp;)(?:token|signature|sig|key|credential|x-amz-[^=]*|expires|hmac)=)/i
  URL_PATTERN = %r{(?:https?://|/)[^\s<>"']+}i
  CPF_PATTERN = /(?<!\d)(?:\d{3}[.\s-]?){2}\d{3}-?\d{2}(?!\d)/
  PHONE_PATTERN = /(?<!\d)(?:\+?55[\s.-]?)?\(?\d{2}\)?[\s.-]?(?:9?\d{4})[\s.-]?\d{4}(?!\d)/
  JWT_PATTERN = /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?:\.[A-Za-z0-9_-]{8,})?\b/
  BEARER_PATTERN = /\bBearer\s+[A-Za-z0-9._~+\/-]+=*/i
  INLINE_SECRET_PATTERN = /["']?\b(?:token|api[_-]?key|authorization|password|passwd|secret|signature|hmac)\b["']?\s*[:=]\s*["']?[^\s,;}"']+["']?/i
  CONTROL_CHARACTER_PATTERN = /[\x00-\x08\x0B\x0C\x0E-\x1F]/

  module_function

  def sanitize(value)
    case value
    when String
      sanitize_string(value)
    when Array
      value.map { |item| sanitize(item) }
    when Hash
      value.each_with_object({}) do |(key, item), sanitized|
        sanitized[key] = redaction_for_key(key) || sanitize(item)
      end
    else
      value
    end
  end

  def sanitize_string(value)
    value
      .gsub(CONTROL_CHARACTER_PATTERN, '')
      .gsub(URL_PATTERN) { |url| url.match?(SIGNED_QUERY_PATTERN) ? REDACTED_SIGNED_URL : url }
      .gsub(BEARER_PATTERN, REDACTED)
      .gsub(JWT_PATTERN, REDACTED)
      .gsub(INLINE_SECRET_PATTERN, REDACTED)
      .gsub(CPF_PATTERN, REDACTED_CPF)
      .gsub(PHONE_PATTERN, REDACTED_PHONE)
  end

  def redaction_for_key(key)
    key = key.to_s
    return REDACTED_CPF if key.match?(CPF_KEY_PATTERN)
    return REDACTED_PHONE if key.match?(PHONE_KEY_PATTERN)
    return REDACTED_SIGNED_URL if key.match?(SIGNED_URL_KEY_PATTERN)
    return REDACTED if key.match?(SECRET_KEY_PATTERN)
  end
end
