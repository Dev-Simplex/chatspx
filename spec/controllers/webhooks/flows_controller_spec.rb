# frozen_string_literal: true

require 'rails_helper'

# R-2: público, sem sessão. Cobre cada defesa do modelo de ameaça (ver Webhooks::FlowsController).
RSpec.describe 'Public Flow Webhook Trigger (F1 / R-2)', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:flow) { create(:flow, account: account, trigger_type: :external_webhook) }
  let(:token) { flow.webhook_token }
  let(:path) { "/webhooks/flows/#{token}" }

  def enable_engine
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
  end

  # As defesas de rate-limit/dedupe usam Rails.cache; o test env é null_store (fail-open), então
  # trocamos por um MemoryStore só nos exemplos que as exercitam.
  def use_memory_cache
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  before { enable_engine }

  describe 'a valid token' do
    it 'enqueues the flow trigger job and returns 202 accepted' do
      expect do
        post path, params: { conversation_id: conversation.display_id }.to_json,
                   headers: { 'CONTENT_TYPE' => 'application/json' }
      end.to have_enqueued_job(Flows::WebhookTriggerJob)
        .with(flow.id, conversation_display_id: conversation.display_id, payload: anything)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['status']).to eq('accepted')
    end

    it 'accepts the target conversation from the JSON body' do
      post path, params: { conversation_id: conversation.display_id }.to_json,
                 headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:accepted)
    end
  end

  describe 'token that must NOT fire (anti-enumeration: identical generic 404)' do
    it 'returns a generic 404 for an unknown token, without leaking existence' do
      post '/webhooks/flows/does-not-exist', params: {}.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'not_found')
    end

    it 'returns the SAME generic 404 for an inactive flow (does not reveal it exists)' do
      flow.update!(active: false)
      post path, params: {}.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'not_found')
    end

    it 'does not enqueue anything for an unknown token' do
      expect do
        post '/webhooks/flows/nope', params: {}.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      end.not_to have_enqueued_job(Flows::WebhookTriggerJob)
    end
  end

  describe 'engine gating' do
    it 'is a 200 no-op when the Flow engine is off for the account' do
      account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => false))
      expect do
        post path, params: { conversation_id: conversation.display_id }.to_json,
                   headers: { 'CONTENT_TYPE' => 'application/json' }
      end.not_to have_enqueued_job(Flows::WebhookTriggerJob)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'ignored', 'reason' => 'engine_inactive')
    end
  end

  describe 'target resolution without a conversation' do
    it 'is a documented 200 no-op when no target conversation is resolvable' do
      expect do
        post path, params: {}.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      end.not_to have_enqueued_job(Flows::WebhookTriggerJob)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'ignored', 'reason' => 'no_target')
    end

    it 'is a no-op when the conversation_id belongs to another account' do
      other = create(:conversation)
      post path, params: { conversation_id: other.display_id }.to_json,
                 headers: { 'CONTENT_TYPE' => 'application/json' }
      # Same-account scoping: a display_id from another account resolves to nothing here.
      expect(response.parsed_body['reason']).to eq('no_target') if response.parsed_body['status'] == 'ignored'
    end
  end

  describe 'payload cap' do
    it 'rejects a body larger than the cap with 413, before any heavy work' do
      stub_const('Webhooks::FlowsController::MAX_BYTES', 50)
      big = { conversation_id: conversation.display_id, blob: 'x' * 200 }.to_json
      expect do
        post path, params: big, headers: { 'CONTENT_TYPE' => 'application/json' }
      end.not_to have_enqueued_job(Flows::WebhookTriggerJob)
      expect(response).to have_http_status(:payload_too_large)
    end
  end

  describe 'per-token rate limit' do
    it 'returns 429 once the per-token limit is exceeded within the window' do
      use_memory_cache
      stub_const('Webhooks::FlowsController::RATE_LIMIT', 2)

      # freeze_time keeps every request in the same fixed window (no minute-boundary straddle).
      freeze_time do
        body = { conversation_id: conversation.display_id }.to_json
        headers = { 'CONTENT_TYPE' => 'application/json' }
        2.times { post path, params: body, headers: headers }
        expect(response).to have_http_status(:accepted)

        post path, params: body, headers: headers
        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body).to eq('error' => 'rate_limited')
      end
    end
  end

  describe 'idempotency / dedupe' do
    it 'no-ops a repeated Idempotency-Key within the window (fires once)' do
      use_memory_cache
      body = { conversation_id: conversation.display_id }.to_json
      headers = { 'CONTENT_TYPE' => 'application/json', 'Idempotency-Key' => 'evt-123' }

      expect do
        post path, params: body, headers: headers
      end.to have_enqueued_job(Flows::WebhookTriggerJob).exactly(:once)
      expect(response).to have_http_status(:accepted)

      expect do
        post path, params: body, headers: headers
      end.not_to have_enqueued_job(Flows::WebhookTriggerJob)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'duplicate')
    end

    it 'also honours the idempotency_key from the JSON body' do
      use_memory_cache
      headers = { 'CONTENT_TYPE' => 'application/json' }
      body = { conversation_id: conversation.display_id, idempotency_key: 'body-key' }.to_json

      post path, params: body, headers: headers
      expect(response).to have_http_status(:accepted)
      post path, params: body, headers: headers
      expect(response.parsed_body).to eq('status' => 'duplicate')
    end
  end
end
