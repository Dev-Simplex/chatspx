# Rollout — Correção "Não Lidas" (admin vê todas + robustez)

**Commits (na `nicolas`, a portar p/ `producao`):** 4 — `fbd6f1acc`, `ab8071468`, `2df2763ce`, `adef78236` (Correções 1, 1b, 1c, 1d). Ver [`plano-correcao-nao-lidas.md`](plano-correcao-nao-lidas.md).
**Patches:** [`task/unread-fix-producao.mbox`](unread-fix-producao.mbox) (mbox único, 4 commits, p/ `git am`) — ou [`task/unread-fix-patches/`](unread-fix-patches/) (1 arquivo por commit). O antigo `unread-admin-visibility.patch` cobria só `fbd6f1acc` — **não usar**.
**Migration:** nenhuma (o `db:migrate` do deploy é no-op para esta correção).
**Status:** ✅ rodando e validado em `nicolas.chatspx.app` (build+restart feito 2026-06-12). Falta levar para `producao` e propagar à frota.
**✅ Verificado (2026-06-12):** os 4 patches aplicam **limpo** sobre `origin/producao` (HEAD `29a32046f`) via `git am --3way`, testado em worktree isolado — sem conflito.

> **Por que precisa ser feito fora do host `nicolas`:** este host tem chave SSH **read-only** no GitHub (não pusha — confirmado: "key marked as read only") e **não** alcança o orquestrador da frota (host key verification failed; sem `simplex.linux.pem` / `sshpass`). Os passos abaixo precisam de uma conta com **push em `Dev-Simplex/chatspx`** e do host **CHATSPX-PRODUCAO (192.168.8.229)**.

---

## Passo A — levar os fixes para `producao` + PR

Numa máquina com **acesso de escrita** ao repo (a mesma conta que pusha os outros commits do `chatspx`). Copie o mbox antes:

```bash
scp chatwoot@192.168.8.98:/home/chatwoot/chatwoot/task/unread-fix-producao.mbox .
```

Aplique os 4 commits, pushe e abra o PR:

```bash
git fetch origin
git checkout -b fix/unread-view origin/producao
git am --3way unread-fix-producao.mbox   # aplica os 4 commits (verificado: limpo sobre producao)
git push -u origin fix/unread-view
```

PR (base **producao** ← head **fix/unread-view**):
```
https://github.com/Dev-Simplex/chatspx/compare/producao...fix/unread-view?expand=1
```
Revise (13 arquivos, +296/−43) e faça **merge em `producao`**.

> Sem PR: `git checkout producao && git merge --ff-only fix/unread-view && git push origin producao`.

### Arquivos (13, nos 4 commits)
- `app/javascript/dashboard/components/ChatList.vue` — default da aba + guard anti-crash + paginação + clamp custom-role + redirect unread + sync aba→URL
- `app/javascript/dashboard/helper/unreadViewHelper.js` (novo) + spec — `defaultAssigneeTab`/`resolveAssigneeTab`
- `app/javascript/dashboard/helper/URLHelper.js` + spec — caso `unread` em conversationUrl/listPageURL
- `app/javascript/dashboard/helper/routeHelpers.js` + spec — rotas unread em isAConversationRoute/getConversationDashboardRoute
- `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue` — back-button unread
- `app/javascript/dashboard/components-next/copilot/CopilotLauncher.vue` — CONVERSATION_ROUTES
- `app/javascript/dashboard/components-next/sidebar/SidebarGroup.vue` — activeChild unread (default ALL)
- `app/javascript/dashboard/store/modules/conversations/helpers/actionHelpers.js` — DRY UNREAD_ROUTES
- `app/finders/conversation_finder.rb` + `app/services/conversations/permission_filter_service.rb` — detecção de admin unificada

---

## Passo B — deploy da frota

⚠️ Atinge **produção de cliente** (PRODUCAO, CATATAU, SENTINELA, ALTERNATIVO). Só **depois** do merge em `producao`.

No orquestrador **CHATSPX-PRODUCAO (192.168.8.229)**:

```bash
cd /home/chatwoot/chatwoot
./deployment/deploy.sh producao
```

O script, por VM: `git checkout producao && git pull` → `bundle install` → `pnpm install` → `assets:precompile` → `db:migrate` → `systemctl restart chatwoot.target`.

### Verificação
- Cada VM deve terminar em **"Atualizado com sucesso"** (ou "Já está no último commit").
- Linha final: **"Resultado: N/N OK"**. Se algo aparecer em "Falharam:", rever aquela VM.
- ⚠️ O deploy puxa **todo o `producao`** — se houver outros commits não-liberados ali, vão junto. Confirme que o estado de `producao` é o desejado em produção.
- **Smoke test** em 1–2 VMs (hard refresh / Ctrl+Shift+R):
  - Admin sem time abre **Não Lidas** → lista **todas** as não-lidas da conta.
  - Clicar **Minhas / Não atribuídas / Todos** → a URL muda para `?assignee_type=me|unassigned|all` e a aba destacada acompanha; sem crash.
  - Clicar numa conversa → abre em `/unread/conversations/:id` e fica **selecionada**; back-button volta à lista unread.

### Rollback
```bash
# numa máquina com escrita (reverte os 4 commits, do mais novo p/ o mais antigo):
git checkout producao
git revert --no-edit adef78236 2df2763ce ab8071468 fbd6f1acc
git push origin producao
# depois, no orquestrador:
./deployment/deploy.sh producao
```
> Os hashes acima são da `nicolas`. Após o `git am` no Passo A os commits em `producao` terão **hashes novos** — use os que aparecerem no `git log` de `producao` (mesmas mensagens) para reverter.

---

## Checklist
- [ ] Passo A: patch aplicado, branch pushada, PR mergeado em `producao`
- [ ] Passo B: `deploy.sh producao` rodado no 192.168.8.229 → N/N OK
- [ ] Smoke test pós-deploy (admin vê todas em ≥1 VM da frota)
- [ ] Tokens de PAT colados no chat **revogados**
