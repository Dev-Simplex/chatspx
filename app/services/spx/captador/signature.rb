module Spx::Captador::Signature
  def self.v2(secret:, timestamp:, method:, path:, identifier:, header_name:, header_value:, body:)
    canonical = [
      'v2', timestamp.to_s, method.to_s.upcase, path.to_s, identifier.to_s,
      "#{header_name.to_s.downcase}:#{header_value}", Digest::SHA256.hexdigest(body.to_s)
    ].join("\n")
    "v2=#{OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, canonical)}"
  end
end
