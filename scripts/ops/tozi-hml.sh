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
# Igual ao A(), mas SEM fechar o stdin: é por ele que a senha do sudo viaja.
# A senha NUNCA entra na string do comando remoto — em 10/08 ela vazou duas vezes
# porque `echo '$PASS' | sudo -S ...` morava na mesma string que o comando do
# usuário: uma aspa desbalanceada no comando quebrava o parsing e o shell remoto
# devolvia a linha inteira no erro. Pelo stdin, erro de quoting continua sendo
# erro, mas deixa de ser vazamento — e a senha some do `ps` da VM.
Ain() { SSH_ASKPASS="$AK" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 "$@"; }
sudo_via_stdin() { # $1 = timeout, $2 = comando remoto ja montado
  printf '%s\n' "$PASS" | Ain ssh -o StrictHostKeyChecking=no -o ConnectTimeout="$1" "$H" "$2" 2>&1 | grep -v "^\[sudo\]"
}
# O comando do usuario viaja em base64, nunca interpolado no shell remoto. Antes,
# `bash -lc '$2'` quebrava com QUALQUER aspa simples no comando (e um `(` solto
# virava syntax error) — o que forcava reescrever o comando ate passar. Em base64
# o shell remoto nao ve o conteudo, so o decodifica: aspas, parenteses e acentos
# passam intactos.
b64() { printf '%s' "$1" | base64 -w0; }
case "${1:-}" in
  put) A scp -o StrictHostKeyChecking=no "$2" "$H:$3" ;;
  ssh) A ssh -o StrictHostKeyChecking=no -o ConnectTimeout=25 "$H" "$2" ;;
  chatwoot) sudo_via_stdin 40 "sudo -S -p '' -u chatwoot bash -lc \"\$(echo $(b64 "$2") | base64 -d)\"" ;;
  sudo) sudo_via_stdin 60 "sudo -S -p '' bash -lc \"\$(echo $(b64 "$2") | base64 -d)\"" ;;
  *) echo "uso: chatwoot|ssh|put|sudo"; exit 1 ;;
esac
