# PROMPT — Deploy da frota → `90304224cd` (bundle, backend-only)

> Cole numa sessão Claude Code rodando NA **.229**, em `/home/chatwoot/chatwoot`.
> Alvo: `origin/producao` = **`90304224cd`** (carrossel de fotos + selected_option + fotos/Vista/status +
> eval-representatividade). **Delta é backend-only** (0 front, 0 migration nova pro trio) → **bundle +
> restart**, sem rebuild/rsync. Método comprovado (as VMs cliente não têm credencial GitHub → bundle).

## Alvos
| VM | IP | user | estado |
|----|----|------|--------|
| PRODUCAO (.229) | local | chatwoot | `05cf6005c` (ancestral do topo) |
| CATATAU | 3.85.130.14 | ubuntu | `05cf6005c` |
| SENTINELA | 54.166.220.138 | ubuntu | `05cf6005c` |
| AGN | 13.221.167.143 | ubuntu | verificar ao vivo |
| **TOZI** | 3.82.215.109 | ubuntu | `1ffd7c49e` **bundle-SHA divergente** + **sem migration representatividade** → especial |
| FABRICA / ALTERNATIVO | — | — | **fora** (divergida / offline) |

PEM AWS: `/home/chatwoot/chatwoot/simplex.linux.pem`. Comando remoto canônico:
`ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@$IP "sudo -n -u chatwoot bash -lc 'cd /home/chatwoot/chatwoot && <cmd>'"`
(sem `cd` → "Could not locate Gemfile"; sem `bash -lc` → "bundle: command not found"). **Exit code MENTE** →
valide pela saída e pelo `git rev-parse`, nunca pelo `$?`.

## REGRAS DE OURO
1. Uma VM por vez, **gate + rollback** (snapshot `PREV` antes). Check FAIL → rollback + PARA (não vai pra próxima).
2. **Nunca** force/edite migration. `db:migrate` falhou → `git reset --hard $PREV` + PARA + reporta.
3. Nenhuma flag ligada.

## Grupo A — trio + AGN (ancestrais do topo → fast-forward)
Pra cada VM (.229 local primeiro como canary; depois CATATAU, SENTINELA, AGN):
```bash
TOPO=90304224cd
PEM=/home/chatwoot/chatwoot/simplex.linux.pem
# --- .229 (local) ---
cd /home/chatwoot/chatwoot
PREV=$(git rev-parse HEAD)
git fetch origin && git checkout producao && git pull --ff-only origin producao
git rev-parse --short HEAD    # == 90304224cd
RAILS_ENV=production bundle exec rails db:migrate     # 0 pendentes esperado (delta sem migration)
sudo systemctl restart chatwoot.target
# valida: curl -sk -o /dev/null -w '%{http_code}\n' https://chatspx.app  (200)

# --- remotas (CATATAU/SENTINELA/AGN), uma por vez ---
NAME=CATATAU; IP=3.85.130.14      # repetir p/ SENTINELA 54.166.220.138 e AGN 13.221.167.143
R="ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@$IP sudo -n -u chatwoot bash -lc"
PREV=$($R 'cd /home/chatwoot/chatwoot && git rev-parse HEAD')
git bundle create /tmp/spx-$NAME.bundle "$PREV..$TOPO" && git bundle verify /tmp/spx-$NAME.bundle
scp -i $PEM /tmp/spx-$NAME.bundle ubuntu@$IP:/tmp/spx.bundle
ssh -i $PEM ubuntu@$IP "sudo chown chatwoot:chatwoot /tmp/spx.bundle"
$R 'cd /home/chatwoot/chatwoot && git fetch /tmp/spx.bundle producao && git merge --ff-only FETCH_HEAD && git rev-parse --short HEAD'
$R 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate' || { echo "FAIL migrate $NAME"; $R "cd /home/chatwoot/chatwoot && git reset --hard $PREV"; break; }
ssh -i $PEM ubuntu@$IP "sudo -n systemctl restart chatwoot.target"
# valida: HEAD==90304224cd, curl localhost:3000/app/login==200, db:migrate:status sem 'down'
```
> Se `PREV` de alguma VM **não** for ancestral do topo (o `merge --ff-only` recusa), trate como a Tozi abaixo.

## Grupo B — TOZI (divergente + ganha a migration representatividade)
A Tozi está num **bundle-SHA que não existe no GitHub** e **não é ancestral do topo**. NÃO dá ff. Antes de
qualquer coisa, **ver o que ela tem a mais** e decidir:
```bash
PEM=/home/chatwoot/chatwoot/simplex.linux.pem; IP=3.82.215.109; TOPO=90304224cd
T="ssh -i $PEM ubuntu@$IP sudo -n -u chatwoot bash -lc"
PREV=$($T 'cd /home/chatwoot/chatwoot && git rev-parse HEAD')   # 1ffd7c49e
# 1) traz o topo pra Tozi por bundle (base = merge-base que a Tozi tenha)
git bundle create /tmp/tozi.bundle "$TOPO" --not "$PREV" 2>/dev/null || git bundle create /tmp/tozi.bundle "$TOPO"
scp -i $PEM /tmp/tozi.bundle ubuntu@$IP:/tmp/ && ssh -i $PEM ubuntu@$IP "sudo chown chatwoot:chatwoot /tmp/tozi.bundle"
$T 'cd /home/chatwoot/chatwoot && git fetch /tmp/tozi.bundle producao'
# 2) VER o que a Tozi tem a mais que o topo (o divergente do bundle-SHA)
$T "cd /home/chatwoot/chatwoot && git log --oneline $TOPO..HEAD"
#    -> se for só merge/version.json/lixo de bundle: seguir. Se tiver CÓDIGO real: PARE e reporte.
# 3) backup + alinhar no topo (descarta o bundle-SHA divergente)
$T 'cd /home/chatwoot/chatwoot && cp -a . /tmp/tozi-tree-bak 2>/dev/null; git checkout -- public/version.json 2>/dev/null; git reset --hard '"$TOPO"
$T 'cd /home/chatwoot/chatwoot && git rev-parse --short HEAD'    # == 90304224cd
# 4) MIGRATE (a Tozi ganha a coluna representatividade + qualquer pendente) — status antes
$T 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate:status | grep -i down'
$T 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate'
# 5) restart + valida
ssh -i $PEM ubuntu@$IP "sudo -n systemctl restart chatwoot.target"
$T 'for i in $(seq 1 12); do curl -s -o /dev/null -w %{http_code} localhost:3000/app/login; sleep 5; done'  # 200
$T 'cd /home/chatwoot/chatwoot && git rev-parse --short HEAD && RAILS_ENV=production bundle exec rails db:migrate:status | grep -i down'
```
**Isto acaba com o bundle-SHA da Tozi** (ela passa a bater com o GitHub) — era o que o Paulo pediu.

## Validação final (todas)
Por VM: `HEAD == 90304224cd`, `:3000`/HTTPS 200, `db:migrate:status` sem `down`. Reporta VM a VM.

## Fora deste deploy (não fazer aqui)
- **Reprocess do eval (F2.0) na conta 6:** o deploy já ativa a coluna `representatividade` pra evals NOVOS.
  O reprocess dos evals ANTIGOS é a rake/script do Paulo (`f20_eval_reprocess.sh`), caro (~484 chamadas de
  juiz), roda **só na Tozi** — passo separado, não neste prompt.
- **FABRICA / ALTERNATIVO:** fora (divergida / offline).
