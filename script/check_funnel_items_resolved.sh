#!/usr/bin/env bash
# Verificação manual da API de funnel_items para a coluna Resolvidos (stage_id=3).
# Uso: envie seu token de acesso (ex: do cookie ou do header da aplicação).
#
# Exemplo (substitua BASE_URL e TOKEN):
#   BASE_URL="https://chat.simplexsolucoes.com.br" TOKEN="seu_token" ./script/check_funnel_items_resolved.sh
# Ou para localhost:
#   BASE_URL="http://localhost:3000" TOKEN="seu_token" ./script/check_funnel_items_resolved.sh
#
# Parâmetros da URL (conforme usado pelo frontend): stage_id=3, page=1, per_page=50
# Inspecione o JSON de resposta para: funnel_items presentes e conversations.last_activity_at.

set -e
BASE_URL="${BASE_URL:-http://localhost:3000}"
ACCOUNT_ID="${ACCOUNT_ID:-3}"
FUNNEL_ID="${FUNNEL_ID:-1}"
STAGE_ID="${STAGE_ID:-3}"
TOKEN="${TOKEN:?Defina TOKEN (ex: export TOKEN=seu_api_access_token)}"

URL="${BASE_URL}/api/v1/accounts/${ACCOUNT_ID}/funnels/${FUNNEL_ID}/funnel_items?stage_id=${STAGE_ID}&page=1&per_page=50"
echo "GET $URL"
curl -s -H "api_access_token: $TOKEN" "$URL" | jq . 2>/dev/null || curl -s -H "api_access_token: $TOKEN" "$URL"
