#!/usr/bin/env bash
# Script para testar a API do Copilot via curl
# Uso: ./script/copilot_curl_test.sh <BASE_URL> <ACCOUNT_ID> <ASSISTANT_ID> <CONVERSATION_ID> <ACCESS_TOKEN> <CLIENT> <UID>
#
# Exemplo (substitua os valores):
#   ./script/copilot_curl_test.sh https://chatspx.app 3 2 461 "seu-access-token" "seu-client" "seu-uid@email.com"
#
# Ou exporte as variáveis e execute:
#   export COPILOT_BASE_URL=https://chatspx.app
#   export COPILOT_ACCOUNT_ID=3
#   export COPILOT_ASSISTANT_ID=2
#   export COPILOT_CONVERSATION_ID=461
#   export COPILOT_ACCESS_TOKEN=seu-token
#   export COPILOT_CLIENT=seu-client
#   export COPILOT_UID=seu-uid@email.com
#   ./script/copilot_curl_test.sh

set -e

BASE_URL="${1:-$COPILOT_BASE_URL}"
ACCOUNT_ID="${2:-$COPILOT_ACCOUNT_ID}"
ASSISTANT_ID="${3:-$COPILOT_ASSISTANT_ID}"
CONVERSATION_ID="${4:-$COPILOT_CONVERSATION_ID}"
ACCESS_TOKEN="${5:-$COPILOT_ACCESS_TOKEN}"
CLIENT="${6:-$COPILOT_CLIENT}"
USER_UID="${7:-$COPILOT_UID}"

if [ -z "$BASE_URL" ] || [ -z "$ACCOUNT_ID" ] || [ -z "$ASSISTANT_ID" ] || [ -z "$ACCESS_TOKEN" ] || [ -z "$CLIENT" ] || [ -z "$USER_UID" ]; then
  echo "Uso: $0 <BASE_URL> <ACCOUNT_ID> <ASSISTANT_ID> [CONVERSATION_ID] <ACCESS_TOKEN> <CLIENT> <UID>"
  echo ""
  echo "Variáveis necessárias:"
  echo "  BASE_URL       - URL base (ex: https://chatspx.app)"
  echo "  ACCOUNT_ID     - ID da conta"
  echo "  ASSISTANT_ID   - ID do assistente Captain"
  echo "  CONVERSATION_ID - ID da conversa (opcional, use display_id)"
  echo "  ACCESS_TOKEN   - Token de autenticação"
  echo "  CLIENT         - Header client (Devise Token Auth)"
  echo "  USER_UID       - Header uid (email do usuário)"
  echo ""
  echo "Exemplo:"
  echo "  $0 https://chatspx.app 3 2 461 aCDfxb4vWqWY3Cn5oaunIw joxDQtN-FAiKrcMCQP5WnA user@example.com"
  exit 1
fi

API_URL="${BASE_URL}/api/v1/accounts/${ACCOUNT_ID}/captain"

if [ -n "$CONVERSATION_ID" ]; then
  PAYLOAD="{\"assistant_id\": ${ASSISTANT_ID}, \"conversation_id\": ${CONVERSATION_ID}, \"message\": \"Resuma os pontos-chave discutidos nesta conversa\"}"
else
  PAYLOAD="{\"assistant_id\": ${ASSISTANT_ID}, \"message\": \"Resuma os pontos-chave discutidos nesta conversa\"}"
fi

echo "=== 1. POST copilot_threads (criar nova thread) ==="
echo "URL: ${API_URL}/copilot_threads"
echo "Payload: $PAYLOAD"
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/copilot_threads" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "access-token: ${ACCESS_TOKEN}" \
  -H "client: ${CLIENT}" \
  -H "uid: ${USER_UID}" \
  -d "$PAYLOAD")

HTTP_BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)

echo "HTTP Status: $HTTP_CODE"
echo "Response: $HTTP_BODY" | head -c 500
[ ${#HTTP_BODY} -gt 500 ] && echo "..."
echo ""

if [ "$HTTP_CODE" -eq 401 ]; then
  echo "❌ 401 Unauthorized - Token expirado ou inválido. Faça login novamente."
  exit 1
fi

if [ "$HTTP_CODE" -eq 404 ]; then
  echo "❌ 404 Not Found - Assistente ou recurso não encontrado."
  exit 1
fi

if [ "$HTTP_CODE" -eq 422 ]; then
  echo "❌ 422 Unprocessable - Verifique:"
  echo "   - Chave API OpenAI configurada? (code: captain_api_key_missing)"
  echo "   - Mensagem não vazia?"
  exit 1
fi

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  THREAD_ID=$(echo "$HTTP_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
  if [ -n "$THREAD_ID" ]; then
    echo "✅ Thread criada com ID: $THREAD_ID"
    echo ""
    echo "=== 2. GET copilot_messages (buscar mensagens da thread) ==="
    echo "URL: ${API_URL}/copilot_threads/${THREAD_ID}/copilot_messages"
    echo ""
    sleep 2
    curl -s -X GET "${API_URL}/copilot_threads/${THREAD_ID}/copilot_messages" \
      -H "Accept: application/json" \
      -H "access-token: ${ACCESS_TOKEN}" \
      -H "client: ${CLIENT}" \
      -H "uid: ${USER_UID}" | head -c 1000
    echo ""
  fi
else
  echo "❌ Erro inesperado: $HTTP_CODE"
  exit 1
fi
