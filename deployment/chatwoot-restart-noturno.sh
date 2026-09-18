#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  Restart noturno do SPX: reinicia os servicos web e workers, NUNCA a VM.
#
#      sudo SIMULAR=1 /usr/local/sbin/chatwoot-restart-noturno.sh   # tudo menos o restart
#
#  Disparado pelo chatwoot-restart-noturno.timer as 20:00 de Cuiaba. O deploy
#  deixa codigo e assets no disco de dia; o processo no ar segue no codigo
#  antigo (preload_app! no Puma, manifest do Vite memoizado) ate este restart.
#  Decisao do dono em 18/09/2026: reiniciar VM de cliente de dia e ruim.
#
#  Nada de reboot, shutdown ou stop/start da VM: na AWS as VMs nao tem Elastic
#  IP e o endereco publico muda num stop/start (a TOZI ja trocou assim).
#
#  Roda como root, mas git, bundle e o log rodam como `chatwoot`. O checkout e
#  dele: root rodando git ali executaria hook ou config que o chatwoot escreveu,
#  e root escrevendo no log/ dele seguiria um symlink plantado. Pelo mesmo
#  motivo o service aponta para a copia em /usr/local/sbin, nunca para esta.
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

DIR=/home/chatwoot/chatwoot
LOG="$DIR/log/restart-noturno.log"
SIMULAR="${SIMULAR:-0}"

como_chatwoot() { sudo -n -H -u chatwoot "$@"; }
avisa() { logger -t chatwoot-restart-noturno -- "$1"; echo "$1"; }

commit=$(como_chatwoot git -C "$DIR" rev-parse --short=10 HEAD 2>/dev/null || echo "?")

# Uma linha por noite, legivel sem root, que o raio-X le:
#   <quando> <resultado> <commit> <detalhe>
# Com SIMULAR=1 o resultado ganha o prefixo "simulado-", para nao passar por noite de verdade.
termina() {
  local resultado="$1" detalhe="$2" codigo="${3:-0}"
  [ "$SIMULAR" = 1 ] && resultado="simulado-$resultado"
  avisa "$resultado $commit: $detalhe"
  printf '%s %s %s %s\n' "$(TZ=America/Cuiaba date -Is)" "$resultado" "$commit" "$detalhe" \
    | como_chatwoot tee -a "$LOG" >/dev/null
  exit "$codigo"
}

# 1. Os units do SPX que existem nesta VM. A PRODUCAO tem chatwoot-worker.bulk e .realtime, que o
#    chatwoot.target nao cobre; as outras so tem web.1 e worker.1. O que esta parado (inactive)
#    fica parado: restart ligaria de volta um worker que alguem desligou de proposito.
mapfile -t units < <(systemctl list-units --type=service --all --no-legend --plain \
  'chatwoot-web*' 'chatwoot-worker*' | awk '$3 != "inactive" {print $1}')
[ "${#units[@]}" -gt 0 ] || termina abortou "nenhum chatwoot-web/worker no ar nesta VM" 1

# 2. O web ja serve o disco? A regua do deployment/deploy.sh (web_subiu_depois_do_head): o web
#    subiu depois da ultima vez que a branch andou. Reflog da BRANCH, nao do HEAD, porque um
#    checkout na mesma branch tambem escreve no do HEAD. O public/version.json nao responde isso.
#    Na duvida (nao leu um dos dois), reinicia: e noite, e um restart a mais e melhor que codigo
#    parado no disco.
RE_BRANCH_ANDOU='@\{([0-9]+)\}'
RE_WEB_SUBIU='@([0-9]+)'
branch=$(como_chatwoot git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
branch_andou=$(como_chatwoot git -C "$DIR" reflog -1 --date=unix --format=%gd "$branch" 2>/dev/null)
web_subiu=$(systemctl show chatwoot-web.1 -p ActiveEnterTimestamp --value --timestamp=unix 2>/dev/null)
andou="" subiu=""
[[ "$branch_andou" =~ $RE_BRANCH_ANDOU ]] && andou="${BASH_REMATCH[1]}"
[[ "$web_subiu" =~ $RE_WEB_SUBIU ]] && subiu="${BASH_REMATCH[1]}"
if [ -n "$andou" ] && [ -n "$subiu" ] && [ "$subiu" -ge "$andou" ]; then
  termina pulou "web ja serve o disco (subiu depois de $branch andar)"
fi

# 3. Migration pendente + restart = 500 em cadeia (PG::UndefinedColumn, incidente de 24/04/2026).
#    Aqui a duvida vai para o outro lado: sem nenhuma linha `up` a leitura falhou, e nao reinicia.
status=$(sudo -n -i -u chatwoot bash -lc "cd $DIR && RAILS_ENV=production bundle exec rails db:migrate:status" 2>/dev/null)
ups=$(grep -cE '^\s+up\s' <<<"$status")
downs=$(grep -cE '^\s+down\s' <<<"$status")
[ "$ups" -gt 0 ] || termina abortou "nao consegui ler o db:migrate:status" 1
[ "$downs" -eq 0 ] || termina abortou "$downs migration(s) pendente(s): rode o db:migrate" 1

# 4. Restart, uma vez so. Espera o web responder 200 em /api; se nao responder, registra e sai sem
#    tentar de novo: restart em laco derruba mais do que conserta.
porta=$(systemctl show chatwoot-web.1 -p Environment --value 2>/dev/null | tr ' ' '\n' | sed -n 's/^PORT=//p')
porta="${porta:-3000}"
[ "$SIMULAR" = 1 ] && termina reiniciaria "${units[*]}, depois esperaria /api 200 na porta $porta"

systemctl restart "${units[@]}" || termina falhou "systemctl restart devolveu erro: ${units[*]}" 1
for _ in $(seq 36); do
  sleep 5
  codigo_http=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$porta/api")
  [ "$codigo_http" = 200 ] && termina reiniciou "${units[*]}, /api 200"
done
termina falhou "reiniciou ${units[*]}, mas /api nao respondeu 200 em 3 min" 1
