# ADR 0002 — Invariantes de `chat.messages` (frontend)

**Data:** 2026-05-06
**Status:** Implementado
**Autor:** Orion (aiox-master) + Ederson (Simplex)
**Branch:** producao

---

## Contexto

O store Vuex `dashboard/store/modules/conversations` mantém, para cada conversa carregada em memória, um array `chat.messages`. Esse array é usado diretamente pelo `MessageList.vue` (e `components-next/message/*`) para renderizar a timeline e calcular `<DateSeparator>` entre mensagens consecutivas.

### Bug observado em produção (2026-05-06)

Conv `account 3 / 1177` (Leo Tozi). Após o deploy de `8bf795a6b` (2026-05-05), toda mensagem outgoing passou a enfileirar `Waha::MessageStatusSyncJob` 10s depois. O job sincroniza status de até 20 mensagens recentes na WAHA, e re-emite `message.updated` via ActionCable para qualquer mensagem cujo ack mudou — **incluindo mensagens de dias atrás** (status `sent` → `delivered`).

No frontend:

1. `updateMessage` action commitava `ADD_MESSAGE` para qualquer broadcast `message.updated`.
2. `findPendingMessageIndex` retornava `-1` quando a msg antiga não estava no array (trimmada pela sliding window de 500, ou nunca carregada).
3. `else` cego fazia `chat.messages.push(message)` — empurrando uma msg antiga para o **fim** do array.
4. UI renderizava a msg de 11/abril após mensagens de hoje, com `<DateSeparator>` "11 de abril" depois de "Hoje".

Hard reload resolvia até o próximo broadcast.

---

## Decisão

### Invariantes

I1. **Ordem ascendente por `created_at`.** `chat.messages` deve estar sempre ordenado em ordem cronológica ascendente. Toda mutation que insere em `chat.messages` deve preservar esta ordem.

I2. **Sem ids duplicados.** `chat.messages` não pode conter duas entradas com o mesmo `id`. Já garantido nas mutations `SET_PREVIOUS_CONVERSATIONS` e `SET_NEXT_CONVERSATIONS` (filtro via `Set` de ids); reforçado em `ADD_MESSAGE` via `findPendingMessageIndex` (replace in-place).

I3. **Mensagem visível ↔ presente no array.** Status updates (`message.updated` via ActionCable) só são aplicados a mensagens que JÁ estão no array. Mensagens fora da janela ficam fora — o user pegará estado fresco no próximo fetch.

### Implementação (curto prazo)

1. **Helper puro `insertSortedByCreatedAt(messages, message)`** em `app/javascript/dashboard/store/modules/conversations/helpers.js`
   - Faz `findIndex` da primeira msg com `created_at` maior; insere via `splice` ou `push`
   - Coerciona `created_at` (number Unix em segundos) e ISO string para comparação consistente

2. **`ADD_MESSAGE` mutation** (`index.js:305`)
   - Substitui `chat.messages.push(message)` por `insertSortedByCreatedAt(chat.messages, message)`
   - Defesa em profundidade: mesmo callers que ignorem o action ainda preservam ordem

3. **`updateMessage` action** (`actions.js:446`)
   - Skip silencioso quando a msg não existe em `state.allConversations[i].messages`
   - Evita re-injetar msg antiga no array

### Como adicionar nova mutation/action que toca em `chat.messages`

Checklist obrigatório:

- [ ] A mutation/action insere em `chat.messages`? Se sim, usar `insertSortedByCreatedAt` ou justificar (ex: payload do servidor já vem ordenado).
- [ ] Pode receber a mesma msg duas vezes? Se sim, dedupe via `findPendingMessageIndex` ou `Set` de ids antes de inserir.
- [ ] Pode receber msg fora da janela? Se sim, considerar skip (como `updateMessage`) ou marcar `pendingNewMessageCount` (como o branch `hasNewerMessages`).
- [ ] Adicionar spec em `mutations.spec.js` ou `helpers.spec.js` cobrindo o caso fora-de-ordem.

---

## Alternativas consideradas

### Alternativa A — Sort do array inteiro a cada insert
`chat.messages.push(message); chat.messages.sort(byCreatedAt)` — O(n log n) por insert. Pros: trivial. Contras: custo desnecessário no caso comum (msg nova vai para o fim).

### Alternativa B (escolhida) — Insertion ordenada O(n)
`findIndex` + `splice`. Pros: O(n) com early exit no caso comum (`-1` rápido para msg nova). Contras: array mutável (já é como o store funciona).

### Alternativa C — Source of truth no backend (sem store local)
Reload total a cada update. Pros: zero risco de drift client-side. Contras: latência alta, custo de banco, regressão de UX. Fora de escopo.

---

## Consequências

### Positivas

- Mensagens fora-de-ordem nunca mais quebram a timeline mesmo que o backend re-emita msgs antigas (defesa em profundidade)
- Updates de status para msgs fora da janela viram no-op silencioso (sem efeito visual indesejado)
- Helper reutilizável para futuras mutations que toquem `chat.messages`

### Negativas / a observar

- `findIndex` é O(n) no array — com window=500, no pior caso é 500 comparações por insert. Caso comum (msg nova): 1 comparação (primeiro item já é maior? não → push). Aceitável.
- `state` agora é dependência de `updateMessage` (junto com `commit` e `rootGetters`). Actions que delegam para `updateMessage` em testes precisam mockear `state`.

### Métricas pós-deploy

- Console do navegador: zero `[Vue warn]: Invalid prop: type check failed for prop "date"` (Bug 2 corrigido em conjunto)
- Console do navegador: zero `[Vue warn]: Failed to resolve component: VoiceCallButton` (Bug 3 corrigido em conjunto)
- Conv 1177 (Tozi): observar 30 min sem novos saltos de ordem após outgoing + status sync
- Reports do canal de suporte com palavras "fora de ordem|11 de abril|data errada": cair a zero

---

## Referências

- Plano: `docs/plano-correcao-mensagens-fora-de-ordem-2026-05-06.md`
- Commit que amplificou: `8bf795a6b fix(messages): corrigir mensagens sumindo, edit timeout e dedupe`
- Specs de regression: `app/javascript/dashboard/store/modules/conversations/specs/mutations.spec.js` (`#ADD_MESSAGE order preservation`), `helpers.spec.js` (`#insertSortedByCreatedAt`), `app/javascript/dashboard/store/modules/specs/conversations/actions.spec.js` (`#updateMessage`)
- Helper: `app/javascript/dashboard/store/modules/conversations/helpers.js:insertSortedByCreatedAt`
