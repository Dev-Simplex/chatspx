#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  TOZI · HOMOLOGAÇÃO · 192.168.8.232 (chatspx.app, conta 3)
# ═══════════════════════════════════════════════════════════════════════
# Acesso via SSH_ASKPASS (senha do Cortex no vault — nunca ecoada).
# Uso:
#   scripts/ops/tozi-hml.sh chatwoot "<cmd>"   -> como user chatwoot (app)
#   scripts/ops/tozi-hml.sh ssh "<cmd>"        -> como simplexia
#   scripts/ops/tozi-hml.sh put <local> <rem>  -> scp pra .232 (/tmp/...)
#   scripts/ops/tozi-hml.sh sudo "<cmd>"       -> root (senha do vault)
set -euo pipefail
printf '\033[1;33m▛▀ TOZI · HOMOLOGAÇÃO · 192.168.8.232 (conta 3) ▀▜\033[0m\n' >&2
VAULT="${VAULT:-/c/Users/paulo/Workspaces/Obsidian/credenciais/infraestrutura.md}"
PASS=$(awk '/### Cortex \(LAN\)/{f=1} f&&/^### /&&$0!~/Cortex/{f=0} f&&/[Ss]enha|[Pp]assword/{ if(match($0,/`[^`]+`/)){print substr($0,RSTART+1,RLENGTH-2); exit} }' "$VAULT")
[ -z "$PASS" ] && { echo "ERRO: senha nao extraida do vault"; exit 1; }
PASSFILE=$(mktemp); printf '%s' "$PASS" > "$PASSFILE"
AK=$(mktemp); printf '#!/bin/sh\ncat %q\n' "$PASSFILE" > "$AK"; chmod +x "$AK"
trap 'rm -f "$AK" "$PASSFILE"' EXIT
H="simplexia@192.168.8.232"
A() { SSH_ASKPASS="$AK" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 "$@" < /dev/null; }
case "${1:-}" in
  put) A scp -o StrictHostKeyChecking=no "$2" "$H:$3" ;;
  ssh) A ssh -o StrictHostKeyChecking=no -o ConnectTimeout=25 "$H" "$2" ;;
  chatwoot) A ssh -o StrictHostKeyChecking=no -o ConnectTimeout=40 "$H" "echo '$PASS' | sudo -S -u chatwoot bash -lc '$2'" 2>&1 | grep -v "^\[sudo\]" ;;
  sudo) A ssh -o StrictHostKeyChecking=no -o ConnectTimeout=60 "$H" "echo '$PASS' | sudo -S bash -lc '$2'" 2>&1 | grep -v "^\[sudo\]" ;;
  *) echo "uso: chatwoot|ssh|put|sudo"; exit 1 ;;
esac
