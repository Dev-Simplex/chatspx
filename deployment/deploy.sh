#!/usr/bin/env bash
# ==========================================================================
# ChatSPX - Script de deploy para todas as VMs
# Uso: ./deployment/deploy.sh [branch]
# Default: producao
# Rodar de: CHATSPX-PRODUCAO (192.168.8.229)
# ==========================================================================

set -euo pipefail

NO_RESTART=false
INCLUIR_TOZI=false
BRANCH="producao"

# Parse argumentos
for arg in "$@"; do
  case "$arg" in
    --no-restart) NO_RESTART=true ;;
    --incluir-tozi) INCLUIR_TOZI=true ;;
    --*) echo "Opcao desconhecida: $arg"; exit 1 ;;
    *) BRANCH="$arg" ;;
  esac
done
PEM="/home/chatwoot/chatwoot/simplex.linux.pem"
# Senha das VMs `local` fora do arquivo versionado: o que entra aqui fica no
# historico do Git para sempre. Hoje nenhuma VM usa este caminho (a PRODUCAO e
# tratada no ramo `local` sem SSH, e a ALTERNATIVO saiu do fan-out), entao o
# valor vazio nao quebra nada — mas se alguem cadastrar uma VM `local` sem
# exportar CHATSPX_LOCAL_PASS, o erro precisa ser obvio.
LOCAL_PASS="${CHATSPX_LOCAL_PASS:-}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=30"
CWCTL_URL="https://raw.githubusercontent.com/Dev-Simplex/chatspx/${BRANCH}/deployment/setup_spx_24.04.sh"
# As duas horas que dizem se a VM esta servindo o que tem no disco (ver web_subiu_depois_do_head).
# Reflog da BRANCH, e nao do HEAD: o proprio deploy faz `git checkout` na mesma branch, e isso
# tambem escreve no reflog do HEAD sem mudar codigo nenhum.
CMD_BRANCH_ANDOU="git -C /home/chatwoot/chatwoot reflog -1 --date=unix --format=%gd ${BRANCH}"
CMD_WEB_SUBIU="systemctl show chatwoot-web.1 -p ActiveEnterTimestamp --value --timestamp=unix"

# Lista de VMs: nome|ip|tipo(aws|local)|usuario
VMS=(
  "PRODUCAO|local|local|chatwoot"
  "TOZI|3.94.9.51|aws|ubuntu"
  "CATATAU|3.85.130.14|aws|ubuntu"
  "SENTINELA|54.166.220.138|aws|ubuntu"
  "FABRICA|3.87.182.184|aws|ubuntu"
  "AGN|13.221.167.143|aws|ubuntu"
  "CDSOLAR|13.218.193.75|aws|ubuntu"
  # CDSOLAR entrou a mao no deploy.sh da PRODUCAO em 10/09/2026, sem commit; esta linha so
  # espelha o arquivo que roda la. Sem ela, o primeiro deploy deste arquivo tiraria a VM do fan-out.
  # TOZI e CLIENTE REAL (conta 6): deploy e restart so com OK explicito.
  # O IP dela NAO e Elastic e ja mudou num stop/start da AWS (era 3.82.215.109).
  # Se der "sem resposta", confira o console EC2 antes de concluir que caiu.
  # ALTERNATIVO (192.168.8.169) foi DESATIVADO — a maquina nao existe mais.
  # Removido do fan-out em 08/09/2026; se voltar, cadastre com o endereco novo.
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] AVISO:${NC} $1"; }
fail() { echo -e "${RED}[$(date '+%H:%M:%S')] ERRO:${NC} $1"; }

# "Esta servindo o que tem no disco?" = o chatwoot-web.1 subiu DEPOIS da ultima vez que a branch
# andou. $1 = saida de CMD_BRANCH_ANDOU (`producao@{<epoch>}`), $2 = de CMD_WEB_SUBIU (`@<epoch>`).
#
# O `public/version.json` NAO responde isso, embora pareca: o app_version.rb o reescreve em TODO
# boot do Rails, nao so no do web. `rake`, `rails runner` e o cron de 3 em 3 minutos
# (`rails messages:reconcile_team_id`, na CATATAU, na AGN e na PRODUCAO) carimbam o HEAD novo com o
# web velho no ar — medido na CATATAU em 10/09/2026: web de 15:51, carimbo das 17:57. Confiar nele
# pularia a VM justamente no caso de 08/09 que este teste existe para pegar.
#
# As duas horas saem da mesma maquina, entao relogio torto nao interfere. Se alguma nao puder ser
# lida, a resposta e "nao": na duvida o script reconstroi, nunca pula.
RE_BRANCH_ANDOU='@\{([0-9]+)\}'
RE_WEB_SUBIU='@([0-9]+)'
web_subiu_depois_do_head() {
  local branch_andou="" web_subiu=""
  [[ "$1" =~ $RE_BRANCH_ANDOU ]] && branch_andou="${BASH_REMATCH[1]}"
  [[ "$2" =~ $RE_WEB_SUBIU ]] && web_subiu="${BASH_REMATCH[1]}"
  [ -n "$branch_andou" ] && [ -n "$web_subiu" ] && [ "$web_subiu" -ge "$branch_andou" ]
}

web_servindo_aqui() {
  web_subiu_depois_do_head "$($CMD_BRANCH_ANDOU 2>&1 || true)" "$($CMD_WEB_SUBIU 2>&1 || true)"
}

web_servindo_na_vm() {
  local ip="$1" tipo="$2" user="$3" branch_andou web_subiu
  branch_andou=$(remote_exec "$ip" "$tipo" "$user" "sudo -n -u chatwoot $CMD_BRANCH_ANDOU" 2>/dev/null || echo "")
  web_subiu=$(remote_exec "$ip" "$tipo" "$user" "$CMD_WEB_SUBIU" 2>/dev/null || echo "")
  web_subiu_depois_do_head "$branch_andou" "$web_subiu"
}

exige_local_pass() {
  if [ -z "$LOCAL_PASS" ]; then
    fail "VM do tipo 'local' exige a variavel CHATSPX_LOCAL_PASS exportada."
    return 1
  fi
}

# Executa comando remoto via SSH
remote_exec() {
  local ip="$1" tipo="$2" user="$3" cmd="$4"

  if [ "$tipo" == "aws" ]; then
    ssh $SSH_OPTS -i "$PEM" "${user}@${ip}" "$cmd" 2>&1
  else
    exige_local_pass || return 1
    sshpass -p "$LOCAL_PASS" ssh $SSH_OPTS "${user}@${ip}" "$cmd" 2>&1
  fi
}

# Executa comando remoto com sudo
remote_sudo() {
  local ip="$1" tipo="$2" user="$3" cmd="$4"

  if [ "$tipo" == "aws" ]; then
    ssh $SSH_OPTS -i "$PEM" "${user}@${ip}" "sudo bash -c '${cmd}'" 2>&1
  else
    exige_local_pass || return 1
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

    # Git igual NAO significa entregue: se alguem ja deu `git pull` na VM sem reiniciar, o
    # commit bate e o servico segue no codigo velho. Foi o que aconteceu em 08/09/2026 — o
    # script pulou, e a correcao ficou semanas fora do ar com o deploy relatando sucesso.
    if [ "$before_commit" == "$after_commit" ] && web_servindo_aqui; then
      log "[$name] Ja esta no ultimo commit (${before_commit:0:9}) e servindo ele. Nada a atualizar."
      return 0
    fi
    if [ "$before_commit" == "$after_commit" ]; then
      warn "[$name] git ja esta em ${before_commit:0:9}, mas o servico nao esta servindo esse commit. Reconstruindo."
    fi
    log "[$name] ${before_commit:0:9} -> ${after_commit:0:9}"

    source /usr/local/rvm/scripts/rvm
    rvm use 3.4.4

    bundle install --jobs $(nproc) --retry 3
    pnpm install --frozen-lockfile 2>/dev/null || pnpm install

    RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=12288' bundle exec rake assets:precompile
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

  # 2. Onde a VM esta, e se ela consegue buscar sozinha
  #
  # So a AGN alcanca o GitHub. TOZI, CATATAU, SENTINELA e FABRICA respondem
  # "could not read Username" no fetch, porque nao tem credencial de leitura.
  # Isso importa aqui por dois motivos:
  #
  #   1. o `fatal:` sai em STDERR, entao um `&& echo OK` acha que deu certo;
  #   2. sem fetch, `origin/BRANCH` e a referencia VELHA que sobrou do ultimo
  #      deploy — a VM se declara "no ultimo commit" comparando consigo mesma.
  #
  # Por isso o fetch e testado em separado do rev-parse: se ele falhar, a VM
  # nao entra na comparacao e o script diz para usar o bundle, em vez de
  # seguir para um `cwctl -U` que vai morrer no `git pull` la dentro.
  # Medido em 08/09/2026.
  local remote_commit
  remote_commit=$(remote_exec "$ip" "$tipo" "$user" "sudo -i -u chatwoot bash -c 'cd ~/chatwoot && git rev-parse HEAD 2>/dev/null'" 2>/dev/null || echo "desconhecido")

  if ! remote_exec "$ip" "$tipo" "$user" "sudo -i -u chatwoot bash -c 'cd ~/chatwoot && git fetch origin -q'" >/dev/null 2>&1; then
    fail "[$name] esta em ${remote_commit:0:9} mas NAO consegue buscar do GitHub"
    warn "[$name] esta VM so aceita pacote: use o /promover-pr (git bundle), nao este script"
    return 1
  fi

  local latest_commit
  latest_commit=$(remote_exec "$ip" "$tipo" "$user" "sudo -i -u chatwoot bash -c 'cd ~/chatwoot && git rev-parse origin/${BRANCH} 2>/dev/null'" 2>/dev/null || echo "desconhecido")

  if [ "$remote_commit" == "desconhecido" ] || [ "$latest_commit" == "desconhecido" ]; then
    fail "[$name] nao consegui ler o commit da VM (remoto=${remote_commit:0:9} alvo=${latest_commit:0:9})"
    return 1
  fi

  if [ "$remote_commit" == "$latest_commit" ] && web_servindo_na_vm "$ip" "$tipo" "$user"; then
    log "[$name] Ja esta no ultimo commit (${remote_commit:0:9}) e servindo ele. Nada a atualizar."
    return 0
  fi
  if [ "$remote_commit" == "$latest_commit" ]; then
    warn "[$name] git ja esta em ${remote_commit:0:9}, mas o servico nao esta servindo esse commit. Reconstruindo."
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
        RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=12288' bundle exec rake assets:precompile
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

  # Nao declare sucesso sem reler a VM. O `cwctl -U` ja voltou 0 tendo falhado o
  # `git pull` la dentro (08/09/2026: "Atualizado com sucesso em 12s" numa VM que
  # ficou 8 dias parada). Codigo de saida de wrapper nao e prova de entrega.
  local commit_final
  commit_final=$(remote_exec "$ip" "$tipo" "$user" "sudo -i -u chatwoot bash -c 'cd ~/chatwoot && git rev-parse HEAD 2>/dev/null'" 2>/dev/null || echo "desconhecido")
  if [ "$commit_final" != "$latest_commit" ]; then
    fail "[$name] terminou em ${commit_final:0:9}, mas o alvo era ${latest_commit:0:9}"
    return 1
  fi
  # Commit certo no disco nao prova restart: o exit 0 do `cwctl -U` tambem nao.
  if [ "$NO_RESTART" == "false" ] && ! web_servindo_na_vm "$ip" "$tipo" "$user"; then
    fail "[$name] esta em ${commit_final:0:9}, mas o chatwoot-web.1 nao reiniciou depois do codigo novo"
    return 1
  fi

  local elapsed=$(( $(date +%s) - start_time ))
  log "[$name] Atualizado e verificado em ${elapsed}s (${commit_final:0:9})"
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

puladas=0

for vm in "${VMS[@]}"; do
  IFS='|' read -r name ip tipo user <<< "$vm"

  # TOZI e cliente real (conta 6) e o runbook exige OK explicito antes de
  # deploy/restart. Estando no array, um `deploy.sh producao` sem querer a
  # incluiria — por isso ela so entra com --incluir-tozi.
  if [ "$name" == "TOZI" ] && [ "$INCLUIR_TOZI" == "false" ]; then
    warn "[$name] pulada: cliente real. Use --incluir-tozi apos o OK explicito."
    puladas=$((puladas + 1))
    echo ""
    continue
  fi

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
if [ "$puladas" -gt 0 ]; then
  warn "Puladas: ${puladas}"
fi
if [ "$failed" -gt 0 ]; then
  fail "Falharam:${failed_names}"
fi
echo "=========================================="

# Sair com erro quando alguma VM falhar. Antes o script terminava no `echo` e
# devolvia 0 mesmo imprimindo "Falharam: ..." — quem chamasse o deploy de outro
# script ou de um agente lia sucesso.
if [ "$failed" -gt 0 ]; then
  exit 1
fi
