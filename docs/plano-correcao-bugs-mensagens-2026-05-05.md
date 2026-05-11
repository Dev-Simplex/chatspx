# Plano de Correção — Bugs Mensagens (Tozi / Simplex SaaS)

**Data:** 2026-05-05
**Orquestrador:** Orion (aiox-master)
**Origem:** Reports clientes (Emily Santos / Tozi Imóveis, Leo Tozi) — conversas account 3 #1011 e #1177
**Branch atual:** `producao` (HEAD `2844c21c0`)
**Status:** Auditoria concluída. **Nada implementado ainda.** Aguarda aprovação para execução.

---

## 1. Sumário Executivo

| # | Bug | Severidade | Confiança causa | Fix dificuldade | Squad principal |
|---|---|---|---|---|---|
| 1 | Mensagens "sumindo" — refresh não traz | **Crítica** | Alta | Trivial (1 linha) | @dev → @qa |
| 2 | "Não foi possível atualizar a mensagem" (edit) | Alta | Alta | Média (decisão arq.) | @architect → @dev → @qa |
| 3 | Mensagens fora de ordem / duplicadas | Média | Média | Requer instrumentação | @dev → @qa |

**Recomendação de release:**
- **Hotfix imediato (hoje):** Bug 1 + quick-win do Bug 2 (toast amigável). Mudança total < 30 LOC.
- **Próximo deploy (24-48h):** Fix arquitetural Bug 2 (backfill de `source_id`).
- **Sprint seguinte:** Instrumentação + correção definitiva Bug 3.

---

## 2. Base de Conhecimento

### 🔴 Bug 1 — Mensagens "sumindo" (Crítico)

**Sintoma reportado:**
- Leo Tozi (account 6, conv 1177, 16:46): *"de novo / a msg está sumindo / não, continua da mesma forma"* — mesmo após F5
- Print mostra painel de chat completamente vazio com apenas 1 linha de atribuição visível

**Causa raiz:**
A flag de estado `chat.hasNewerMessages` é setada como `true` quando o usuário rola a janela de scroll para cima além do tamanho da janela de mensagens (500 mensagens). A flag fica grudada porque `setActiveChat` **não a limpa** ao re-abrir a conversa. Quando a flag está `true`, **TODAS** as mensagens novas que chegam via WebSocket são silenciosamente descartadas (apenas `pendingNewMessageCount` é incrementado).

**Sequência do bug:**
```
1. Conv com 1.654 msgs → user scroll-up
2. fetchPreviousMessages → SET_PREVIOUS_CONVERSATIONS → trimNewest()
3. Array > 500 → chat.hasNewerMessages = true   ← flag setada
4. User troca de conversa
5. User volta para a mesma conversa
6. setActiveChat → CLEAR_ALL_MESSAGES_LOADED apenas (flag NÃO é limpa)
7. WS chega "message.created" → addMessage → ADD_MESSAGE mutation
8. else if (chat.hasNewerMessages) { ... NUNCA push ... }
9. Cliente: "msg sumiu"
```

**Por que F5 não resolve:** O `setActiveChat` é chamado novamente após reload, mas continua sem limpar a flag. Em conversas grandes, o ciclo trim-and-stick recomeça.

**Arquivos:**
- `app/javascript/dashboard/store/modules/conversations/index.js:60-65` (trimNewest seta a flag)
- `app/javascript/dashboard/store/modules/conversations/index.js:284-309` (ADD_MESSAGE suprime a mensagem)
- `app/javascript/dashboard/store/modules/conversations/actions.js:290-306` (setActiveChat — falta `CLEAR_NEWER_MESSAGES_FLAG`)
- `app/javascript/dashboard/store/mutation-types.js` — types `CLEAR_NEWER_MESSAGES_FLAG`, `SET_ALL_NEWER_MESSAGES_LOADED`

**Commit que introduziu:** `6d26c7043 fix(messages): implementar sliding window para scroll ilimitado de histórico` (09-abr-2026).

---

### 🟠 Bug 2 — Edit de mensagem timeout (`Não foi possível atualizar a mensagem`)

**Sintoma reportado:**
- Emily Santos (Tozi, conv 1011 do Simplex, 16:11): print mostra toast cinza superior *"Não foi possível atualizar a mensagem. Tente novamente"*

**Causa raiz:**
`Messages::UpdateContentService` precisa do `source_id` (ID da mensagem na WAHA) para chamar o endpoint de edit. Quando o `source_id` está vazio (que é a regra para mensagens enviadas pelo Chatwoot — ver investigação abaixo), faz-se um lookup síncrono em `WAHA /api/{session}/chats/{chat_id}/messages?limit=100`. Para chats do tipo `@lid` (grupos/comunidades novos do WhatsApp), esse endpoint do WAHA leva mais de 15 segundos. O `Rack::Timeout` mata o request em exatamente 15.000 ms → 500 → frontend mostra toast genérico.

**Evidência logs (5 ocorrências hoje, todas com mesmo padrão):**
```
mai 05 20:09:55 [50ffdabc] Started PATCH /api/v1/accounts/6/conversations/3726/messages/1221914
mai 05 20:09:55 [UpdateContentService] Looking up WAHA message for message_id=1221914, chat_id=93119387287639@lid, session=Tozi_prestacao
mai 05 20:10:10 source=rack-timeout state=timed_out
mai 05 20:10:10 Completed 500 Internal Server Error in 14995ms
mai 05 20:10:10 Rack::Timeout::RequestTimeoutException (Request ran for longer than 15000ms)
  app/services/waha/api_service.rb:157  request
  app/services/messages/update_content_service.rb:56  find_waha_message_id_from_api
```

**Investigação `source_id` (por que ele está sempre vazio):**
- Mensagens outgoing seguem o fluxo: `Messages::MessageBuilder` (cria com `source_id: nil`) → `SendReplyJob` → `WebhookListener#deliver_api_inbox_webhooks` → `WebhookJob` posta payload pro WAHA
- WAHA **não retorna** o ID da WhatsApp message no response síncrono pro Chatwoot
- O backfill é feito tardiamente em `Waha::MessageStatusSyncService#backfill_source_id` (job periódico)
- **Não existe** listener realtime que capture `message.any` / `message.ack` do WAHA pra setar `source_id` imediatamente
- Conclusão: **toda primeira edição** de mensagem nova passa pelo lookup lento

**Arquivos:**
- `app/services/messages/update_content_service.rb:46-50` (skip lookup se source_id presente)
- `app/services/waha/api_service.rb:13` (`@timeout = 10`)
- `app/services/waha/api_service.rb:131-166` (request, rescue só captura `Net::ReadTimeout`/`OpenTimeout` → `Waha::ApiService::Error`)
- `app/services/waha/message_status_sync_service.rb:53-54` (já tem `backfill_source_id`)
- `app/jobs/waha/message_status_sync_job.rb` (existe, não está sendo enfileirado eagerly)
- `app/controllers/api/v1/accounts/conversations/messages_controller.rb:34` (rescue só pega `ActiveRecord::*` e `ArgumentError` — `Rack::Timeout` vaza como 500)

---

### 🟡 Bug 3 — Mensagens fora de ordem / duplicadas (Média)

**Sintoma reportado:**
- Emily Santos (16:08): *"As mensagens estão bugando e ficam fora das ordens ou repetem as mensagens duas vezes / Está de baixo para cima / Quando atualizar a página ai volta o normal"*

**Causa provável (confiança média — precisa instrumentação para confirmação 100%):**
- Backend (`MessageFinder`) sempre retorna ASC — verificado linha por linha
- `MessageList.vue` renderiza em ordem natural — sem `sort/reverse/column-reverse`
- **`SET_PREVIOUS_CONVERSATIONS` faz `unshift(...data)` sem deduplicar** (`index.js:112-119`)
- `filterDuplicateSourceMessages` (`conversationHelper.js:24`) deduplica por `source_id`, mas mensagens otimistas (sem `source_id` ainda) escapam
- Race possível: WS chega para mensagem que `fetchPreviousMessages` também trouxe → duplicada
- Múltiplos WS para a mesma mensagem (status sync re-emite) podem inverter ordem visual em surto de tráfego

**Por que refresh resolve:** Re-fetch traz array limpo do `MessageFinder` (ASC, sem duplicatas).

**O caso "todo de baixo para cima"** ainda não tem explicação 100% sólida — pode ser efeito visual de várias mensagens recebidas em ordem inversa via WS num burst, ou estado intermediário durante uma re-renderização. **Recomendado coletar print do Vue DevTools (`currentChat.messages`) na próxima ocorrência** antes de implementar fix.

**Arquivos:**
- `app/javascript/dashboard/store/modules/conversations/index.js:112-127` (mutations sem dedupe)
- `app/javascript/dashboard/helper/conversationHelper.js:24-32` (filtro só pega source_id)
- `app/javascript/dashboard/store/modules/conversations/actions.js:430-440` (addMessage)

---

## 3. Plano de Correção — Squad Allocation

### 🚀 Sprint Hotfix (hoje — < 1 hora total)

#### Task 1.1 — Bug 1: Limpar `hasNewerMessages` em `setActiveChat`
**Squad:** @dev (Dex)
**Estimate:** 5 min código + 10 min spec
**Dificuldade:** Trivial

**Mudança proposta** (`actions.js:290-306`):
```js
async setActiveChat({ commit, dispatch }, { data, after }) {
  commit(types.SET_CURRENT_CHAT_WINDOW, data);
  commit(types.CLEAR_ALL_MESSAGES_LOADED, data.id);
  commit(types.CLEAR_NEWER_MESSAGES_FLAG, data.id);   // ← NOVO
  if (data.dataFetched === undefined) { ... }
}
```

**Critérios de aceite:**
- [ ] Spec Vitest: ao chamar `setActiveChat`, `chat.hasNewerMessages` é resetado para `false`
- [ ] Manualmente: abrir conv > 500 msgs, scroll até topo, trocar de conv, voltar, enviar msg de outro device → msg aparece imediatamente
- [ ] @qa valida em homologação com conv real do Tozi (account 6, restaurada via dump)

**Risco:** Baixíssimo. A flag é um reset; pior caso, o botão "Novas mensagens" some quando não devia. Reversível.

---

#### Task 1.2 — Bug 2 (Quick Win): Toast amigável + reduzir limit
**Squad:** @dev (Dex)
**Estimate:** 15 min código + 15 min spec
**Dificuldade:** Trivial

**Mudanças propostas:**
1. `messages_controller.rb:34` — adicionar `Rack::Timeout::RequestTimeoutException` no rescue, retornando 422 com mensagem amigável traduzível (`errors.messages.update.timeout`)
2. `update_content_service.rb:56` — reduzir `limit: 100` → `limit: 20`
3. `waha/api_service.rb:13` — reduzir `@timeout = 10` → `@timeout = 8` (para Net::ReadTimeout disparar antes de Rack::Timeout)
4. Adicionar tradução em `config/locales/pt_BR.yml` e `en.yml`:
   ```yaml
   messages:
     update:
       timeout: 'WhatsApp demorou para responder. Tente novamente em alguns segundos.'
   ```

**Critérios de aceite:**
- [ ] Spec request: simular `Rack::Timeout` → retorna 422 com mensagem em pt-BR/en
- [ ] Spec service: `limit: 20` é passado para WAHA
- [ ] Manualmente: reproduzir cenário lento → toast diz "WhatsApp demorou..."

**Risco:** Médio-baixo. Reduzir limit de 100→20 pode deixar de achar mensagens muito antigas — mas o `EDIT_WINDOW_SECONDS = 900` (15 min) já filtra por janela, raramente mais de 20 candidatos relevantes.

---

### 📦 Sprint Próximo Deploy (24–48h)

#### Task 2.1 — Bug 2 (Fix arquitetural): Backfill realtime de `source_id`
**Squad:** @architect (Aria) → @dev (Dex) → @qa (Quinn)
**Estimate:** 1–2 dias de dev
**Dificuldade:** Média

**Decisão arquitetural (Aria):**
Reusar `Waha::MessageStatusSyncService#backfill_source_id` que já existe. Trigger eager:
- **Opção A (recomendada):** Enfileirar `Waha::MessageStatusSyncJob` 5–10 segundos após `SendReplyJob` completar com sucesso, escopado pelo `conversation_id` do batch recente
- **Opção B:** Adicionar listener no webhook WAHA quando chega `message.any` com `fromMe=true` que casa com source_id ainda nulo numa janela recente

A escolha depende de:
- Frequência do `MessageStatusSyncJob` periódico já existente (verificar com @architect)
- Se há webhook `message.any` configurado no WAHA → preferir B (sem polling)

**Implementação (Dex):**
- Adicionar `Waha::MessageStatusSyncJob.set(wait: 10.seconds).perform_later(conversation.id)` no callback de sucesso do `SendReplyJob` para inboxes WAHA
- Idempotência: `backfill_source_id` deve ser no-op se `source_id` já presente
- Métrica: log `[MessageStatusSync] Backfilled #{n} source_ids in #{ms}ms`

**Critérios de aceite (Quinn):**
- [ ] Spec: após enviar mensagem WAHA, em < 15s o `source_id` está populado no DB
- [ ] Spec: edit de mensagem que tem source_id pula o lookup (não chama `Waha::ApiService#get_messages`)
- [ ] Manual em homologação: enviar msg, esperar 15s, editar → < 1s de latência
- [ ] Métrica: zero `Rack::Timeout` no endpoint `PATCH /messages/:id` durante 24h em produção

**Risco:** Médio. Adiciona load no Sidekiq; mitigado por idempotência e dedupe por conversation_id.

**Rollback:** Remover o `perform_later` adicional. O job continua existindo via schedule periódico.

---

### 🔬 Sprint Seguinte (próxima semana)

#### Task 3.1 — Bug 3: Instrumentação + dedupe defensivo
**Squad:** @dev (Dex) → @qa (Quinn)
**Estimate:** 4–6 horas
**Dificuldade:** Média

**Plano de coleta antes do fix:**
1. Adicionar log/sentry breadcrumb sempre que `addMessage` mutation é chamada com mensagem cujo ID já existe no array (=duplicata)
2. Adicionar log quando ordem do `chat.messages` ficar inconsistente (e.g. `messages[i].created_at > messages[i+1].created_at`)
3. Coletar 1 semana de dados antes de finalizar fix

**Fix preventivo (já pode ir junto com instrumentação):**
- `SET_PREVIOUS_CONVERSATIONS` e `SET_NEXT_CONVERSATIONS` — deduplicar por `id` antes de unshift/push
- `addMessage` — verificar se mensagem com mesmo ID já existe; se sim, atualizar in-place ao invés de push
- Após qualquer mutation que modifica `chat.messages`, garantir ordenação ASC por `created_at`

**Critérios de aceite (Quinn):**
- [ ] Spec: chamar `SET_PREVIOUS_CONVERSATIONS` 2x com mesmo payload → array tem N mensagens, não 2N
- [ ] Spec: `addMessage` com ID existente → conta de mensagens permanece igual
- [ ] Spec: receber mensagens fora de ordem timestamp via WS → ordem final ASC
- [ ] Manual: simular burst de mensagens → ordem visual sempre correta

**Risco:** Médio. Sort após cada mutation tem custo O(n log n). Mitigar fazendo binary insertion no lugar correto se ordem normal preservada.

---

## 4. Sequenciamento e Dependências

```
HOJE (Sprint Hotfix):
  ├─ Task 1.1 (Bug 1) ─┐
  └─ Task 1.2 (Bug 2 quick-win) ─┤
                                 ├─→ Build assets + restart
                                 ├─→ Smoke test em homologação
                                 └─→ Deploy producao
                                       └─→ @qa monitora 2h

D+1 / D+2 (Sprint Próximo):
  Task 2.1 (Bug 2 arquitetural)
       ├─ @architect: documentar decisão A vs B
       ├─ @dev: implementar
       ├─ @qa: validar em homologação 24h
       └─ Deploy producao

Próxima semana:
  Task 3.1 (Bug 3)
       ├─ Instrumentação primeiro (1 dia em prod coletando)
       ├─ Análise de dados (Aria + Dex)
       ├─ Fix definitivo
       └─ Deploy
```

---

## 5. Checklist Pós-Implementação (CLAUDE.md)

Para cada task:

- [ ] `bundle exec rspec` passando nos specs afetados
- [ ] `pnpm eslint` sem erros
- [ ] `bundle exec rubocop -a` sem offenses
- [ ] Verificou `enterprise/` para arquivos relacionados (provável: `enterprise/app/views/api/v1/conversations/partials/_conversation.json.jbuilder`)
- [ ] Apenas `en.yml`/`en.json` editados (outras línguas = comunidade) — exceção: `pt_BR.yml` é mantido pela Simplex no fork
- [ ] CLAUDE.md atualizado se descobriu novo pitfall (ex: "lembrar de limpar flags `hasNewerMessages` ao trocar de chat")
- [ ] **Validar migration pendente antes de restart em produção** (regra do vault `01-Permanentes/Incidente - Pending Migration 24-abr-2026.md`)

---

## 6. Telemetria de Validação Pós-Deploy

**Métricas-chave a observar (24h após deploy):**

1. Bug 1 (msg sumindo):
   - Reports do canal de suporte (account 3) com palavras-chave "sumindo|sumiu|não aparece" — deve cair a zero
   - Reabrir conversas reportadas (1011, 1177) e confirmar fluxo

2. Bug 2 (edit timeout):
   - `journalctl -u chatwoot-web.1 --since "today" | grep -c "Rack::Timeout.*update_content_service"` — deve cair a zero
   - Latência p99 do endpoint `PATCH /messages/:id` deve cair de >15s para < 1s

3. Bug 3 (ordem/dup):
   - Contador de duplicatas detectadas pela instrumentação
   - Reports do canal de suporte com "fora de ordem|duplicada|repetida"

---

## 7. Riscos e Rollback

| Task | Risco | Mitigação | Rollback |
|---|---|---|---|
| 1.1 | UX: botão "Novas mensagens" some prematuramente | Spec cobrindo cenário | `git revert` da linha adicionada |
| 1.2 | `limit: 20` perder mensagens antigas válidas | `EDIT_WINDOW_SECONDS=900` já filtra; logs avisam quando candidatos < `messages.size` | `git revert` |
| 2.1 | Sidekiq sobrecarregado | `perform_later` com dedupe; observar throughput | Remover linha de enqueue eager |
| 3.1 | Sort O(n log n) em arrays grandes | Usar binary insert; benchmark com 500 msgs | `git revert` mutation |

---

## 8. Apêndices

### A. Evidências brutas

**Conversa Emily Santos (account 3, conv 1011):**
- Msg 1221928 (16:08): print "fora de ordem"
- Msg 1221948 (16:09): print "depois do refresh, normal"
- Msg 1221965 (16:11): print do toast "Não foi possível atualizar"

**Conversa Leo Tozi (account 3, conv 1177):**
- Msg 1222506 (16:46): print da conversa empty na visão de agente

**Logs Rack::Timeout (5 ocorrências hoje):**
- request_id `50ffdabc-0edf-43d6-ab11-419441ef8395` (20:09)
- request_id `be1bf944-ca2d-4f84-a1b7-282028f2ecfb` (20:10)
- request_id `66617bac-db9f-4ad1-bccf-dca3accba64a` (20:42)
- request_id `eca2264e-17db-4a28-91b7-4b442caf1988` (20:47)

### B. Reports anteriores (auditoria secundária)

| Data | Cliente | Sintoma | Status |
|---|---|---|---|
| 23-abr | Emily | Looping infinito + "nem carregando vai" | Mitigado parcial pelo commit `453d352be` (limita serialização a 100 msgs) |
| 27-abr | Emily | Conversa desatribuindo sozinha | Comportamento esperado de team workflow ao reabrir conv "fechada" |
| 27-abr | Emily | Nome `@lid` em encaminhadas | Endereçado pelo commit `c02dfaa02` (`ResolveLidJob` limpa name/identifier) |
| 30-abr | Leo | Imóvel CTWA não aparece no painel | Em planejamento (`docs/plano-ctwa-referral.md`) |

### C. Referências de código

- Frontend store: `app/javascript/dashboard/store/modules/conversations/{index.js,actions.js,getters.js}`
- Frontend cable: `app/javascript/dashboard/helper/actionCable.js:113-126`
- Frontend render: `app/javascript/dashboard/components-next/message/MessageList.vue:198-241`
- Backend edit: `app/services/messages/update_content_service.rb`
- Backend WAHA client: `app/services/waha/api_service.rb`
- Backend status sync: `app/services/waha/message_status_sync_service.rb`
- Backend message finder: `app/finders/message_finder.rb`

### D. Squad mapping (AIOX)

| Agente | Responsabilidade |
|---|---|
| @architect (Aria) | Decisão A vs B na Task 2.1 |
| @dev (Dex) | Implementação 1.1, 1.2, 2.1, 3.1 |
| @qa (Quinn) | Specs + validação homologação + smoke test produção |
| @devops (Gage) | `git push`, deploy, restart de chatwoot-web.1 + chatwoot-worker.1 (após `db:migrate:status`) |
| @aiox-master (Orion) | Orquestração + handoff entre tasks |

---

**Próximo passo:** Aprovação para iniciar Task 1.1 + 1.2 (sprint hotfix). Ao confirmar, faço `*workflow story-development-cycle` puxando @dev para a primeira task.

— Orion, orquestrando o sistema 🎯
