#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  Deploy do nível 2 do Captador (feature/captador-nivel2) na frota do SPX.
#  Roteiro completo em docs/deploy-captador.md. Mesmo mecanismo do /promover-pr
#  (.claude/commands/promover-pr.md): pacote git bundle + merge --ff-only nas VMs,
#  assets gerados uma vez na PRODUCAO, timer das 20:00, NENHUM restart de dia.
#
#  Roda na PRODUCAO (192.168.8.229), como chatwoot, no checkout /home/chatwoot/chatwoot.
#
#    captador-deploy.sh ensaio               # ensaio a seco do git (merge, pacote, ff, revert), só em /tmp
#    captador-deploy.sh verificar [VM ...]   # leitura: commit, serviços, timer, /api, rota do Captador, erros
#    captador-deploy.sh integrar             # abre o PR feature -> producao (o merge é gate humano)
#    captador-deploy.sh producao             # .229: ff da producao, assets, timer e o pacote da frota
#    captador-deploy.sh vm <NOME>            # uma VM: pacote, ff-only, assets, timer (sem restart)
#    captador-deploy.sh reverter <merge_sha> # abre o PR de revert (volta pelo mesmo caminho)
#
#  Tudo que muda algo só IMPRIME os comandos. Para executar de verdade: EXECUTAR=1.
#  TOZI e CDSOLAR são clientes: só com --incluir-tozi / --incluir-cdsolar, depois do OK
#  explícito do usuário a CADA deploy. Restart na hora só na PRODUCAO, com
#  --reiniciar-agora E REINICIAR_OK=PRODUCAO (o OK do usuário para aquele restart).
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

D="${CHATSPX_DIR:-/home/chatwoot/chatwoot}"
REPO=Dev-Simplex/chatspx
FEATURE="${FEATURE:-origin/feature/captador-nivel2}"
WORK=/tmp/captador-deploy
EXECUTAR="${EXECUTAR:-0}"
ROTA=/spx/captador/v1/catalogo
PEM="${CHATSPX_PEM:-}"
[ -n "$PEM" ] || { [ -r "$HOME/.ssh/simplex.linux.pem" ] && PEM="$HOME/.ssh/simplex.linux.pem" || PEM="$D/simplex.linux.pem"; }
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=30)

# nome|endereço|usuário. Mesma lista do deployment/deploy.sh e do scripts/ops/pr-raiox.py (a TOZI
# não tem Elastic IP: se não responder, confira o console EC2). Ordem = ordem do deploy.
VMS=(
  "PRODUCAO|local|chatwoot"
  "CATATAU|3.85.130.14|ubuntu"
  "SENTINELA|54.166.220.138|ubuntu"
  "FABRICA|3.87.182.184|ubuntu"
  "AGN|13.221.167.143|ubuntu"
  "TOZI|3.94.9.51|ubuntu"
  "CDSOLAR|13.218.193.75|ubuntu"
)
ARGS=("$@")

log() { printf '\033[0;32m[%s]\033[0m %s\n' "$(TZ=America/Cuiaba date +%H:%M:%S)" "$*"; }
falha() { printf '\033[0;31mERRO:\033[0m %s\n' "$*" >&2; exit 1; }
roda() { if [ "$EXECUTAR" = 1 ]; then "$@"; else printf '  (a seco)'; printf ' %q' "$@"; echo; fi; }

vm_linha() {
  local v
  for v in "${VMS[@]}"; do [ "${v%%|*}" = "$1" ] && { echo "$v"; return 0; }; done
  return 1
}
vm_valida() { vm_linha "$1" >/dev/null || falha "VM desconhecida: $1 (use: ${VMS[*]%%|*})"; }

# Roda um script bash na VM como chatwoot, com o ambiente de login (Ruby do RVM). Na PRODUCAO é
# local. `sudo -i` começa no home do chatwoot: todo comando usa caminho absoluto.
na_vm() {
  local host user
  IFS='|' read -r _ host user <<<"$(vm_linha "$1")"
  if [ "$host" = local ]; then bash -l -s; else ssh -i "$PEM" "${SSH_OPTS[@]}" "$user@$host" "sudo -n -i -u chatwoot bash -s"; fi
}
na_vm_cmd() { local nome=$1; shift; na_vm "$nome" <<<"$*"; }

tem_flag() { [[ " ${ARGS[*]} " == *" $1 "* ]]; }
cliente_liberado() {
  case "$1" in
    TOZI) tem_flag --incluir-tozi ;;
    CDSOLAR) tem_flag --incluir-cdsolar ;;
    *) true ;;
  esac
}

# Não deploye entre 19:50 e 20:10 de Cuiabá: o timer pode pegar código no disco pela metade.
fora_da_janela_do_timer() {
  local hm
  hm=$(TZ=America/Cuiaba date +%H%M)
  [ "$hm" -lt 1950 ] || [ "$hm" -gt 2010 ] || falha "19:50-20:10 de Cuiabá: o timer das 20:00 pode pegar o deploy no meio"
}

# ---------------------------------------------------------------------------------------------
# verificar: só leitura. Depois do restart (20:00 ou --reiniciar-agora) a rota do Captador tem de
# responder 401 (sem assinatura); 404 quer dizer que o web ainda serve o código anterior.
cmd_verificar() {
  local nomes=() nome a
  for a in "$@"; do [[ "$a" == --* ]] || nomes+=("$a"); done
  [ ${#nomes[@]} -gt 0 ] || nomes=("${VMS[@]%%|*}")
  for nome in "${nomes[@]}"; do
    vm_valida "$nome"
    cliente_liberado "$nome" || { log "$nome: pulada (cliente: até a leitura só com o OK e --incluir-*)"; continue; }
    log "$nome"
    na_vm "$nome" <<VERIFICA || log "$nome: sem resposta"
D=/home/chatwoot/chatwoot
porta=\$(systemctl show chatwoot-web.1 -p Environment --value | tr ' ' '\n' | sed -n 's/^PORT=//p'); porta=\${porta:-3000}
echo "  commit: \$(git -C \$D rev-parse --short=10 HEAD) (\$(git -C \$D rev-parse --abbrev-ref HEAD))"
for u in chatwoot-web.1 chatwoot-worker.1; do echo "  \$u: \$(systemctl is-active \$u) desde \$(systemctl show \$u -p ActiveEnterTimestamp --value)"; done
echo "  branch andou: \$(git -C \$D reflog -1 --date=iso --format=%gd \$(git -C \$D rev-parse --abbrev-ref HEAD))"
echo "  timer: \$(systemctl is-enabled chatwoot-restart-noturno.timer 2>/dev/null); última noite: \$(tail -1 \$D/log/restart-noturno.log 2>/dev/null)"
echo "  /api: \$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:\$porta/api)"
rota=\$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:\$porta$ROTA)
case \$rota in 401) echo "  $ROTA: 401 (nível 2 no ar)";; 404) echo "  $ROTA: 404 (web ainda no código anterior: carrega às 20:00)";; *) echo "  $ROTA: \$rota (INESPERADO)";; esac
# Journal desde a subida do web, no máximo 2 h para trás: varrer o dia inteiro com glob de unit
# leva minutos e pesa na VM (medido na .229 em 27/09). Rode logo depois do restart das 20:00.
subiu=\$(systemctl show chatwoot-web.1 -p ActiveEnterTimestamp --value --timestamp=unix | tr -d @)
limite=\$(( \$(date +%s) - 7200 )); desde=\$(( \${subiu:-0} > limite ? \${subiu:-0} : limite ))
unidades=\$(systemctl list-units --type=service --no-legend --plain 'chatwoot-web*' 'chatwoot-worker*' | awk '{printf "-u %s ", \$1}')
if erros=\$(timeout 60 sudo -n journalctl \$unidades --since "@\$desde" -p err --no-pager -q 2>/dev/null); then
  echo "  erros no journal desde \$(date -u -d @\$desde '+%H:%M UTC'): \$(printf '%s' "\$erros" | grep -c .)"
else
  echo "  journal: sem sudo para ler ou passou de 60 s (confira com o usuário ubuntu)"
fi
echo "  linhas do Captador com erro no production.log: \$(tail -n 20000 \$D/log/production.log 2>/dev/null | grep -ci 'captador.*\(error\|exception\)')"
echo "  migrations pendentes: \$(cd \$D && timeout 120 bundle exec rake db:migrate:status RAILS_ENV=production 2>/dev/null | grep -c '^ *down')"
df -h / | awk 'NR==2 {print "  disco: " \$5 " usado, " \$4 " livre"}'
VERIFICA
  done
}

# ---------------------------------------------------------------------------------------------
# ensaio: o git inteiro a seco, em clones --bare --shared em /tmp (o checkout não muda). Ida: merge
# como o do GitHub (commit com dois pais), pacote da base até o merge e fetch producao:producao na
# "VM", que recusa o que não for fast-forward. Volta: revert -m 1 do merge (merge-tree com o merge
# como base), pacote do merge até o revert, e a árvore da VM tem de ficar igual à da base.
cmd_ensaio() {
  local base feat tmp tree merge volta
  base=$(git -C "$D" rev-parse "${BASE:-origin/producao}")
  feat=$(git -C "$D" rev-parse "$FEATURE") || falha "sem $FEATURE: git -C $D fetch origin feature/captador-nivel2"
  tmp=$(mktemp -d /tmp/captador-ensaio.XXXX)
  # shellcheck disable=SC2064 # expande agora: $tmp é local e já não existe no EXIT
  trap "rm -rf '$tmp'" EXIT
  local P=(git -C "$tmp/producao.git") V=(git -C "$tmp/vm.git")
  local ID=(git -c user.name=ensaio -c user.email=ensaio@captador.local -C "$tmp/producao.git")

  git clone -q --bare --shared "$D" "$tmp/producao.git"
  git clone -q --bare --shared "$D" "$tmp/vm.git"
  "${P[@]}" update-ref refs/heads/producao "$base"
  "${V[@]}" update-ref refs/heads/producao "$base"

  tree=$("${P[@]}" merge-tree --write-tree "$base" "$feat" | head -1) || falha "o merge conflita com a producao: resolva na feature antes do PR"
  merge=$("${ID[@]}" commit-tree "$tree" -p "$base" -p "$feat" -m "Merge (ensaio) feature/captador-nivel2")
  "${P[@]}" update-ref refs/heads/producao "$merge"
  "${P[@]}" bundle create -q "$tmp/ida.bundle" producao --not "$base" 2>/dev/null
  "${V[@]}" bundle verify -q "$tmp/ida.bundle" >/dev/null 2>&1
  "${V[@]}" fetch -q "$tmp/ida.bundle" producao:producao || falha "ida: a VM recusou o pacote (não é fast-forward)"
  [ "$("${V[@]}" rev-parse producao)" = "$merge" ] || falha "ida: a VM não chegou ao merge"
  log "ida ok: base ${base:0:10} -> merge ${merge:0:10} (pacote $(du -h "$tmp/ida.bundle" | cut -f1), $("${P[@]}" diff --name-only "$base" "$merge" | wc -l | tr -d ' ') arquivos)"

  tree=$("${P[@]}" merge-tree --write-tree --merge-base="$merge" "$merge" "$base" | head -1) || falha "volta: o revert conflita"
  volta=$("${ID[@]}" commit-tree "$tree" -p "$merge" -m "Revert (ensaio) do merge ${merge:0:10}")
  "${P[@]}" diff --quiet "$base" "$volta" || falha "volta: o revert não restaura a árvore da base"
  "${P[@]}" update-ref refs/heads/producao "$volta"
  "${P[@]}" bundle create -q "$tmp/volta.bundle" producao --not "$merge" 2>/dev/null
  "${V[@]}" fetch -q "$tmp/volta.bundle" producao:producao || falha "volta: a VM recusou o pacote"
  "${V[@]}" diff --quiet "$base" producao || falha "volta: a VM não voltou à árvore da base"
  log "volta ok: revert ${volta:0:10} deixa a VM com a árvore de ${base:0:10} (pacote $(du -h "$tmp/volta.bundle" | cut -f1)); sem migração a desfazer"
}

# ---------------------------------------------------------------------------------------------
cmd_integrar() {
  log "PR feature/captador-nivel2 -> producao (o merge fica com um humano, depois do raio-X e da revisão)"
  roda gh pr create -R "$REPO" --base producao --head feature/captador-nivel2 \
    --title "feat(captador): integração nativa nível 2" \
    --body "Integração nativa com o Captador: login, abertura de conversa assinada, eventos, catálogo, reconciliação e painel na conversa. Desligada por conta (Super Admin, captador_integration). Sem migração. Roteiro: docs/deploy-captador.md."
  cat <<'PASSOS'
  Depois:
    python3 scripts/ops/pr-raiox.py <PR> --frota          # fase 1 do /promover-pr (o OK de TOZI/CDSOLAR vale para esta leitura)
    sha=$(gh pr view <PR> --json headRefOid --jq .headRefOid)
    gh pr merge <PR> --merge --match-head-commit "$sha"   # gate humano
PASSOS
}

# ---------------------------------------------------------------------------------------------
# Com o sudo de quem entra na VM (chatwoot na .229, ubuntu nas AWS), caminhos absolutos: o script
# vai para /usr/local/sbin como root porque o do checkout é do chatwoot (ver o /promover-pr).
instalar_timer() {
  local dep=/home/chatwoot/chatwoot/deployment host user cmd
  cmd="sudo -n install -m 750 -o root -g root $dep/chatwoot-restart-noturno.sh /usr/local/sbin/"
  cmd+=" && sudo -n install -m 644 -o root -g root $dep/chatwoot-restart-noturno.service $dep/chatwoot-restart-noturno.timer /etc/systemd/system/"
  cmd+=" && sudo -n systemctl daemon-reload && sudo -n systemctl enable --now chatwoot-restart-noturno.timer"
  IFS='|' read -r _ host user <<<"$(vm_linha "$1")"
  if [ "$host" = local ]; then roda bash -c "$cmd"; else roda ssh -i "$PEM" "${SSH_OPTS[@]}" "$user@$host" "$cmd"; fi
}

# producao: a .229 alcança o GitHub. ff da producao, build dos assets (o nível 2 muda o front),
# timer e o pacote da frota (bundle desde o commit que as VMs têm + assets novos com .gz).
cmd_producao() {
  fora_da_janela_do_timer
  local antes marco
  antes=$(git -C "$D" rev-parse HEAD)
  marco=$(date -u +%Y-%m-%dT%H:%M:%S)
  log "PRODUCAO em ${antes:0:10}; o pacote da frota vai de ${antes:0:10} até o topo da producao"
  roda git -C "$D" fetch origin producao
  roda git -C "$D" merge --ff-only origin/producao
  roda bash -lc "cd '$D' && RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=12288' bundle exec rake assets:precompile"
  roda bash -lc "cd '$D' && find public/vite -newermt '$marco' -type f \\( -name '*.js' -o -name '*.css' -o -name '*.json' -o -name '*.svg' \\) ! -name '*.map' -exec gzip -kf9 {} +"
  roda mkdir -p "$WORK"
  roda bash -lc "cd '$D' && find public/vite -newermt '$marco' -type f ! -name '*.map' -print0 > '$WORK/novos.list0' && tar -czf '$WORK/assets.tgz' --null -T '$WORK/novos.list0'"
  roda git -C "$D" bundle create "$WORK/rel.bundle" producao --not "$antes"
  roda bash -lc "cd '$D' && [ \$(RAILS_ENV=production bundle exec rake db:migrate:status | grep -c '^ *down') -eq 0 ]"
  instalar_timer PRODUCAO
  if tem_flag --reiniciar-agora; then
    [ "${REINICIAR_OK:-}" = PRODUCAO ] || falha "--reiniciar-agora exige REINICIAR_OK=PRODUCAO (o OK do usuário para este restart)"
    # shellcheck disable=SC2046
    roda sudo -n systemctl restart $(systemctl list-units --type=service --state=active --no-legend --plain 'chatwoot-web*' 'chatwoot-worker*' | awk '{print $1}')
    log "PRODUCAO reiniciada: em 1 minuto, captador-deploy.sh verificar PRODUCAO ($ROTA tem de dar 401)"
  else
    log "PRODUCAO: no disco, carrega às 20:00. Depois das 20:05: captador-deploy.sh verificar PRODUCAO"
  fi
}

# vm: uma VM por vez. Pacote copiado, ff-only (recusa se a VM divergir), assets por cima (sem
# apagar os antigos: aba aberta segue servida), migrate:status zerado, timer. Nada de restart.
cmd_vm() {
  local nome=${1:-} host user
  [ -n "$nome" ] && [ "$nome" != PRODUCAO ] || falha "uso: captador-deploy.sh vm <CATATAU|SENTINELA|FABRICA|AGN|TOZI|CDSOLAR>"
  vm_valida "$nome"
  cliente_liberado "$nome" || falha "$nome é cliente: só com --incluir-${nome,,}, depois do OK explícito do usuário"
  fora_da_janela_do_timer
  [ "$EXECUTAR" != 1 ] || { [ -s "$WORK/rel.bundle" ] && [ -s "$WORK/assets.tgz" ]; } || falha "rode 'producao' antes: falta o pacote em $WORK"
  IFS='|' read -r _ host user <<<"$(vm_linha "$nome")"
  log "$nome ($host): pacote, ff-only, assets, timer"
  roda scp -i "$PEM" "${SSH_OPTS[@]}" "$WORK/rel.bundle" "$WORK/assets.tgz" "$user@$host:/tmp/"
  roda ssh -i "$PEM" "${SSH_OPTS[@]}" "$user@$host" "chmod 644 /tmp/rel.bundle /tmp/assets.tgz"
  roda na_vm_cmd "$nome" "set -e; D=/home/chatwoot/chatwoot; git -C \$D bundle verify -q /tmp/rel.bundle; git -C \$D fetch -q /tmp/rel.bundle producao && git -C \$D merge --ff-only FETCH_HEAD; tar -xzf /tmp/assets.tgz -C \$D; cd \$D && [ \$(RAILS_ENV=production bundle exec rake db:migrate:status | grep -c '^ *down') -eq 0 ]; git -C \$D rev-parse --short=10 HEAD"
  instalar_timer "$nome"
  log "$nome: no disco, carrega às 20:00. Depois: captador-deploy.sh verificar $nome"
}

# ---------------------------------------------------------------------------------------------
# reverter: o caminho de volta é o mesmo da ida. Branch com `git revert -m 1 <merge>` a partir da
# producao, PR, merge (gate humano), e então `producao` + `vm` como num deploy normal.
cmd_reverter() {
  local merge=${1:-}
  [ -n "$merge" ] || falha "uso: captador-deploy.sh reverter <sha do merge do PR>"
  cat <<'ANTES'
  Antes do código: desligue o efeito, que não precisa de deploy e vale na hora.
    Super Admin → conta → "Captador integration enabled" desmarcado (e apague o hook em Integrações → Captador).
    Com isso /spx/captador/* responde 401, o painel some e nenhum evento sai.
ANTES
  roda git -C "$D" fetch origin producao
  roda git -C "$D" worktree add -b revert/captador-nivel2 /tmp/captador-revert origin/producao
  roda git -C /tmp/captador-revert revert --no-edit -m 1 "$merge"
  roda git -C /tmp/captador-revert push origin revert/captador-nivel2
  roda gh pr create -R "$REPO" --base producao --head revert/captador-nivel2 \
    --title "revert: integração nativa nível 2 do Captador" --body "Reverte o merge $merge. Sem migração a desfazer."
  roda git -C "$D" worktree remove /tmp/captador-revert
  log "depois do merge do PR de revert: captador-deploy.sh producao; captador-deploy.sh vm <VM> (uma por vez)"
  log "para subir de novo mais tarde: reverta o revert (um novo merge da feature não traz os commits de volta)"
}

case "${1:-}" in
  ensaio) cmd_ensaio ;;
  verificar) shift; cmd_verificar "$@" ;;
  integrar) cmd_integrar ;;
  producao) cmd_producao ;;
  vm) cmd_vm "${2:-}" ;;
  reverter) cmd_reverter "${2:-}" ;;
  *) sed -n '2,21p' "$0" | sed 's/^#  \{0,1\}//'; exit 1 ;;
esac
