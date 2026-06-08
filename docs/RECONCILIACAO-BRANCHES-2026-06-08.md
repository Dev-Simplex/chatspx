# Reconciliação de branches — `paulao` ↔ `rollout/release-20260605`

> Levantado em 2026-06-08 ao tentar deployar a frente-1 do disparo. **Plano para revisão — NÃO executado.**

## TL;DR

Prod **não** roda `paulao` nem `producao`. Roda uma branch **local-de-prod** chamada `rollout/release-20260605` (deployada 2026-06-08 01:48). Ela **não existe no origin** (só no servidor AWS). A `paulao` tem ~6 commits / 59 arquivos / **2.460 inserções que existem APENAS na máquina local** (nem no origin/paulao nem na rollout). As duas branches **divergiram com mudanças sobrepostas** nos mesmos arquivos.

🔴 **Risco de backup imediato:** trabalho crítico vive em **um lugar só** — a rollout só em prod, e os 6 commits de disparo só no notebook. Perda de qualquer um = perda de trabalho. **Primeira ação do plano = empurrar os dois pro origin.**

## Topologia (com SHAs)

### Prod: `rollout/release-20260605` (deploy 08/06 01:48, só no servidor)
Remote: `origin = github.com/Dev-Simplex/chatspx.git`. Branches locais no prod: `master`, `producao`, `rollout/release-20260605` (atual).

Commits da rollout (que `origin/producao` não tem):
```
fc0f9afdf fix(db): migration FK 20260330120000 versao SAFE (nullify + abort-and-list)   ⭐ resolve a landmine
7e652b7f8 docs(brand): manual de marca SPX em /brand/
a4a098bd9 fix(waha): eliminar F5 no realtime (inbound high, stale-refetch, watchdog)
90998eeee feat(reply-box): merge — drag-drop + foco editor + anexos em canned (Tozi)
28ca50c9f fix(routes): merge Tozi (campaigns :stats + remove migration_sso)
4cb583534 chore(git): .gitattributes eol=lf + gitignore .env.bak/STATE.md
c7405f010 feat(campaign): desativa blaster WhatsApp nativo (decisao Tozi 06-05)
20ebc5ac9 feat(spx-tozi): consolida off-git da Tozi sobre a canonica
cc4536209 Merge PR #19 from paulao
  ... + historico de paulao ate a base comum 8cd481bfd
```

### `paulao` LOCAL (6 commits NÃO no origin/paulao, NÃO na rollout)
```
11b913531 fix(disparo): reusa ficha e conversa unica do contato            <- FRENTE-1
ed1b90a54 docs(spx): STATE atualizado da operacao de disparos
cd409845a feat(conversations): filtro de conversas nao lidas
6ee421881 feat(campaigns): tela de estatisticas de disparo + blaster off
1133a6fd6 feat(canned): anexo em resposta rapida (modal e inline)
d88e51c55 feat(spx/tozi): orquestrador disparo HSM + follow-up + scripts   <- INQUILINOS/imagem
```
`origin/paulao` está em `71629abe1` (01/06) — **atrás** do local. Ou seja, todo o trabalho de disparo (orquestrador, inquilinos, frente-1, scripts) está **só no notebook**.

### Bases comuns
- `merge-base(rollout, origin/producao)` = `88da75b9d`
- `merge-base(rollout, origin/paulao)`   = `8cd481bfd`

## O que cada lado tem que o outro NÃO tem

| Recurso | rollout (prod) | paulao (local) |
|---|---|---|
| Migration landmine SAFE (`fc0f9afdf`) | ✅ | ❌ |
| Fix WAHA F5 realtime (`a4a098bd9`) | ✅ | ❌ |
| Manual de marca (`7e652b7f8`) | ✅ | ❌ |
| `.gitattributes` eol=lf (`4cb583534`) | ✅ | ❌ |
| Disparo job **com inquilinos/imagem** (`d88e51c55`) | ❌ (versão pré-inq, 124 linhas) | ✅ (178 linhas) |
| Disparo job **frente-1** (reusa ficha/conversa, `11b913531`) | ❌ | ✅ |
| Scripts de operação (`scripts/spx/tozi/*`) | ❌ | ✅ (18 scripts + consolidação) |
| Canned anexo / campaign stats / blaster off | ✅ (commits próprios de merge) | ✅ (commits originais) |

⚠️ As 3 últimas features (canned/campaign/blaster) existem nos **dois** lados via **commits diferentes** → um `git merge` direto vai **conflitar** nos arquivos compartilhados (`campaigns_controller.rb`, `ReplyBox.vue`, `config/routes.rb`, etc.).

## Plano recomendado (revisar antes de executar)

1. **BACKUP primeiro (sem isso, não mexer em nada):**
   - `git push origin paulao` (sobe os 6 commits locais) — **precisa do seu OK explícito.**
   - Do servidor de prod: `git push origin rollout/release-20260605` — sobe a branch de prod pro GitHub.
2. **Definir a canônica:** a `rollout` é a branch de prod de fato e a mais integrada (tem a migration SAFE + WAHA). Sugestão: **rollout vira a base**; trazemos pra ela só o que falta da paulao.
3. **Trazer o delta de disparo pra rollout** (o que prod não tem):
   - `app/jobs/spx/tozi/disparo_lead_job.rb` → **usar a versão da paulao inteira** (178 linhas: inquilinos + frente-1). A versão da rollout (124) é subconjunto puro (pré-inq, sem lógica única) → substituição segura.
   - `app/jobs/spx/tozi/followup_hsm_job.rb` (confirmar se rollout tem).
   - `scripts/spx/tozi/*` (inclui `consolida_conversas_duplicadas.rb`).
   - `lib/tasks/spx_tozi.rake`.
   - Validar `unread` filter (`cd409845a`) e demais — caso a caso (rollout pode já ter equivalente).
4. **Resolver conflitos** dos arquivos sobrepostos (canned/campaign/routes) **a favor da versão que já está em prod** (rollout), já que está validada no ar — exceto onde a paulao tem correção mais nova.
5. **Verificar:** `zeitwerk:check` "All is good!", `bundle exec rubocop` nos arquivos tocados, o job carrega, `send_hsm` trata os 3 tipos (2-var / no-var texto / no-var imagem).
6. **Deploy:** recompila assets + restart `chatwoot-worker.1` (+ web se assets) — **sempre** `db:migrate:status` antes (hoje = 0 down).
7. **Fechar:** push da branch reconciliada pro origin; atualizar STATE.md; decidir o fluxo de deploy daqui pra frente (a branch local-de-prod sem origin foi o que gerou a bagunça).

## Conflitos esperados (arquivos nos 2 lados)
`app/controllers/api/v1/accounts/campaigns_controller.rb`, `app/javascript/.../ReplyBox.vue`, `app/javascript/.../canned-response/*`, `config/routes.rb`, `app/models/campaign.rb`, `.claude/STATE.md`.

## Decisões abertas pro Paulo
- [ ] Autorizar `git push origin paulao` (backup dos 6 commits locais).
- [ ] Autorizar push da `rollout` de prod pro origin (backup).
- [ ] Confirmar rollout como branch canônica de release (ou migrar tudo pra `producao`).
- [ ] Definir o processo de deploy oficial (pra não recriar branch local-de-prod).
