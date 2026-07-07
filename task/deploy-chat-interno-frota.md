# Runbook — Promover o Chat Interno para a frota/produção

> Preparado em 2026-07-06 a partir da auditoria de risco (4 frentes: migrations, escopo/flags, backfill/runtime, tempo-real/performance).
> Execução prevista: **amanhã, em conjunto.** Produção = `chat.simplexsolucoes.com.br`. Deploy roda do **orquestrador 192.168.8.229 via deploy.sh** (host `nicolas` é pull-only, não deploya).
> Regra de ouro: nada é testado em produção; validamos no staging antes. Ações reversíveis/read-only por padrão.

---

## FASE 0 — Endurecimento de código (fazer ANTES do deploy; idealmente commitar hoje/amanhã cedo)
Sem isso, o rollout do chat interno é acidental e o gating é só cosmético. São 4 mudanças pequenas na branch `nicolas`:

- [ ] **0.1 — Dar à `internal_chat` um BIT PRÓPRIO novo** (append no fim de `config/features.yml`), em vez de reciclar o slot da `message_reply_to`.
  - Motivo: hoje as duas dividem o bit 30 (`1<<29`) → toda conta com `message_reply_to` ligado acende o chat sozinha.
  - Cuidado: `config/features.yml` já tem ~65 flags e o bitmask bigint só cobre 63. **NÃO** dá pra simplesmente appendar sem antes recuperar um slot deprecado de bit baixo (ver [[feature-flags-bigint-limit]]). Decisão a tomar juntos: qual slot deprecado reaproveitar, ou aceitar o bit atual e apenas **limpar o bit das contas afetadas** (ver 1.2).
  - ⚠️ Se mudarmos o bit, contas do STAGING que já têm o chat ligado precisam ser religadas no bit novo.
- [ ] **0.2 — Enforçar a flag na ROTA**: fazer o guard global consumir `meta.featureFlag` (hoje só valida `meta.permissions`). Arquivo: `app/javascript/dashboard/helper/routeHelpers.js` + `routes.js` do internalChat.
- [ ] **0.3 — Enforçar a flag no BACKEND**: `before_action` que barra (404) se `Current.account.feature_enabled?('internal_chat')` for false, no controller base do chat interno (`internal_channels_controller.rb` e `internal_messages_controller.rb`).
- [ ] **0.4 — Rake task de backfill idempotente** dos grupos de time (hoje só existe o service, sem task): `lib/tasks/internal_chat.rake` → `internal_chat:backfill_team_channels` que roda `SyncTeamChannelsService` por conta (ou por `ACCOUNT_ID=`).
- [ ] **0.5 — (Opcional, recomendado antes de canais grandes) performance:**
  - [ ] Debounce/throttle do `markRead` no cliente (hoje dispara por mensagem → tempestade O(viewers×membros)). `internalChat.js:301-304`.
  - [ ] Rotear broadcasts internos p/ fila própria (ex.: `:internal_chat`/`:low`) em vez de `:critical` (não competir com eventos de conversa de clientes).
  - [ ] `includes(members: { user: { avatar_attachment: :blob } })` na listagem (mata N+1 de avatar). Idem nas mensagens.
  - [ ] Paginar o modo auditoria admin (`?scope=all`).
  - [ ] Índice `GIN (content) gin_trgm_ops` em `internal_messages` (busca ILIKE).

- [ ] **0.6 — Validar 0.1–0.4 no staging**: build (`assets:precompile`, heap 8GB) + `sudo /bin/systemctl restart chatwoot.target`; conferir que com flag OFF a URL direta dá 404 e o menu some; com flag ON funciona. Commitar tudo.

> Se preferir, dá pra **eu deixar a Fase 0 pronta e commitada hoje/amanhã cedo** — aí amanhã começamos direto na Fase 1.

---

## FASE 1 — Pré-checagens em PRODUÇÃO (read-only, com código ANTIGO ainda no ar)
- [ ] **1.1 — Backup do banco de produção** (antes de qualquer migrate).
- [ ] **1.2 — Pré-checar o bit reclamado** (risco nº1). Rodar no banco de produção:
  ```sql
  SELECT id, name FROM accounts WHERE (feature_flags & (1::bigint << 29)) <> 0;
  ```
  - Se **vazio** → seguro, ninguém acende o chat sozinho.
  - Se **retornar contas** → decidir: (a) limpar o bit dessas contas antes de subir, ou (b) se fizemos a Fase 0.1 (bit novo), o problema some sozinho. Registrar quais contas.
  - ⚠️ Nessas contas os **admins poderiam ler as DMs entre agentes** (auditoria by-design) — por isso não pode acender sem querer.
- [ ] **1.3 — Pré-checar outras reclamações de bit** do runbook geral (§3.1 de `task/runbook-deploy-producao.md`): `response_bot→message_sequences`, `report_v4→ai_assistant_v2`, `mobile_v2→report_rollup`. (Só relevante se esses trabalhos forem no mesmo deploy.)
- [ ] **1.4 — Conferir `db:migrate:status`** nos bancos-alvo: garantir que as 8 migrations do chat interno estão `down` (nunca foram aplicadas por fora). Se algum banco já tiver as tabelas `internal_*`, as migrations 1–7 (não-idempotentes) estouram "already exists" — tratar antes.

---

## FASE 2 — Deploy (do orquestrador 192.168.8.229 via deploy.sh)
- [ ] **2.1 — Pull da branch `nicolas`.**
- [ ] **2.2 — `db:migrate`** — as 8 migrations do chat interno são **aditivas e seguras** (tabelas nascem vazias). Único ponto: a migration `20260626140000` cria FK `internal_messages → conversations` (lock breve em `conversations`). **Rodar em janela de baixa escrita.**
- [ ] **2.3 — `assets:precompile`** com `NODE_OPTIONS=--max-old-space-size=8192` (evita OOM).
- [ ] **2.4 — Confirmar assets de som** no servidor: `public/audio/internal_chat/` (pop.wav, tritone.wav, dingdong.wav, marimba.wav, soft.wav, chime.mp3) — versionados no git, só garantir que o deploy não filtra `public/audio`.
- [ ] **2.5 — Restart web + sidekiq** (`chatwoot.target`). Não há cron/listener novo do chat interno — restart padrão basta.

---

## FASE 3 — Habilitar e backfill (por conta — rollout controlado)
- [ ] **3.1 — Habilitar a flag `internal_chat` na(s) conta(s)-piloto** (default é OFF). Começar por 1 conta piloto, não a frota inteira.
- [ ] **3.2 — Backfill dos grupos de time** para as contas onde ligamos (idempotente):
  ```bash
  # via rake (se fizemos 0.4):
  bundle exec rails internal_chat:backfill_team_channels ACCOUNT_ID=<id>
  # ou direto:
  bundle exec rails runner "InternalChannels::SyncTeamChannelsService.new(account: Account.find(<id>)).perform"
  ```
  - Fora do horário de pico (INSERTs 1-a-1). Sem isso, as contas ligadas ficam **sem grupos de time** até um rename/mudança de membro.

---

## FASE 4 — Smoke test em produção (na conta-piloto)
- [ ] **4.1** Menu "Chat interno" aparece p/ quem tem a flag; **não** aparece p/ conta sem a flag.
- [ ] **4.2** Com flag OFF numa conta de controle: URL direta `/accounts/:id/internal-chat` dá 404 (valida Fase 0.2/0.3).
- [ ] **4.3** DM entre 2 agentes: mensagem chega em **tempo real** ao destinatário (sem reload) + som toca.
- [ ] **4.4** Grupo de time aparece e recebe mensagem; @menção notifica.
- [ ] **4.5** Badge de não-lidas atualiza; limite de anexo respeitado.
- [ ] **4.6** Admin em auditoria (`Ver todos`): vê canais somente-leitura, não consegue postar em canal que não participa.

---

## FASE 5 — Rollback (se algo der errado)
- [ ] **5.1** Desligar a flag `internal_chat` nas contas ligadas → recurso some (front) — mitigação imediata.
- [ ] **5.2** Se necessário reverter código: as migrations são reversíveis (aditivas); mas como o recurso é inerte sem a flag, geralmente basta desligar a flag e re-deployar o commit anterior. Restaurar backup só em último caso.

---

## Resumo dos riscos (referência rápida)
| Sev | Item | Onde | Mitigação nesta lista |
|-----|------|------|-----------------------|
| 🔴 | Bit `message_reply_to`→`internal_chat` acende o chat sozinho | `features.yml:110` | 0.1 + 1.2 |
| 🔴 | Flag não enforçada em rota/backend (só esconde menu) | `routeHelpers.js`, controllers | 0.2 + 0.3 |
| 🟠 | Backfill de grupos de time não é automático | `sync_team_channels_service.rb` | 0.4 + 3.2 |
| 🟡 | `markRead` por mensagem → tempestade de broadcast | `internalChat.js:301` | 0.5 |
| 🟡 | Broadcasts na fila `:critical` competem c/ conversas | `action_cable_broadcast_job.rb` | 0.5 |
| 🟡 | N+1 avatar / auditoria sem paginação / busca sem índice | jbuilder, controller, schema | 0.5 |
| ✅ | Migrations aditivas, escopo por conta, 100MB backend, echo_id, account_id no broadcast | — | já sólido |
