# ADR 0001 — Team Message Isolation: Association Lambda vs Pundit Policy

**Data:** 2026-05-05
**Status:** Implementado (curto prazo) — revisar em sprint W+1
**Autor:** Orion (aiox-master) + Ederson (Simplex)
**Branch:** producao

---

## Contexto

O Chatwoot tem um setting por inbox chamado `team_message_isolation` (boolean, default `false`) que controla se mensagens de uma conversa devem ser visíveis apenas para membros do team atual da conversa.

Antes deste ADR, o setting era respeitado **apenas no frontend** (`Message.vue:isRestrictedByTeam`, `useTeamIsolation.js`), que esconde mensagens via `🔒` para usuários não-members. O backend `Conversation#messages` (`app/models/conversation.rb:114`) tinha um lambda que **sempre** filtrava por `team_id` quando a conv tinha team setado, independente do flag do inbox.

### Bug observado em produção (2026-05-05)

Conversa `account 6 / display 874` (pk 12770) reportada "sem histórico". Investigação revelou:

- 195 mensagens no DB, todas com `team_id` setado (zero NULL)
- Hoje a conv foi reatribuída 4× em 10min: team 33 → 31 → 33 → 33 → 31 (final)
- Mensagens criadas antes da reatribuição final ficaram com `team_id=33` (antigas) ou `team_id=31` (novas)
- `MessageFinder` usa `@conversation.messages` que aplicava o lambda → retornou apenas 2 mensagens (as do team_id atual=31), ocultando 193
- Inbox 61 (`[Tozi] Financeiro`) tem `team_message_isolation = false`

Logo: usuário admin desabilitou a flag esperando ver tudo, mas o backend bloqueou silenciosamente porque o lambda ignorava o setting.

### Causa secundária

`Conversations::UpdateMessagesTeamIdJob` é enfileirado em `saved_change_to_team_id?` para sincronizar `team_id` das mensagens. Em rajadas de reatribuição, vários jobs foram enfileirados com team_ids diferentes; a ordem de execução não é garantida → o último job executado podia sobrescrever com um team_id já obsoleto.

---

## Decisão

### Curto prazo (implementado)

1. **`Conversation#messages` lambda passa a respeitar `inbox.team_message_isolation`**
   - Quando `false` → retorna `all` (sem filtro)
   - Quando `true` → mantém comportamento atual (filtra por team_id)
   - Arquivo: `app/models/conversation.rb:114-126`

2. **`UpdateMessagesTeamIdJob` lê `team_id` no momento da execução** (não do argument)
   - `perform(conversation_id, _legacy_team_id = nil)` — segundo arg mantido para backward-compat com jobs já na fila
   - Garante que o último write vence, independente da ordem de execução
   - Arquivo: `app/jobs/conversations/update_messages_team_id_job.rb`

3. **Rake task de saneamento** `messages:resync_team_id[account_id]`
   - Encontra conversas com `m.team_id IS DISTINCT FROM c.team_id` e enfileira o job idempotente
   - Modo `inline` para batches pequenos (sem Sidekiq)
   - Arquivo: `lib/tasks/messages_resync_team_id.rake`

### Longo prazo (a avaliar — sprint W+1)

Mover a lógica de team isolation **da association** para uma **Pundit policy** (`MessagePolicy`) ou um scope explícito (`Message.visible_to_team(team_ids)`). Razões:

- Association lambda quebra contratos: serializadores, relatórios, jobs, callbacks que usam `conv.messages` veem dados diferentes do que esperariam
- Lambda em association é difícil de descobrir / debugar (não aparece em queries SQL óbvias)
- Pundit é o padrão do projeto para autorização (ver `ConversationPolicy`)

A migração para policy precisa cuidar de:
- `MessageFinder` (controller-facing)
- Serializadores de Conversation que incluem messages
- Webhook payloads
- Jobs que iteram messages
- Activity messages (sempre visíveis, regra atual)

---

## Alternativas consideradas

### Alternativa A — Backfill imediato + manter lambda
Sincronizar todos os team_ids stale via UPDATE em massa, sem mexer no lambda. Pros: zero mudança de comportamento. Contras: bug se manifestaria de novo na próxima reatribuição com falha de job; admin que desabilita flag continuaria sem ver tudo.

### Alternativa B (escolhida) — Lambda condicional + job idempotente + saneamento
Pros: alinha backend com setting, previne novos drifts via job resilient, sana drifts antigos. Contras: muda comportamento de `conv.messages` para inboxes com isolation OFF (que é o desejado).

### Alternativa C — Migrar para Pundit policy
Pros: arquitetura mais limpa. Contras: refactor grande, risco alto, fora do escopo do hotfix.

---

## Consequências

### Positivas

- Inboxes com `team_message_isolation = false` (default; maioria) passam a mostrar histórico completo, alinhado com a UI
- Reatribuições em rajada não geram mais drift de team_id
- Saneamento dos drifts existentes via rake task

### Negativas / a observar

- Inboxes com `team_message_isolation = true` (raros) continuam com o lambda — qualquer drift residual continua escondendo histórico até `UpdateMessagesTeamIdJob` rodar
- Carga adicional no banco quando `conv.messages` é chamado em inboxes com isolation OFF (filtro a menos = mais rows; mas é o comportamento esperado)
- `inbox.team_message_isolation` agora é um lookup adicional na association lambda — em loops grandes pode causar N+1. Mitigação: usar `.includes(:inbox)` quando iterar conversations.

### Métricas pós-deploy

- Reabrir conv 12770 em produção → ver 195 mensagens
- `journalctl -u chatwoot-worker.1 | grep UpdateMessagesTeamIdJob` — observar execuções pós-saneamento
- Rake task na account 6: `RAILS_ENV=production rake messages:resync_team_id[6]` → ver contagem de convs corrigidas

---

## Referências

- Plano original: `docs/plano-correcao-bugs-mensagens-2026-05-05.md`
- Commit que introduziu o lambda atual: `2844c21c0 fix(messages): tratar team_id NULL como publica no scope de visibilidade`
- Investigação completa: conversa de orquestração com Orion (aiox-master), 2026-05-05 19:00–21:00 UTC
