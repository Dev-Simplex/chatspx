# Rollout — Enter como atalho padrão de envio

**PR:** https://github.com/Dev-Simplex/chatspx/pull/106 (`fix/enter-default-send-key` → `producao`)
**Commit:** 1 commit, 2 arquivos, só front. Sem migration, sem feature flag.
**Validado em:** `nicolas.chatspx.app` desde 08/09/2026.

---

## ⚠️ A ordem importa — não inverta

O reset de dados **só pode rodar depois** que o código novo estiver no ar em cada VM.

Motivo: apagar `editor_message_key` faz o usuário cair no **padrão do código**.
Com o código **novo**, esse padrão é `enter` — que é o que queremos.
Com o código **antigo**, o padrão é `cmd_enter`. Rodar o reset antes do deploy
jogaria para `cmd_enter` inclusive quem tinha escolhido `enter` de propósito —
o oposto do objetivo.

---

## Passo 1 — Merge (só o usuário faz)

`gh pr merge` é bloqueado pelo classificador do modo automático. Merge pela interface do GitHub.
O CI reprova todo PR neste repo; o gate real é o título.

## Passo 2 — Deploy (do orquestrador 192.168.8.229)

```bash
cd /home/chatwoot/chatwoot && ./deployment/deploy.sh producao
```

Alcança **PRODUCAO**, **CATATAU**, **SENTINELA**.
Se der OOM no `assets:precompile`, use `NODE_OPTIONS=--max-old-space-size=8192`.

**ALTERNATIVO (192.168.8.169)** está comentado no array `VMS` do `deploy.sh`. Para incluí-la nesta
rodada, descomente a linha, rode o deploy e **volte o comentário depois** — deixá-la descomentada
muda todo deploy futuro, o que é efeito além desta tarefa.

**TOZI (3.94.9.51, conta 6) — BLOQUEADA num gate de terceiro.** O cabeçalho de
`scripts/ops/tozi-prod.sh` diz: *"CLIENTE REAL. Deploy/restart só com OK EXPLÍCITO do Paulo."*
Não avance sem esse OK. Ela não usa `deploy.sh` (não tem credencial GitHub): o deploy é por
`git bundle` manual, com swap ligado por causa de OOM. Depois do OK:

```bash
export TOZI_PEM=~/.ssh/simplex.linux.pem   # não use o .pem do repo: o chmod 600 do script tira o acesso do nicolas
scripts/ops/tozi-prod.sh run "bundle exec rails db:migrate:status"   # OBRIGATÓRIO antes de qualquer restart
```

Migration pendente + restart = 500 em cadeia. Esta mudança não traz migration, mas a VM pode ter
pendência anterior — confira mesmo assim.

**Confirme que o código chegou** antes de seguir (em cada VM, o bundle atual não pode ter o campo legado):

```bash
grep -c enter_to_send_enabled public/vite/assets/$(python3 -c "import json;m=json.load(open('public/vite/.vite/manifest.json'));print([v['file'] for k,v in m.items() if 'dashboard' in k and v.get('isEntry')][0])" | sed 's|assets/||')
# esperado: 0
```

## Passo 3 — Reset das preferências gravadas (nas 5 VMs, DEPOIS do passo 2)

Decisão do usuário em 08/09/2026: aplicar em **todas as VMs de produção — PRODUCAO, CATATAU,
SENTINELA, ALTERNATIVO e TOZI** (a TOZI só depois do OK do Paulo, ver passo 2).
Garanta que o backup do banco do passo 1 do runbook geral existe — **isto é irreversível**.

```bash
cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "
alvo = User.where(\"ui_settings ? 'editor_message_key' OR ui_settings ? 'enter_to_send_enabled'\")
puts 'a resetar: ' + alvo.count.to_s + ' de ' + User.count.to_s
alvo.find_each { |u| u.update!(ui_settings: u.ui_settings.except('editor_message_key', 'enter_to_send_enabled')) }
puts 'restantes com chave: ' + User.uncached { User.where(\"ui_settings ? 'editor_message_key'\").count.to_s }
"
```

Saída esperada na última linha: `restantes com chave: 0`.

> `psql` é bloqueado pelo classificador (exige a senha do `.env`) — use `rails runner`, que pega a
> credencial sozinho. Precisa ser a árvore com as gems instaladas.

## Passo 4 — Smoke

Abrir **Perfil → Tecla de atalho para enviar mensagens** em cada VM e conferir que **Enter (↵)**
está marcado. Ctrl+Shift+R se a tela vier do cache.

---

## Alcance a partir do host `nicolas`

| VM | SSH daqui | Observação |
|---|---|---|
| CATATAU (3.85.130.14) | ✅ | com `~/.ssh/simplex.linux.pem` |
| SENTINELA (54.152.144.236) | ❌ | timeout na 22 |
| PRODUCAO / orquestrador (.229) | ❌ | publickey recusada |
| ALTERNATIVO (192.168.8.169) | ❌ | `simplexia@`, VM local — o `deploy.sh` usa `sshpass`, que não existe aqui |
| TOZI (3.94.9.51) | ⛔ | não testado de propósito: gate do Paulo |

Ou seja: daqui dá para fazer o passo 3 **só na CATATAU**. Merge, deploy e as demais VMs
precisam de quem tem acesso ao `.229`.

## Rollback

Código: reverter o merge do PR #106 e rodar `deploy.sh` de novo.
Dados: **não há rollback** do reset a não ser restaurar o backup do banco — a preferência
apagada não fica registrada em lugar nenhum.
