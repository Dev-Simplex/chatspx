#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  ⚠️  CD SOLAR · PRODUÇÃO · 13.218.193.75 (cdsolar.chatspx.app, conta 1)  ⚠️
#  CLIENTE REAL. Qualquer escrita (banco, env, arquivo, restart, pull) só com
#  OK EXPLÍCITO do Paulo, pedido a cada vez. Antes de restart: sempre
#  `rails db:migrate:status` (pendente + restart = 500 em cadeia).
# ═══════════════════════════════════════════════════════════════════════
# Uso:
#   scripts/ops/cdsolar.sh ro < script.rb      -> rails runner SÓ LEITURA (transação read only), script pelo stdin
#   scripts/ops/cdsolar.sh run "<cmd>"         -> comando como chatwoot, com RAILS_ENV=production
#   scripts/ops/cdsolar.sh ssh "<cmd cru>"     -> comando como ubuntu (sudo NOPASSWD)
#   scripts/ops/cdsolar.sh put <local> <rem>   -> scp
set -euo pipefail
printf '\033[1;31m▛▀ ⚠️  CD SOLAR · PRODUÇÃO · 13.218.193.75 (conta 1) — CLIENTE REAL ▀▜\033[0m\n' >&2
KEY="${SPX_PEM:-/c/Users/paulo/Downloads/handoff-tozi/simplex.linux.pem}"
H=ubuntu@13.218.193.75
APP=/home/chatwoot/chatwoot
chmod 600 "$KEY" 2>/dev/null || true
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$H")
case "${1:-}" in
  ro)  "${SSH[@]}" "sudo -u chatwoot bash -lc 'cd $APP && RAILS_ENV=production bundle exec rails runner \"ActiveRecord::Base.connection.execute(%q(SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY)); eval(STDIN.read)\"'" ;;
  run) "${SSH[@]}" "sudo -u chatwoot bash -lc 'cd $APP && RAILS_ENV=production $2'" < /dev/null ;;
  ssh) "${SSH[@]}" "$2" < /dev/null ;;
  put) scp -i "$KEY" -o StrictHostKeyChecking=no "$2" "$H:$3" ;;
  *) echo "uso: ro|run|ssh|put"; exit 1 ;;
esac
