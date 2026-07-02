#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  ⚠️  TOZI · PRODUÇÃO · 3.82.215.109 (tozi.chatspx.app, conta 6)  ⚠️
#  CLIENTE REAL. Deploy/restart só com OK EXPLÍCITO do Paulo.
#  Antes de restart: sempre `rails db:migrate:status` (pendente + restart = 500 em cadeia).
# ═══════════════════════════════════════════════════════════════════════
# Uso:
#   scripts/ops/tozi-prod.sh put <local> <rem>
#   scripts/ops/tozi-prod.sh run "<cmd apos RAILS_ENV=production>"
#   scripts/ops/tozi-prod.sh ssh "<cmd cru>"
set -euo pipefail
printf '\033[1;31m▛▀ ⚠️  TOZI · PRODUÇÃO · 3.82.215.109 (conta 6) — CLIENTE REAL ▀▜\033[0m\n' >&2
KEY="${TOZI_PEM:-/c/Users/paulo/Downloads/handoff-tozi/simplex.linux.pem}"
H=ubuntu@3.82.215.109
chmod 600 "$KEY" 2>/dev/null || true
case "${1:-}" in
  put) scp -i "$KEY" -o StrictHostKeyChecking=no "$2" "$H:$3" ;;
  run) ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$H" "sudo -u chatwoot bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production $2'" ;;
  ssh) ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$H" "$2" ;;
  *) echo "uso: put|run|ssh"; exit 1 ;;
esac
