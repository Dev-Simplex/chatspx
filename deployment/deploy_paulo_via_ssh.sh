#!/usr/bin/env bash
# Deploy da VM PAULAO (192.168.8.100, ChatSPX dev/staging) via SSH (Windows Git Bash).
# Pipeline: pull -> db:migrate:status -> assets:precompile -> restart chatwoot.target -> smoke.
#
# Uso:
#   export SPX_SSH_PASS='<senha_paulo>'
#   bash deployment/deploy_paulo_via_ssh.sh
#
# Pré-requisitos:
#   - estar na rede interna ou VPN da empresa
#   - git da VM autenticado (deploy via HTTPS + token em ~chatwoot/.git-credentials)

set -euo pipefail

HOST="192.168.8.100"
USER_SSH="paulo"
APP_DIR="/home/chatwoot/chatwoot"
BRANCH="paulao"

if [[ -z "${SPX_SSH_PASS:-}" ]]; then
  echo "ERRO: defina SPX_SSH_PASS env var antes de rodar"
  exit 1
fi

# SSH_ASKPASS helper temporário
ASKPASS_FILE=$(mktemp /tmp/_askpass_XXXX.sh)
cat > "$ASKPASS_FILE" << EOF
#!/bin/sh
echo "$SPX_SSH_PASS"
EOF
chmod +x "$ASKPASS_FILE"

cleanup() {
  rm -f "$ASKPASS_FILE"
}
trap cleanup EXIT

run_remote() {
  local cmd="$1"
  SSH_ASKPASS="$ASKPASS_FILE" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
    ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
    "${USER_SSH}@${HOST}" "$cmd" < /dev/null
}

# Helper pra rodar comando como user chatwoot (com login shell pra PATH rbenv)
run_chatwoot() {
  local cmd="$1"
  run_remote "echo '${SPX_SSH_PASS}' | sudo -S -u chatwoot bash -lc '$cmd'"
}

echo "==> [1/5] Commit atual em produção:"
run_chatwoot "cd $APP_DIR && git log -1 --oneline"

echo ""
echo "==> [2/5] Descartar mudanças locais e fazer pull"
run_chatwoot "cd $APP_DIR && git checkout -- public/version.json 2>/dev/null || true"
run_chatwoot "cd $APP_DIR && git fetch origin $BRANCH"
run_chatwoot "cd $APP_DIR && git pull --ff-only origin $BRANCH"

echo ""
echo "==> [3/6] Verificar migrations (HARD RULE: db:migrate:status antes de restart)"
run_chatwoot "cd $APP_DIR && RAILS_ENV=production bundle exec rails db:migrate:status 2>&1 | tail -5"

echo ""
echo "==> [4/6] Recompilar assets (frontend Vue/JS — sem isto, mudanças de tela nao aparecem)"
run_chatwoot "cd $APP_DIR && RAILS_ENV=production bundle exec rails assets:precompile 2>&1 | tail -4"

echo ""
echo "==> [5/6] Restart chatwoot.target"
echo "${SPX_SSH_PASS}" | run_remote "echo '${SPX_SSH_PASS}' | sudo -S systemctl restart chatwoot.target"
sleep 8
run_remote "systemctl is-active chatwoot.target chatwoot-web.1.service chatwoot-worker.1.service"

echo ""
echo "==> [6/6] Smoke HTTP"
run_remote "curl -sS -o /dev/null -w 'HTTP %{http_code} em %{time_total}s\n' http://localhost:3000/"

echo ""
echo "==> Commit deployado:"
run_chatwoot "cd $APP_DIR && git log -1 --oneline"

echo ""
echo "OK — deploy completo."
