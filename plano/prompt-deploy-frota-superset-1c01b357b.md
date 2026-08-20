# PROMPT — Deploy da frota → superset `1c01b357b6` (Paulo + Nicolas + eval de episódios)

> Cole numa sessão Claude Code rodando NA **.229** (CHATSPX-PRODUCAO), em `/home/chatwoot/chatwoot`.
> Alvo: `origin/producao` = **`1c01b357b6`**. Método comprovado: **git bundle (código) + rsync do
> `public/vite` buildado na .229 (front) + db:migrate ROBUSTO**. As VMs cliente não têm credencial GitHub.

## O que sobe
Superset: trabalho do Paulo (Clara áudio, gates, **eval de episódios**, fixes) **+ Nicolas inteiro**
(Puxar Atendimento/isolamento por agente, fix de segurança P11, kanban/anexos/etiquetas). É um deploy
**grande** (106 arquivos de front, várias migrations).

🟢 **A feature do Nicolas é GATED/dormente:** `agent_conversation_isolation` tem `default: false` e o guard
`authorize_agent_conversation_access` é no-op enquanto ninguém liga → **o código sobe dormente, não muda
comportamento até ligar por inbox.** O único que muda comportamento é o **fix P11** (fecha vazamento entre
times), que é desejado. Deploy seguro.

## Estado da frota (desunificada — cada VM num SHA; use o PREV real de cada uma)
| VM | IP | user | current |
|----|----|------|---------|
| PRODUCAO (.229) | local | chatwoot | `7ff128c5` |
| CATATAU | 3.85.130.14 | ubuntu | `1b8a9824` |
| SENTINELA | 54.166.220.138 | ubuntu | `1b8a9824` |
| AGN | 13.221.167.143 | ubuntu | verificar ao vivo |
| TOZI | 3.82.215.109 | ubuntu | `253042d7` (SHA de bundle — pode divergir) |
| FABRICA / ALTERNATIVO | — | — | **fora** |

PEM: `/home/chatwoot/chatwoot/simplex.linux.pem`. Comando remoto canônico (⚠️ sem o `cd` dá "Could not
locate Gemfile"; sem `bash -lc` dá "bundle: command not found"):
`ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@$IP "sudo -n -u chatwoot bash -lc 'cd /home/chatwoot/chatwoot && <cmd>'"`
**Exit code MENTE** → valide pela saída / `git rev-parse` / mtime do manifest, nunca pelo `$?`.

## REGRAS DE OURO
1. Uma VM por vez, **.229 é o canary** — valide antes de propagar. Check FAIL → rollback (`git reset --hard $PREV`) + PARA.
2. **db:migrate ROBUSTO** (loop abaixo) — as VMs têm colunas de fork antigo (`labels.visibility` etc.) que duplicam. Se falhar por OUTRA coisa que não duplicata → PARA e reporta.
3. Nenhuma flag ligada (o Nicolas é dormente de propósito).

## Passo 1 — .229 (canary): atualiza + BUILDA o front (fonte do rsync)
```bash
cd /home/chatwoot/chatwoot
PREV=$(git rev-parse HEAD)
git fetch origin && git checkout producao && git pull --ff-only origin producao   # -> 1c01b357b6
source /usr/local/rvm/scripts/rvm && rvm use 3.4.4
bundle install --jobs $(nproc) --retry 3
pnpm install --frozen-lockfile 2>/dev/null || pnpm install
RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=8192' bundle exec rake assets:precompile
ls -la --time-style=+%H:%M public/vite/.vite/manifest.json     # mtime = agora (senão OOM → refaz)
# --- db:migrate robusto (trata duplicatas do fork antigo) ---
for a in $(seq 1 15); do
  OUT=$(RAILS_ENV=production bundle exec rails db:migrate 2>&1)
  if echo "$OUT" | grep -qiE 'already exists|DuplicateColumn|DuplicateTable'; then
    VER=$(echo "$OUT" | grep -oE 'Migrating to \S+ \([0-9]{14}\)' | tail -1 | grep -oE '[0-9]{14}')
    echo "  migration $VER duplicou (já aplicada de fato) -> registra e segue"
    RAILS_ENV=production bundle exec rails runner "ActiveRecord::Base.connection.execute(%q{INSERT INTO schema_migrations (version) VALUES ('$VER') ON CONFLICT DO NOTHING})"
  else echo "$OUT" | tail -3; break; fi
done
sudo systemctl restart chatwoot.target
curl -sk -o /dev/null -w 'HTTP %{http_code}\n' https://chatspx.app   # 200 -> canary ok
```

## Passo 2 — remotas (CATATAU → SENTINELA → AGN → TOZI), uma por vez
```bash
TOPO=1c01b357b6; PEM=/home/chatwoot/chatwoot/simplex.linux.pem
for VM in "CATATAU 3.85.130.14" "SENTINELA 54.166.220.138" "AGN 13.221.167.143"; do
  set -- $VM; NAME=$1; IP=$2
  R="ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@$IP sudo -n -u chatwoot bash -lc"
  PREV=$($R 'cd /home/chatwoot/chatwoot && git rev-parse HEAD')
  echo "== $NAME (PREV=$PREV) =="
  # código via bundle (delta real desta VM)
  git bundle create /tmp/spx-$NAME.bundle "$PREV..$TOPO" 2>/dev/null || git bundle create /tmp/spx-$NAME.bundle $TOPO --not $PREV
  scp -i $PEM /tmp/spx-$NAME.bundle ubuntu@$IP:/tmp/spx.bundle
  ssh -i $PEM ubuntu@$IP "sudo chown chatwoot:chatwoot /tmp/spx.bundle"
  $R 'cd /home/chatwoot/chatwoot && git fetch /tmp/spx.bundle "*:refs/spx/*" && (git merge --ff-only '"$TOPO"' 2>/dev/null || { echo DIVERGE-checar; git log --oneline '"$TOPO"'..HEAD | head; })'
  # se ff-only recusou (Tozi bundle-SHA): ver o que a VM tem a mais; se for lixo, git reset --hard $TOPO
  # front via rsync DELTA (do public/vite buildado na .229)
  rsync -az --rsync-path="sudo -n -u chatwoot rsync" -e "ssh -i $PEM -o StrictHostKeyChecking=no" \
    /home/chatwoot/chatwoot/public/vite/ ubuntu@$IP:/home/chatwoot/chatwoot/public/vite/
  # migrate robusto
  $R 'cd /home/chatwoot/chatwoot && for a in $(seq 1 15); do OUT=$(RAILS_ENV=production bundle exec rails db:migrate 2>&1); if echo "$OUT" | grep -qiE "already exists|Duplicate"; then VER=$(echo "$OUT" | grep -oE "Migrating to \S+ \([0-9]{14}\)" | tail -1 | grep -oE "[0-9]{14}"); RAILS_ENV=production bundle exec rails runner "ActiveRecord::Base.connection.execute(%q{INSERT INTO schema_migrations (version) VALUES ('"'"'$VER'"'"') ON CONFLICT DO NOTHING})"; else echo "$OUT" | tail -2; break; fi; done'
  ssh -i $PEM ubuntu@$IP "sudo -n systemctl restart chatwoot.target"
  # valida
  $R 'cd /home/chatwoot/chatwoot && git rev-parse --short HEAD; RAILS_ENV=production bundle exec rails db:migrate:status | grep -ci "^\s*down"'
  $R 'for i in $(seq 1 12); do curl -s -o /dev/null -w %{http_code} localhost:3000/app/login; sleep 5; done'  # 200
done
```

## TOZI (por último — cliente real, bundle-SHA `253042d7` diverge)
Mesmo fluxo, mas o `merge --ff-only` provavelmente recusa (SHA de bundle). Veja `git log 1c01b357b6..HEAD`
na Tozi: **se for só lixo de bundle/version.json → `git reset --hard 1c01b357b6`** (elimina o bundle-SHA);
**se tiver código real → PARE e reporte.** Depois rsync + migrate robusto + restart. Prompts da equipe ficam
no banco (deploy não toca IA).

## Validação final
Por VM: `HEAD == 1c01b357b6`, `db:migrate:status` sem `down`, `:3000`/HTTPS 200, manifest com mtime novo.
**Nenhuma flag ligada** — o isolamento do Nicolas fica dormente até ligar por inbox. Reporta VM a VM.
