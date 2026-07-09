#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  FÁBRICA / ATACADÃO DOS ÓCULOS · 3.87.182.184 (fabrica.chatspx.app)
#  Box único de build/teste. Account 1 = Fábrica, Account 2 = Atacadão.
#  Restart do app: `fabrica.sh ssh "sudo systemctl restart chatwoot.target"` (NOPASSWD p/ chatwoot).
# ═══════════════════════════════════════════════════════════════════════
# Senha via SSH_ASKPASS (vault clientes/fabrica-atacadao-oculos.md — nunca ecoada).
# Uso:
#   scripts/ops/fabrica.sh run "<cmd apos RAILS_ENV=production>"  -> rails/rake
#   scripts/ops/fabrica.sh ssh "<cmd cru>"
#   scripts/ops/fabrica.sh put <local> <rem>
set -euo pipefail
printf '\033[1;36m▛▀ FÁBRICA/ATACADÃO · 3.87.182.184 (fabrica.chatspx.app) ▀▜\033[0m\n' >&2
VAULT="${VAULT_FAB:-/c/Users/paulo/Workspaces/Obsidian/clientes/fabrica-atacadao-oculos.md}"
PASS=$(grep -oP 'senha:\s*`\K[^`]+' "$VAULT" | head -1)
[ -z "$PASS" ] && { echo "ERRO: senha nao extraida do vault"; exit 1; }
PASSFILE=$(mktemp); printf '%s' "$PASS" > "$PASSFILE"
AK=$(mktemp); printf '#!/bin/sh\ncat %q\n' "$PASSFILE" > "$AK"; chmod +x "$AK"
trap 'rm -f "$AK" "$PASSFILE"' EXIT
H="chatwoot@3.87.182.184"
A() { SSH_ASKPASS="$AK" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 "$@" < /dev/null; }
case "${1:-}" in
  put) A scp -o StrictHostKeyChecking=no "$2" "$H:$3" ;;
  ssh) A ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$H" "$2" ;;
  run) A ssh -o StrictHostKeyChecking=no -o ConnectTimeout=40 "$H" "bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production $2'" ;;
  *) echo "uso: run|ssh|put"; exit 1 ;;
esac
