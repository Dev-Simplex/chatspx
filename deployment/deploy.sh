#!/usr/bin/env bash
# ==========================================================================
# ChatSPX - Script de deploy para todas as VMs
# Uso: ./deployment/deploy.sh [branch]
# Default: producao
# Rodar de: CHATSPX-PRODUCAO (192.168.8.229)
# ==========================================================================

set -euo pipefail

NO_RESTART=false
BRANCH="producao"

# Parse argumentos
for arg in "$@"; do
  case "$arg" in
    --no-restart) NO_RESTART=true ;;
    --*) echo "Opcao desconhecida: $arg"; exit 1 ;;
    *) BRANCH="$arg" ;;
  esac
done
PEM="/home/chatwoot/chatwoot/simplex.linux.pem"
LOCAL_PASS='Jzs72144#$GSpx'
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=30"
CWCTL_URL="https://raw.githubusercontent.com/Dev-Simplex/chatspx/${BRANCH}/deployment/setup_spx_24.04.sh"

# Lista de VMs: nome|ip|tipo(aws|local)|usuario
VMS=(
  "PRODUCAO|local|local|chatwoot"
  "CATATAU|3.85.130.14|aws|ubuntu"
  "SENTINELA|54.152.144.236|aws|ubuntu"
  # "TOZI|54.91.152.38|aws|ubuntu"  # Descomentar quando instalar o ChatSPX
  "ALTERNATIVO|192.168.8.169|local|simplexia"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] AVISO:${NC} $1"; }
fail() { echo -e "${RED}[$(date '+%H:%M:%S')] ERRO:${NC} $1"; }

# Executa comando remoto via SSH
remote_exec() {
  local ip="$1" tipo="$2" user="$3" cmd="$4"

  if [ "$tipo" == "aws" ]; then
    ssh $SSH_OPTS -i "$PEM" "${user}@${ip}" "$cmd" 2>&1
  else
    sshpass -p "$LOCAL_PASS" ssh $SSH_OPTS "${user}@${ip}" "$cmd" 2>&1
  fi
}

# Executa comando remoto com sudo
remote_sudo() {
  local ip="$1" tipo="$2" user="$3" cmd="$4"

  if [ "$tipo" == "aws" ]; then
    ssh $SSH_OPTS -i "$PEM" "${user}@${ip}" "sudo bash -c '${cmd}'" 2>&1
  else
    sshpass -p "$LOCAL_PASS" ssh $SSH_OPTS "${user}@${ip}" "echo '${LOCAL_PASS}' | sudo -S bash -c '${cmd}'" 2>&1
  fi
}

# Atualiza uma VM
update_vm() {
  local name="$1" ip="$2" tipo="$3" user="$4"
  local start_time=$(date +%s)

  log "[$name] Iniciando atualizacao..."

  # Caso especial: VM local (PRODUCAO)
  if [ "$tipo" == "local" ] && [ "$ip" == "local" ]; then
    log "[$name] Atualizando localmente..."
    cd /home/chatwoot/chatwoot
    local before_commit=$(git rev-parse HEAD)
    git fetch origin
    git checkout "$BRANCH"
    git pull origin "$BRANCH"
    local after_commit=$(git rev-parse HEAD)

    if [ "$before_commit" == "$after_commit" ]; then
      log "[$name] Ja esta no ultimo commit (${before_commit:0:9}). Nada a atualizar."
      return 0
    fi
    log "[$name] ${before_commit:0:9} -> ${after_commit:0:9}"

    source /usr/local/rvm/scripts/rvm
    rvm use 3.4.4

    bundle install --jobs $(nproc) --retry 3
    pnpm install --frozen-lockfile 2>/dev/null || pnpm install

    RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=4096' bundle exec rake assets:precompile
    RAILS_ENV=production bundle exec rails db:migrate

    if [ "$NO_RESTART" == "false" ]; then
      sudo systemctl restart chatwoot.target
      log "[$name] Servico reiniciado"
    else
      warn "[$name] --no-restart: servico NAO reiniciado"
    fi

    local elapsed=$(( $(date +%s) - start_time ))
    log "[$name] Atualizado com sucesso em ${elapsed}s"
    return 0
  fi

  # VMs remotas
  # 1. Verificar conectividade
  if ! remote_exec "$ip" "$tipo" "$user" "echo OK" > /dev/null 2>&1; then
    fail "[$name] Sem acesso SSH"
    return 1
  fi

  # 2. Verificar se ja esta atualizado
  local remote_commit
  remote_commit=$(remote_exec "$ip" "$tipo" "$user" "sudo -i -u chatwoot bash -c 'cd ~/chatwoot && git fetch origin -q 2>/dev/null && git rev-parse HEAD 2>/dev/null'" 2>/dev/null || echo "desconhecido")
  local latest_commit
  latest_commit=$(remote_exec "$ip" "$tipo" "$user" "sudo -i -u chatwoot bash -c 'cd ~/chatwoot && git rev-parse origin/${BRANCH} 2>/dev/null'" 2>/dev/null || echo "desconhecido")

  if [ "$remote_commit" == "$latest_commit" ] && [ "$remote_commit" != "desconhecido" ]; then
    log "[$name] Ja esta no ultimo commit (${remote_commit:0:9}). Nada a atualizar."
    return 0
  fi
  log "[$name] ${remote_commit:0:9} -> ${latest_commit:0:9}"

  # 3. Atualizar cwctl se necessario
  log "[$name] Atualizando cwctl..."
  remote_sudo "$ip" "$tipo" "$user" \
    "wget -q ${CWCTL_URL} -O /usr/local/bin/cwctl && chmod +x /usr/local/bin/cwctl" || true

  # 4. Rodar upgrade
  if [ "$NO_RESTART" == "false" ]; then
    log "[$name] Executando cwctl -U ${BRANCH} (com restart)..."
    local output
    output=$(remote_sudo "$ip" "$tipo" "$user" "cwctl -U ${BRANCH} <<< 'y'" 2>&1) || {
      fail "[$name] Falhou!"
      echo "$output" | tail -20
      return 1
    }
  else
    log "[$name] Atualizando sem restart..."
    local update_cmd="
      cd /home/chatwoot/chatwoot &&
      sudo -i -u chatwoot bash -l <<'UPDSCRIPT'
        set -e
        cd ~/chatwoot
        git fetch --all && git checkout ${BRANCH} && git pull origin ${BRANCH}
        bundle install --jobs \$(nproc) --retry 3
        pnpm install --frozen-lockfile 2>/dev/null || pnpm install
        RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=4096' bundle exec rake assets:precompile
        RAILS_ENV=production bundle exec rails db:migrate
UPDSCRIPT
    "
    local output
    output=$(remote_sudo "$ip" "$tipo" "$user" "$update_cmd" 2>&1) || {
      fail "[$name] Falhou!"
      echo "$output" | tail -20
      return 1
    }
    warn "[$name] --no-restart: servico NAO reiniciado"
  fi

  local elapsed=$(( $(date +%s) - start_time ))
  log "[$name] Atualizado com sucesso em ${elapsed}s"
  return 0
}

# Main
echo ""
echo "=========================================="
echo "  ChatSPX Deploy (branch: $BRANCH)"
echo "=========================================="
echo ""

total=${#VMS[@]}
success=0
failed=0
failed_names=""

for vm in "${VMS[@]}"; do
  IFS='|' read -r name ip tipo user <<< "$vm"

  if update_vm "$name" "$ip" "$tipo" "$user"; then
    success=$((success + 1))
  else
    failed=$((failed + 1))
    failed_names="${failed_names} ${name}"
  fi

  echo ""
done

echo "=========================================="
echo "  Resultado: ${success}/${total} OK"
if [ "$failed" -gt 0 ]; then
  fail "Falharam:${failed_names}"
fi
echo "=========================================="
