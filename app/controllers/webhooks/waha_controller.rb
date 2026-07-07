# frozen_string_literal: true

# Receives WAHA session-level webhooks for events the external "chatwoot" app
# does not relay (poll votes). Registered on the WAHA session as a webhook with
# an HMAC secret; we verify the signature before enqueuing.
#
# Route: POST /webhooks/waha/:session_name
class Webhooks::WahaController < ActionController::API
  def process_payload
    return head :unauthorized unless valid_signature?

    Webhooks::WahaEventsJob.perform_later(
      event: params[:event].to_s,
      session: (params[:session].presence || params[:session_name]).to_s,
      payload: payload_hash
    )
    head :ok
  end

  private

  def payload_hash
    raw = params[:payload]
    return {} if raw.blank?

    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
  end

  # WAHA signs the raw body with HMAC-SHA512 using the configured key and sends it
  # in the X-Webhook-Hmac header. We reuse the WAHA API key as the secret. When no
  # secret is configured we accept (the handler is self-limiting: it only acts on
  # votes that match a poll WE sent).
  def valid_signature?
    secret = webhook_secret
    return true if secret.blank?

    provided = request.headers['X-Webhook-Hmac'].to_s
    return false if provided.blank?

    expected = OpenSSL::HMAC.hexdigest('SHA512', secret, request.raw_post)
    ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end

  def webhook_secret
    ENV['WAHA_WEBHOOK_HMAC'].presence || ENV.fetch('WAHA_API_KEY', nil).presence
  end
end
