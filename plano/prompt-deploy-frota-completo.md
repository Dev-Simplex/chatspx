# PROMPT — Deploy AUTÔNOMO da frota via BUNDLE + RSYNC (producao @ 8e854522f)

> Rode NA .229. Execução autônoma. Alvo: `origin/producao` = **`8e854522f`** (já buildado na .229).
> **NÃO use `deploy.sh`/`cwctl`** — as VMs cliente não têm credencial GitHub e não buildam (SIGABRT
> com 4096). Método comprovado (14/07, todas → HTTP 200): **git bundle (código) + rsync do
> `public/vite` já buildado na .229 (assets)**. Front é ENV-agnóstico → mesmo `public/vite` serve todas.

## VMs (IPs REAIS — o deploy.sh está desatualizado)
| VM | IP | Obs |
|----|----|-----|
| PRODUCAO (.229) | local | canary, já em 8e854522f (feito) |
| CATATAU | 3.85.130.14 | |
| SENTINELA | **54.166.220.138** | o `54.152.144.236` do deploy.sh é morto |
| **AGN** | **13.221.167.143** | ⚠️ não está em NENHUM config (nem deploy.sh nem server.js); Walisson informou. INCLUA. Pode estar num commit mais atrás → bundle próprio. |
| TOZI | 3.82.215.109 | por último (cliente real) |
| ALTERNATIVO / FABRICA | — | fora (ALTERNATIVO fora do ar; FABRICA divergida) |

Clientes AWS = user `ubuntu` + `/home/chatwoot/chatwoot/simplex.linux.pem`.

## REGRAS DE OURO
1. **Nunca** edite/force/pule migration. `db:migrate` falhou → rollback + PARA + reporta.
2. Validação **objetiva**. **Exit code MENTE** (erro sai no stdout com exit 0) → valide pela SAÍDA e pelo **mtime do manifest**, nunca pelo `$?`.
3. FAIL numa VM → rollback dela + **PARA** (não vai pra próxima) + reporta.
4. Uma VM de cada vez, com gate. **Nenhuma flag ligada** (sobe dormente).

## Forma canônica de comando remoto (gotchas que custaram tempo)
```
ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@$IP "sudo -n -u chatwoot bash -lc 'cd /home/chatwoot/chatwoot && <cmd>'"
```
Sem `cd` → "Could not locate Gemfile"; sem `bash -lc` → "bundle: command not found" (rvm não carrega em SSH não-interativo); sem `sudo -u chatwoot` → "dubious ownership".

## Por VM (CATATAU → SENTINELA → AGN → TOZI)
```bash
PEM=/home/chatwoot/chatwoot/simplex.linux.pem
NAME=CATATAU; IP=3.85.130.14                      # repetir p/ cada VM da tabela
R="ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@$IP sudo -n -u chatwoot bash -lc"

# 1. snapshot p/ rollback (PREV real DESTA VM — cobre a AGN atrasada)
PREV=$($R 'cd /home/chatwoot/chatwoot && git rev-parse HEAD')

# 2. código via bundle (delta PREV..producao)
cd /home/chatwoot/chatwoot
git bundle create /tmp/spx-$NAME.bundle "$PREV..producao" && git bundle verify /tmp/spx-$NAME.bundle
scp -i $PEM /tmp/spx-$NAME.bundle ubuntu@$IP:/tmp/spx.bundle
ssh -i $PEM ubuntu@$IP "sudo chown chatwoot:chatwoot /tmp/spx.bundle"
$R 'cd /home/chatwoot/chatwoot && git checkout -- public/version.json 2>/dev/null; git fetch /tmp/spx.bundle producao && git merge --ff-only FETCH_HEAD && git rev-parse --short HEAD'

# 3. assets via rsync DELTA (NÃO rebuildar — usa o public/vite já buildado na .229)
rsync -az --rsync-path="sudo -n -u chatwoot rsync" \
  -e "ssh -i $PEM -o StrictHostKeyChecking=no" \
  /home/chatwoot/chatwoot/public/vite/ ubuntu@$IP:/home/chatwoot/chatwoot/public/vite/

# 4. migrations (as 5 do Nicolas)
$R 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate' \
  || { echo "FAIL migrate $NAME → rollback"; $R "cd /home/chatwoot/chatwoot && git reset --hard $PREV"; break; }

# 5. restart
ssh -i $PEM ubuntu@$IP "sudo -n systemctl restart chatwoot.target"

# 6. VALIDAÇÃO OBJETIVA (gate)
$R 'cd /home/chatwoot/chatwoot && git rev-parse --short HEAD' | grep -q 8e854522f || { echo "FAIL HEAD $NAME"; break; }
$R 'for i in $(seq 1 12); do curl -s -o /dev/null -w %{http_code} localhost:3000/app/login; sleep 5; done' | tail -c3 | grep -q 200 || { echo "FAIL http $NAME"; break; }
$R 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate:status' | grep -qi ' down ' && { echo "FAIL migrate pendente $NAME"; break; }
$R 'stat -c %Y /home/chatwoot/chatwoot/public/vite/.vite/manifest.json'   # tem que ser recente
echo "OK $NAME"
# Se qualquer check falhou (break acima): rollback já foi/faça git reset --hard $PREV + restart, e PARE.
```

## TOZI — extras (cliente real)
Mesmo fluxo, **por último**, com snapshot+rollback. A chave dela: RSA embutida em
`deployment/panel/server.js` (const `SSH_KEY`) ou a mesma PEM. Prompts da equipe ficam no DB (o deploy
só troca código+assets+migrations, não toca IA). Erro pré-existente `OrphanRetriageJob`
(`blocked? for nil`, Account 6) **não é regressão**.

## Sobre credencial GitHub nas AWS
Não configure agora — é mudança à parte; o bundle já resolve. Fora de escopo deste deploy.

## Relatório final (obrigatório)
Por VM: HEAD final, resultado da validação (OK/FAIL), se houve rollback. Flags: nenhuma ligada.
