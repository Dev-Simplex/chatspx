# frozen_string_literal: true

# F1 (R-2 — MAIOR risco de segurança do motor Flow): endpoint PÚBLICO que dispara Flows a partir
# de um POST externo. `POST /webhooks/flows/:token`.
#
# MODELO DE AMEAÇA — quem pode chamar e o que é validado
#   Qualquer origem na internet pode POSTar aqui: NÃO há sessão, cookie, nem API key. A ÚNICA
#   credencial é o `token` na URL (SecureRandom.hex(24) = 192 bits), que IDENTIFICA o flow — o id
#   sequencial nunca é exposto. Defesas, na ordem em que correm:
#     1. CAP DE PAYLOAD  — corpo > FLOW_WEBHOOK_MAX_BYTES (64KB) → 413, antes de qualquer trabalho
#        pesado. Um payload gigante não chega ao banco nem ao job.
#     2. RATE-LIMIT      — Rack::Attack por IP no path (edge, produção — rack_attack.rb) MAIS um
#        throttle por TOKEN aqui (Rails.cache/Redis, janela fixa) que também barra o flood de um
#        token válido vindo de IPs distribuídos. Backstop testável (Rack::Attack é off em teste).
#     3. TOKEN → FLOW    — lookup por igualdade (Flow.for_webhook_token) + re-verificação em tempo
#        constante (secure_compare). Token desconhecido OU flow inativo → 404 GENÉRICO idêntico:
#        NUNCA revela se um token/flow existe (anti-enumeração). O espaço de 192 bits torna
#        brute-force inviável.
#     4. ENGINE ATIVO    — conta com o motor Flow desligado → 200 no-op. O portador do token já é
#        autorizado; contar-lhe que o motor está ocioso não é vazamento sensível.
#     5. DEDUPE          — `Idempotency-Key` (header ou corpo) repetida na janela → 200 no-op, sem
#        re-disparar (webhooks externos re-entregam em retry). Sem chave, não há como deduplicar.
#     6. ALVO SEM CONVERSA — resolve uma conversa EXISTENTE por `conversation_id` (o display_id,
#        escopo da conta — NÃO o id global). NÃO fabricamos conversa de sistema (poluiria a inbox
#        e exigiria escolher inbox/contato; espelha a decisão do Flows::ScheduleTriggerJob). Sem
#        alvo resolvível → 200 no-op documentado.
#     7. PAYLOAD É SÓ DADO — o corpo NUNCA é executado nem renderizado. Entra apenas como dado de
#        COMPARAÇÃO nas condições (AutomationRules::ConditionsFilterService). As ações usam os
#        action_params do AUTOR do flow; o Liquid das ações expõe só contact/conversation/account
#        (Flows::ActionService#liquid_drops), nunca o payload — zero superfície de injeção.
#   A execução pesada (Flows::RunnerService) roda ASSÍNCRONA no Flows::WebhookTriggerJob: a
#   resposta HTTP volta rápido (202) e um atacante não consegue segurar conexões no processamento.
#
# CONTRATO
#   POST /webhooks/flows/:token   (Content-Type: application/json)
#   Corpo (todos opcionais): { "conversation_id": <display_id>, "idempotency_key": "...", ... }
#   Idempotency-Key também aceito via header `Idempotency-Key` / `X-Idempotency-Key`.
#   Respostas: 202 accepted | 200 {ignored|duplicate} | 404 not_found | 413 | 429.
class Webhooks::FlowsController < ActionController::API
  # Público por DESENHO: ActionController::API não tem autenticação nem CSRF (mesmo padrão dos
  # demais Webhooks::* — whatsapp/instagram/telegram). Nada a pular; a credencial é o token da URL.

  MAX_BYTES = ENV.fetch('FLOW_WEBHOOK_MAX_BYTES', 65_536).to_i
  RATE_LIMIT = ENV.fetch('FLOW_WEBHOOK_RATE_LIMIT', 60).to_i
  RATE_PERIOD = ENV.fetch('FLOW_WEBHOOK_RATE_PERIOD', 60).to_i # segundos
  DEDUPE_WINDOW = ENV.fetch('FLOW_WEBHOOK_DEDUPE_WINDOW', 600).to_i # segundos

  def create
    return render_error(:payload_too_large, 'payload_too_large') if payload_too_large?
    return render_error(:too_many_requests, 'rate_limited') if token_rate_limited?

    flow = authentic_flow
    return render_not_found if flow.nil?
    return render_ignored('engine_inactive') unless flow.account.flows_engine_enabled?
    return render_status('duplicate') if duplicate?(flow)

    trigger(flow)
  end

  private

  # Flow ATIVO cujo token casa exatamente, ou nil. Dobra token-desconhecido, flow-inativo e
  # mismatch num único nil → o `create` devolve o MESMO 404 genérico para os três (anti-enumeração:
  # não vaza se um token/flow existe).
  def authentic_flow
    flow = Flow.for_webhook_token(params[:token])
    return if flow.nil? || !flow.active?
    return unless token_matches?(flow)

    flow
  end

  def trigger(flow)
    conversation = target_conversation(flow)
    # Sem conversa-alvo resolvível → no-op seguro. NÃO criamos conversa de sistema (documentado).
    return render_ignored('no_target') if conversation.nil?

    Flows::WebhookTriggerJob.perform_later(
      flow.id, conversation_display_id: conversation.display_id, payload: safe_payload
    )
    render json: { status: 'accepted' }, status: :accepted
  end

  # Alvo = conversa EXISTENTE da conta do flow, resolvida por display_id (não o id global).
  # Espelha o contrato do Flows::ExecutionJob. NUNCA cria conversa.
  def target_conversation(flow)
    display_id = params[:conversation_id].presence || request_body['conversation_id'].presence
    return if display_id.blank?

    flow.account.conversations.find_by(display_id: display_id)
  end

  # Só o dado do webhook, já limitado em tamanho (raw_post <= MAX_BYTES) e vindo de JSON (estrutura
  # limitada). Serializável pelo ActiveJob. Consumido apenas como dado de comparação nas condições.
  def safe_payload
    { 'trigger' => 'external_webhook', 'webhook' => request_body }
  end

  # --- Defesas -----------------------------------------------------------------------------

  # Rejeita antes de qualquer trabalho pesado. Confere o header (clientes honestos) E o tamanho
  # real do corpo (um cliente que mente no Content-Length é pego pelo raw_post).
  def payload_too_large?
    return true if request.content_length.to_i > MAX_BYTES

    request.raw_post.bytesize > MAX_BYTES
  end

  # Throttle por token em janela FIXA (bucket por período, como o Rack::Attack faz por IP) — evita
  # o falso-positivo de janela deslizante em clientes de baixa taxa. Fail-open quando o cache não
  # conta (null_store em teste → increment devolve nil): o Rack::Attack por IP é a defesa de borda.
  def token_rate_limited?
    token = params[:token].to_s
    return false if token.blank?

    count = Rails.cache.increment(rate_cache_key(token), 1, expires_in: RATE_PERIOD * 2)
    count.present? && count > RATE_LIMIT
  end

  def rate_cache_key(token)
    window = Time.now.to_i / RATE_PERIOD
    # Hash do token na chave: o segredo cru nunca vira nome de chave no Redis.
    "flow_webhook:rate:#{Digest::SHA256.hexdigest(token)}:#{window}"
  end

  # Re-verificação em tempo constante do token já casado pelo SQL (defense-in-depth: guarda contra
  # qualquer casamento não-exato futuro; o custo é irrisório). Comprimentos diferentes → false.
  def token_matches?(flow)
    ActiveSupport::SecurityUtils.secure_compare(flow.webhook_token.to_s, params[:token].to_s)
  end

  # Idempotência: grava-se-se-ausente (atômico) na janela. false do write = já visto → duplicado.
  # Sem chave, não deduplica (retorna false). Fail-open no null_store (write devolve true sempre).
  def duplicate?(flow)
    key = idempotency_key
    return false if key.blank?

    !Rails.cache.write(dedupe_cache_key(flow, key), true, unless_exist: true, expires_in: DEDUPE_WINDOW)
  end

  def idempotency_key
    request.headers['Idempotency-Key'].presence ||
      request.headers['X-Idempotency-Key'].presence ||
      request_body['idempotency_key'].presence
  end

  def dedupe_cache_key(flow, key)
    "flow_webhook:dedupe:#{flow.id}:#{Digest::SHA256.hexdigest(key.to_s)}"
  end

  # --- Corpo / respostas -------------------------------------------------------------------

  # O JSON do cliente, parseado à mão a partir do raw_post — evita surpresas de parameter-wrapping
  # do ActionController::API e mantém o token (que vem do path) separado do dado do corpo.
  def request_body
    @request_body ||= parse_json_body
  end

  def parse_json_body
    raw = request.raw_post
    return {} if raw.blank?

    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def render_not_found
    render json: { error: 'not_found' }, status: :not_found
  end

  def render_error(status, code)
    render json: { error: code }, status: status
  end

  # Autorizado (token válido) mas não acionado: 200 com o motivo. Não é vazamento — o portador do
  # token já controla o gatilho deste flow.
  def render_ignored(reason)
    render json: { status: 'ignored', reason: reason }, status: :ok
  end

  def render_status(status_label)
    render json: { status: status_label }, status: :ok
  end
end
