# Recebe webhooks Meta Lead Ads (Facebook/Instagram).
# - GET  /webhooks/meta_lead_ads  -> challenge (subscription verification)
# - POST /webhooks/meta_lead_ads  -> leadgen events (valida HMAC, enfileira job)
class Webhooks::MetaLeadAdsController < ActionController::API
  def verify
    if Meta::LeadAds::TokenVerifier.valid?(params['hub.verify_token'])
      Rails.logger.info('Meta Lead Ads webhook verified')
      render plain: params['hub.challenge']
    else
      render status: :unauthorized, json: { error: 'Invalid verify token' }
    end
  end

  def process_payload
    raw = request.raw_post

    unless Meta::LeadAds::SignatureVerifier.valid?(
      raw_payload: raw,
      signature_header: request.headers['X-Hub-Signature-256']
    )
      Rails.logger.warn('Meta Lead Ads webhook: invalid signature')
      head :unauthorized
      return
    end

    payload = JSON.parse(raw)
    Webhooks::MetaLeadAdsJob.perform_later(payload)
    head :ok
  rescue JSON::ParserError => e
    Rails.logger.warn("Meta Lead Ads webhook: invalid JSON - #{e.message}")
    head :bad_request
  end
end
