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

# 2. Quem ja serve o disco? A regua do deployment/deploy.sh (web_subiu_depois_do_head), aplicada a
#    CADA unit: ele subiu depois da ultima vez que a branch andou. Unit por unit porque o web pode
#    cair e subir sozinho de dia (Restart=always) ja no codigo novo enquanto os workers seguem no
#    velho: olhando so o web, a noite pularia e o Sidekiq ficaria atrasado ate a proxima mudanca.
#    Reflog da BRANCH, nao do HEAD, porque um checkout na mesma branch tambem escreve no do HEAD. O
#    public/version.json nao responde isso. Na duvida (reflog ilegivel, unit sem hora de subida ou
#    fora do ar), reinicia: e noite, e um restart a mais e melhor que codigo parado no disco.
RE_BRANCH_ANDOU='@\{([0-9]+)\}'
RE_SUBIU='@([0-9]+)'
branch=$(como_chatwoot git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
branch_andou=$(como_chatwoot git -C "$DIR" reflog -1 --date=unix --format=%gd "$branch" 2>/dev/null)
andou=""
[[ "$branch_andou" =~ $RE_BRANCH_ANDOU ]] && andou="${BASH_REMATCH[1]}"
atrasados=()
for u in "${units[@]}"; do
  subiu=""
  [[ "$(systemctl show "$u" -p ActiveEnterTimestamp --value --timestamp=unix 2>/dev/null)" =~ $RE_SUBIU ]] \
    && subiu="${BASH_REMATCH[1]}"
  if [ -z "$andou" ] || [ -z "$subiu" ] || [ "$subiu" -lt "$andou" ] || ! systemctl is-active -q "$u"; then
    atrasados+=("$u")
  fi
done
[ "${#atrasados[@]}" -gt 0 ] || termina pulou "${units[*]} ja servem o disco (subiram depois de $branch andar)"

# 3. Migration pendente + restart = 500 em cadeia (PG::UndefinedColumn, incidente de 24/04/2026).
#    Aqui a duvida vai para o outro lado: sem nenhuma linha `up` a leitura falhou, e nao reinicia.
status=$(sudo -n -i -u chatwoot bash -lc "cd $DIR && RAILS_ENV=production bundle exec rails db:migrate:status" 2>/dev/null)
ups=$(grep -cE '^\s+up\s' <<<"$status")
downs=$(grep -cE '^\s+down\s' <<<"$status")
[ "$ups" -gt 0 ] || termina abortou "nao consegui ler o db:migrate:status" 1
[ "$downs" -eq 0 ] || termina abortou "$downs migration(s) pendente(s): rode o db:migrate" 1

# 4. Restart so dos atrasados, uma vez so: se algo nao voltar, registra e sai sem tentar de novo,
#    porque restart em laco derruba mais do que conserta. Com o web entre eles, a prova inclui o
#    /api responder 200; so com workers, basta eles seguirem no ar.
web_junto=""
for u in "${atrasados[@]}"; do [[ "$u" == chatwoot-web* ]] && web_junto=1; done
porta=$(systemctl show chatwoot-web.1 -p Environment --value 2>/dev/null | tr ' ' '\n' | sed -n 's/^PORT=//p')
porta="${porta:-3000}"
if [ "$SIMULAR" = 1 ]; then
  [ -n "$web_junto" ] && prova="esperaria /api 200 na porta $porta" || prova="conferiria se seguem no ar"
  termina reiniciaria "${atrasados[*]}, depois $prova"
fi

systemctl restart "${atrasados[@]}" || termina falhou "systemctl restart devolveu erro: ${atrasados[*]}" 1
prova="no ar"
if [ -n "$web_junto" ]; then
  respondeu=""
  for _ in $(seq 36); do
    sleep 5
    codigo_http=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$porta/api")
    [ "$codigo_http" = 200 ] && { respondeu=1; break; }
  done
  [ -n "$respondeu" ] || termina falhou "reiniciou ${atrasados[*]}, mas /api nao respondeu 200 em 3 min" 1
  prova="no ar, /api 200"
else
  sleep 15
fi
for u in "${atrasados[@]}"; do
  systemctl is-active -q "$u" || termina falhou "reiniciou ${atrasados[*]}, mas $u nao ficou no ar" 1
done
termina reiniciou "${atrasados[*]}, $prova"
