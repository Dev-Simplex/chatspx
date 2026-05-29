#!/usr/bin/env bash
#
# waha-watchdog.sh — Standalone watchdog para WAHA (FORA do Rails).
#
# Monitora o processo WAHA (GET /ping) e o status de cada sessao
# (GET /api/sessions?all=true). Quando uma sessao nao esta WORKING
# (STOPPED/FAILED/etc.) ou o processo nao responde, aplica RESTART de
# SESSAO (POST /api/sessions/{name}/restart) — que NAO pede QR, pois a
# auth persiste em /app/.sessions (ou no Postgres). Nunca faz logout.
#
# Por padrao roda em ALERT_ONLY=true: apenas loga/alerta, sem reiniciar.
# Depois de validar a deteccao em producao, vire ALERT_ONLY=false para
# habilitar o auto-restart (ver README.md).
#
# Dependencias: bash, curl, jq.
#
# Config via ENV (ou arquivo waha-watchdog.env carregado pelo systemd):
#   WAHA_API_URL            URL base do WAHA (ex: https://waha.simplexsolucoes.com.br)
#   WAHA_API_KEY            API key (header X-Api-Key). Opcional se WAHA sem auth.
#   SESSIONS                Lista de sessoes separadas por espaco/virgula.
#                           Vazio = descobre todas via /api/sessions?all=true.
#   HEALTHY_STATUSES        Status considerados saudaveis (default: "WORKING").
#   ALERT_ONLY              true (default) = nunca reinicia, so alerta.
#   COOLDOWN_SECONDS        Espera minima entre restarts da MESMA sessao (default 300).
#   MAX_RESTARTS_PER_WINDOW Maximo de restarts por sessao na janela (default 3).
#   RESTART_WINDOW_SECONDS  Tamanho da janela do rate-limit (default 3600).
#   PING_RETRIES            Tentativas de /ping antes de declarar crash-loop (default 5).
#   PING_RETRY_DELAY        Backoff base (s) entre tentativas de /ping (default 5).
#   CURL_TIMEOUT            Timeout por request curl em segundos (default 10).
#   ALERT_WEBHOOK           URL opcional p/ POST de alertas (Slack/Discord/n8n).
#   STATE_DIR               Dir de estado (default /var/lib/waha-watchdog).
#   INBOUND_GAP_MONITOR     true = mede gap de inbound por sessao (SO-ALERTA, default false).
#   INBOUND_GAP_THRESHOLD   Segundos sem inbound novo p/ alertar (default 1800).
#
# Saida: stdout/stderr (capturado pelo journald quando rodando via systemd).

set -euo pipefail

# --------------------------------------------------------------------------
# Config + defaults
# --------------------------------------------------------------------------
WAHA_API_URL="${WAHA_API_URL:-http://localhost:3000}"
WAHA_API_KEY="${WAHA_API_KEY:-}"
SESSIONS="${SESSIONS:-}"
HEALTHY_STATUSES="${HEALTHY_STATUSES:-WORKING}"
ALERT_ONLY="${ALERT_ONLY:-true}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-300}"
MAX_RESTARTS_PER_WINDOW="${MAX_RESTARTS_PER_WINDOW:-3}"
RESTART_WINDOW_SECONDS="${RESTART_WINDOW_SECONDS:-3600}"
PING_RETRIES="${PING_RETRIES:-5}"
PING_RETRY_DELAY="${PING_RETRY_DELAY:-5}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
STATE_DIR="${STATE_DIR:-/var/lib/waha-watchdog}"
INBOUND_GAP_MONITOR="${INBOUND_GAP_MONITOR:-false}"
INBOUND_GAP_THRESHOLD="${INBOUND_GAP_THRESHOLD:-1800}"

WAHA_API_URL="${WAHA_API_URL%/}"

# --------------------------------------------------------------------------
# Pre-flight
# --------------------------------------------------------------------------
for bin in curl jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "FATAL: dependencia ausente: $bin" >&2
    exit 1
  fi
done

mkdir -p "$STATE_DIR" 2>/dev/null || {
  echo "FATAL: nao consegui criar STATE_DIR=$STATE_DIR" >&2
  exit 1
}

NOW="$(date +%s)"

log() {
  # log LEVEL MESSAGE...
  local level="$1"; shift
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*"
}

# --------------------------------------------------------------------------
# Alerting
# --------------------------------------------------------------------------
alert() {
  # alert TITLE MESSAGE
  local title="$1"; local message="$2"
  log "ALERT" "$title — $message"
  [ -z "$ALERT_WEBHOOK" ] && return 0

  local payload
  payload="$(jq -n --arg t "$title" --arg m "$message" --arg h "$(hostname)" \
    '{text: ("[waha-watchdog @ " + $h + "] " + $t + ": " + $m), title: $t, message: $m, host: $h}')"

  curl -fsS -m "$CURL_TIMEOUT" -X POST \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "$ALERT_WEBHOOK" >/dev/null 2>&1 \
    || log "WARN" "falha ao enviar alerta para ALERT_WEBHOOK"
}

# --------------------------------------------------------------------------
# HTTP helpers
# --------------------------------------------------------------------------
waha_get() {
  # waha_get PATH  -> body em stdout, exit code do curl
  local path="$1"
  if [ -n "$WAHA_API_KEY" ]; then
    curl -fsS -m "$CURL_TIMEOUT" -H "X-Api-Key: $WAHA_API_KEY" "${WAHA_API_URL}${path}"
  else
    curl -fsS -m "$CURL_TIMEOUT" "${WAHA_API_URL}${path}"
  fi
}

waha_post() {
  # waha_post PATH  -> POST com body vazio (restart/start nao precisam de body)
  local path="$1"
  if [ -n "$WAHA_API_KEY" ]; then
    curl -fsS -m "$CURL_TIMEOUT" -X POST -H "X-Api-Key: $WAHA_API_KEY" "${WAHA_API_URL}${path}"
  else
    curl -fsS -m "$CURL_TIMEOUT" -X POST "${WAHA_API_URL}${path}"
  fi
}

# --------------------------------------------------------------------------
# Liveness: GET /ping (processo vivo?)
# --------------------------------------------------------------------------
ping_alive() {
  waha_get "/ping" >/dev/null 2>&1
}

wait_for_api() {
  # Tenta /ping ate PING_RETRIES com backoff exponencial simples.
  # Retorna 0 se a API voltou, 1 se permaneceu morta.
  local attempt=1 delay="$PING_RETRY_DELAY"
  while [ "$attempt" -le "$PING_RETRIES" ]; do
    if ping_alive; then
      log "INFO" "/ping OK na tentativa $attempt"
      return 0
    fi
    log "WARN" "/ping falhou (tentativa $attempt/$PING_RETRIES); aguardando ${delay}s"
    sleep "$delay"
    delay=$(( delay * 2 ))
    attempt=$(( attempt + 1 ))
  done
  return 1
}

# --------------------------------------------------------------------------
# Estado por sessao (cooldown + rate-limit). Arquivos simples em STATE_DIR.
#   <session>.last       -> epoch do ultimo restart
#   <session>.window     -> "windowStart count" do rate-limit
# --------------------------------------------------------------------------
state_file() { printf '%s/%s.%s' "$STATE_DIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')" "$2"; }

in_cooldown() {
  # in_cooldown SESSION -> 0 (em cooldown) / 1 (livre)
  local f; f="$(state_file "$1" last)"
  [ -f "$f" ] || return 1
  local last; last="$(cat "$f" 2>/dev/null || echo 0)"
  [ $(( NOW - last )) -lt "$COOLDOWN_SECONDS" ]
}

rate_limited() {
  # rate_limited SESSION -> 0 (estourou janela) / 1 (ainda pode)
  local f; f="$(state_file "$1" window)"
  local ws=0 count=0
  if [ -f "$f" ]; then
    read -r ws count < "$f" 2>/dev/null || { ws=0; count=0; }
  fi
  if [ $(( NOW - ws )) -ge "$RESTART_WINDOW_SECONDS" ]; then
    # janela expirou: reset implicito, ainda pode reiniciar
    return 1
  fi
  [ "${count:-0}" -ge "$MAX_RESTARTS_PER_WINDOW" ]
}

record_restart() {
  # record_restart SESSION -> grava cooldown + incrementa janela
  local session="$1"
  printf '%s\n' "$NOW" > "$(state_file "$session" last)"

  local f; f="$(state_file "$session" window)"
  local ws=0 count=0
  if [ -f "$f" ]; then
    read -r ws count < "$f" 2>/dev/null || { ws=0; count=0; }
  fi
  if [ $(( NOW - ws )) -ge "$RESTART_WINDOW_SECONDS" ]; then
    ws="$NOW"; count=0
  fi
  count=$(( count + 1 ))
  printf '%s %s\n' "$ws" "$count" > "$f"
}

# --------------------------------------------------------------------------
# Acao: restart de SESSAO (nunca logout, nunca pede QR)
# --------------------------------------------------------------------------
restart_session() {
  local session="$1" reason="$2"

  if [ "$ALERT_ONLY" = "true" ]; then
    alert "ALERT_ONLY: sessao precisaria de restart" "session=$session reason=$reason (nenhuma acao tomada)"
    return 0
  fi

  if in_cooldown "$session"; then
    log "INFO" "skip restart de '$session' (cooldown ${COOLDOWN_SECONDS}s ativo)"
    return 0
  fi

  if rate_limited "$session"; then
    alert "Rate-limit de restart atingido" \
      "session=$session ja atingiu MAX_RESTARTS_PER_WINDOW=${MAX_RESTARTS_PER_WINDOW} na janela de ${RESTART_WINDOW_SECONDS}s — intervencao manual recomendada"
    return 0
  fi

  log "INFO" "RESTART session='$session' reason='$reason'"
  # Count the ATTEMPT up-front (cooldown + rate-limit window) BEFORE the POST, so a
  # persistently failing /restart (FAILED session, 5xx) can't storm: retry + alert
  # every 60s cycle. The attempt is recorded whether the POST succeeds or fails.
  record_restart "$session"
  if waha_post "/api/sessions/${session}/restart" >/dev/null 2>&1; then
    alert "Sessao reiniciada" "session=$session reason=$reason (restart aplicado; NAO pede QR)"
  else
    alert "Falha ao reiniciar sessao" "session=$session reason=$reason — POST /api/sessions/${session}/restart falhou"
  fi
}

# --------------------------------------------------------------------------
# Resolve a lista de sessoes a monitorar
# --------------------------------------------------------------------------
resolve_sessions() {
  # imprime nomes de sessao (uma por linha)
  if [ -n "$SESSIONS" ]; then
    printf '%s\n' "$SESSIONS" | tr ', ' '\n\n' | sed '/^$/d'
    return 0
  fi
  local body
  if ! body="$(waha_get '/api/sessions?all=true')"; then
    return 1
  fi
  printf '%s' "$body" | jq -r '.[].name'
}

# --------------------------------------------------------------------------
# Inbound-gap monitor (SO-ALERTA, opcional). Tuning de deteccao de freeze.
#   Compara o timestamp do ultimo inbound entre execucoes. Se nao avancar
#   por mais de INBOUND_GAP_THRESHOLD segundos, alerta (sem reiniciar).
# --------------------------------------------------------------------------
inbound_gap_check() {
  local session="$1"
  local body last_ts
  if ! body="$(waha_get "/api/${session}/chats/overview")"; then
    log "WARN" "inbound-gap: falha ao buscar overview de '$session'"
    return 0
  fi

  # Maior timestamp de mensagem inbound (fromMe=false). WAHA retorna ms.
  last_ts="$(printf '%s' "$body" | jq -r '
    [ .[]?.lastMessage // empty
      | select((.fromMe // false) == false)
      | (.timestamp // 0) ] | max // 0' 2>/dev/null || echo 0)"
  # normaliza ms -> s se vier em milissegundos
  if [ "${last_ts:-0}" -gt 9999999999 ] 2>/dev/null; then
    last_ts=$(( last_ts / 1000 ))
  fi

  local f; f="$(state_file "$session" inbound)"
  local prev_ts=0
  [ -f "$f" ] && prev_ts="$(cat "$f" 2>/dev/null || echo 0)"
  printf '%s\n' "$last_ts" > "$f"

  # Sem inbound recente E sem avanco desde a ultima checagem -> possivel freeze
  local age=$(( NOW - last_ts ))
  if [ "$last_ts" -gt 0 ] && [ "$age" -ge "$INBOUND_GAP_THRESHOLD" ] && [ "$last_ts" = "$prev_ts" ]; then
    alert "Possivel freeze de inbound (SO-ALERTA)" \
      "session=$session ultimo inbound ha ${age}s (>= ${INBOUND_GAP_THRESHOLD}s) e sem avanco entre execucoes"
  fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
  log "INFO" "watchdog start — url=$WAHA_API_URL alert_only=$ALERT_ONLY healthy='$HEALTHY_STATUSES'"

  # 1) Liveness do processo WAHA
  if ! ping_alive; then
    log "ERROR" "/ping falhou — possivel crash-loop; aguardando API voltar"
    alert "WAHA /ping falhou" "processo nao respondeu; iniciando espera por recuperacao"
    if ! wait_for_api; then
      alert "WAHA continua morto" "/ping nao voltou apos ${PING_RETRIES} tentativas — intervencao manual pode ser necessaria"
      log "ERROR" "API nao voltou; encerrando este ciclo"
      return 0
    fi
    log "INFO" "API voltou; seguira para checagem de sessoes (restart se necessario)"
  fi

  # 2) Status por sessao
  local sessions_json
  if ! sessions_json="$(waha_get '/api/sessions?all=true')"; then
    alert "Falha ao listar sessoes" "GET /api/sessions?all=true falhou mesmo com /ping OK"
    log "ERROR" "nao consegui listar sessoes"
    return 0
  fi

  local want
  want="$(resolve_sessions || true)"
  if [ -z "$want" ]; then
    log "WARN" "nenhuma sessao para monitorar (SESSIONS vazio e descoberta vazia)"
    return 0
  fi

  local session status
  while IFS= read -r session; do
    [ -z "$session" ] && continue
    status="$(printf '%s' "$sessions_json" \
      | jq -r --arg n "$session" '.[] | select(.name == $n) | .status' 2>/dev/null | head -1)"

    if [ -z "$status" ] || [ "$status" = "null" ]; then
      log "WARN" "sessao '$session' nao encontrada em /api/sessions — tentando recuperar"
      restart_session "$session" "ausente-na-listagem"
      continue
    fi

    # status saudavel?
    if printf '%s' "$HEALTHY_STATUSES" | tr ', ' '\n\n' | grep -qxF "$status"; then
      log "INFO" "sessao '$session' OK (status=$status)"
      [ "$INBOUND_GAP_MONITOR" = "true" ] && inbound_gap_check "$session"
      continue
    fi

    log "WARN" "sessao '$session' NAO saudavel (status=$status)"
    restart_session "$session" "status=$status"
  done <<< "$want"

  log "INFO" "watchdog ciclo concluido"
}

main "$@"
