# Plano de Correção — Mensagens fora de ordem + Vue warns

**Data:** 2026-05-06
**Orquestrador:** Orion (aiox-master)
**Origem:** Report Leo Tozi via WhatsApp Walisson, conversa account 3 / 1177 (Simplex)
**Status:** Auditoria concluída. **Nada implementado ainda.** Aguarda aprovação para execução.
**Branch:** `producao` (HEAD `d131b69e2`)

---

## 1. Sumário Executivo

| # | Bug | Severidade | Confiança | Fix dificuldade | Squad principal |
|---|---|---|---|---|---|
| 1 | Mensagens fora de ordem (datas embaralhadas após hoje 05/06 aparecer 11 abril) | **Crítica** | Alta | Trivial (+5 min preventivo) | @dev → @qa |
| 2 | Vue warn `prop "date"` em `DateSeparator` | Baixa (cosmético) | Alta | Trivial (1 linha) | @dev → @qa |
| 3 | Vue warn `Failed to resolve component: VoiceCallButton` | Baixa (cosmético) | Alta | Trivial (import esquecido) | @dev → @qa |

**Recomendação de release:**
- **Hotfix (hoje, ~15 min total):** Fix 1 (corretivo + preventivo), Fix 2, Fix 3 — em commit único.
- **Preventivo de longo prazo:** spec Vitest + sort guard helper + ADR para regra "store mutations devem preservar ordem cronológica".

---

## 2. Base de Conhecimento

### 🔴 Bug 1 — Mensagens fora de ordem (CRÍTICO)

#### Sintoma reportado

Leo Tozi (cliente Tozi Imóveis) abriu conversa `https://chat.simplexsolucoes.com.br/app/accounts/3/conversations/1177` em 06-mai-2026 e viu mensagens de hoje (`05/06`) seguidas por mensagens de **11 de abril** no scroll. Reabertura da página resolve temporariamente.

#### Cadeia causal completa

```
1. Agente envia msg outgoing pela inbox WAHA (acc 3, conv 1177)
2. SendReplyJob roda → enqueue Waha::MessageStatusSyncJob.set(wait: 10.seconds)
3. Job busca 20 mensagens recentes na WAHA API
4. WAHA retorna msgs com acks pendentes — INCLUINDO msgs de DIAS atrás (status sent → delivered)
5. Para cada msg com ack diferente do registrado, chama Messages::StatusUpdateService.perform
6. Service faz message.update!(status: 'delivered') ← mensagem de 11 de abril
7. after_update_commit dispara message.updated via ActionCable
8. Frontend recebe broadcast → updateMessage action → ADD_MESSAGE mutation
9. findPendingMessageIndex retorna -1 (msg de 11/abr não está no chat.messages —
   foi trimmada pela sliding window OU nunca carregada — user só viu últimas 20)
10. chat.hasNewerMessages é false → cai no else → chat.messages.push(message)
11. UI re-renderiza: msg de 11/abr fica APÓS as msgs de hoje 05/06 (push no fim)
12. <DateSeparator> entre elas mostra "11 de abril" depois de "Hoje"
```

#### Por que apareceu HOJE

- A **Task 2.1** (deploy 21:40 UTC ontem 05/05, commit `8bf795a6b`) introduziu `Waha::MessageStatusSyncJob.set(wait: 10.seconds).perform_later` em **toda mensagem outgoing**.
- O job sincroniza status de **20 mensagens** retornadas pela WAHA — não filtra por idade.
- Resultado: cada outgoing dispara cascata de `message.updated` em msgs antigas → frontend re-injeta no final do array.
- Antes da Task 2.1, o status sync era periódico e raro; o bug existia mas era praticamente invisível.

#### Por que F5 resolve

Hard reload re-fetcha as últimas 20 mensagens via `MessageFinder` (que retorna em `created_at ASC`). Array é resetado para ordem correta. Próximas re-emissões via WS quebram de novo.

#### Backend está íntegro (validado 06-mai)

```
=== Conv account 3 / 1177 ===
  pk_id=13952 status=open team_id=7 inbox=simplex_996571379
  total mensagens: 1665
  inversoes (id sobe, created_at desce): 0
  conv.messages.count (lambda) = all_messages = 1665
  Range cronológico: 2025-12-29 → 2026-05-06
```

#### Por que `findPendingMessageIndex` não cobre

```js
export const findPendingMessageIndex = (chat, message) => {
  const { echo_id: tempMessageId } = message;
  return chat.messages.findIndex(
    m => m.id === message.id || m.id === tempMessageId
  );
};
```

Se a msg JÁ está no array por id, substitui in-place (✅ preserva ordem). Mas se a msg foi **trimmada pela sliding window** (`MESSAGE_WINDOW_SIZE = 500`) ou nunca carregada (user só viu janela inicial de 20 mensagens), não está no array → cai no else → `push` cego.

#### Arquivos chave

- `app/javascript/dashboard/store/modules/conversations/index.js:290-309` — `ADD_MESSAGE` mutation (push cego no else)
- `app/javascript/dashboard/store/modules/conversations/actions.js:430-440` — `addMessage` action
- `app/javascript/dashboard/store/modules/conversations/actions.js:442-445` — `updateMessage` action (re-emite `ADD_MESSAGE`)
- `app/javascript/dashboard/store/modules/conversations/helpers.js:3-8` — `findPendingMessageIndex`
- `app/services/waha/message_status_sync_service.rb:34-51` — sync que dispara update! em massa
- `app/services/messages/status_update_service.rb` — chama `message.update!(status:)`
- `app/jobs/send_reply_job.rb:39-45` — schedule_waha_status_sync (Task 2.1)

#### Commit que amplificou

`8bf795a6b fix(messages): corrigir mensagens sumindo, edit timeout e dedupe` (Task 2.1: enfileirar `Waha::MessageStatusSyncJob` 10s após `SendReplyJob`).

---

### 🟡 Bug 2 — Vue warn `prop "date"` em `DateSeparator`

#### Sintoma

Console do navegador:
```
[Vue warn]: Invalid prop: type check failed for prop "date".
Expected String with value "Wed May 06 2026 07:54:51 GMT-0400 (...)", got Date
  at <DateSeparator key=0 date= Wed May 06 2026 ... >
```

#### Causa

```vue
<!-- app/javascript/dashboard/components-next/message/MessageList.vue:312-315 -->
<DateSeparator
  v-if="shouldShowDateSeparator(index, renderItems)"
  :date="new Date(getItemDate(item) * 1000)"  <!-- ← passa Date object -->
/>
```

```js
// app/javascript/shared/components/DateSeparator.vue:5-9
props: {
  date: {
    type: String,   // ← declara String
    required: true,
  },
},
```

`formatDate({ date })` em `shared/helpers/DateHelper.js:13-20` faz `new Date(date)` que aceita Date object também — então **funciona por sorte**, mas Vue protesta no console e qualquer mudança no helper que assumir String pode quebrar silenciosamente.

#### Arquivos chave

- `app/javascript/dashboard/components-next/message/MessageList.vue:314`
- `app/javascript/shared/components/DateSeparator.vue:6-7`
- `app/javascript/shared/helpers/DateHelper.js:13-20`

---

### 🟢 Bug 3 — Vue warn `VoiceCallButton` não resolvido

#### Sintoma

```
[Vue warn]: Failed to resolve component: VoiceCallButton
  at <ContactInfo contact= Object channel-type=undefined >
  at <ContactPanel ...>
  ...
```

#### Causa

`app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue` usa `<VoiceCallButton>` no template (linha 257) mas **não importa** o componente nem registra em `components: { ... }` (linha 24).

O componente existe em `app/javascript/dashboard/components-next/Contacts/VoiceCallButton.vue` e está importado corretamente em `ContactsDetailsLayout.vue:10`. Foi simplesmente esquecido em `ContactInfo.vue`.

#### Arquivos chave

- `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue` (sem import)
- `app/javascript/dashboard/components-next/Contacts/VoiceCallButton.vue` (componente existe)
- `app/javascript/dashboard/components-next/Contacts/ContactsDetailsLayout.vue:10` (referência correta)

---

## 3. Plano de Correção — Squad Allocation

### 🚀 Sprint Hotfix (hoje — 15-20 min total)

#### Fix 1 — Bug 1 (corretivo + preventivo)

**Squad:** @architect (decisão) → @dev (Dex) → @qa (Quinn)
**Estimate:** 10 min código + 10 min spec
**Dificuldade:** Trivial-baixa
**Severidade:** Crítica

##### Decisão arquitetural (Aria)

Duas camadas de defesa, em sequência:

**Camada 1 — `updateMessage` action vira no-op para msgs fora da janela** (`actions.js:442-445`)

Updates de status (`message.updated`) não fazem sentido visual quando a msg não está visível para o user. Skip silencioso evita poluir o array.

```js
updateMessage({ commit, rootGetters, state }, message) {
  const chat = state.allConversations.find(
    c => c.id === message.conversation_id
  );
  const exists = chat?.messages?.some(m => m.id === message.id);
  if (!exists) return;
  commit(types.ADD_MESSAGE, message);
  handleVoiceCallUpdated(commit, message, rootGetters?.getCurrentUserID);
}
```

**Camada 2 — `ADD_MESSAGE` mutation com insertion ordenada** (`index.js:305-309`)

Mesmo que algum caller chame `ADD_MESSAGE` direto (sem passar pelo action), o mutation não pode mais quebrar ordem. Defesa em profundidade.

```js
} else {
  // Defensive: preserve chronological order even if caller emits an out-of-order
  // message (e.g. WAHA status sync re-emitting old messages via ActionCable).
  const idx = chat.messages.findIndex(
    m => new Date(m.created_at) > new Date(message.created_at)
  );
  if (idx === -1) {
    chat.messages.push(message);
  } else {
    chat.messages.splice(idx, 0, message);
  }
  trimOldest(chat);
  chat.timestamp = message.created_at;
  // ... resto inalterado
}
```

**Nota:** `created_at` no broadcast WS é Unix em segundos (number); `new Date(number)` interpreta como ms. Se for number puro, comparar como número direto:

```js
const ts = m => Number(m.created_at) || new Date(m.created_at).getTime() / 1000;
const idx = chat.messages.findIndex(m => ts(m) > ts(message));
```

@dev decide a forma final no momento da implementação após confirmar o tipo real via Vue DevTools.

##### Critérios de aceite

- [ ] Spec Vitest: emitir `updateMessage` com msg cujo id NÃO está em `chat.messages` → array permanece igual
- [ ] Spec Vitest: emitir `ADD_MESSAGE` com `created_at` mais antigo que todas existentes → msg vai para o início; `created_at` no meio → vai para posição correta
- [ ] Spec Vitest: cenário Tozi reproduzido (array com msgs de hoje, push de msg de 11/abr) → array final em ordem ASC
- [ ] Manual em homologação: simular dispatch direto via Vue DevTools → ordem preservada
- [ ] Manual em produção pós-deploy: abrir conv 1177, observar 30 min sem novos saltos de ordem

##### Risco

Médio-baixo. `findIndex` é O(n) no array (max 500 por causa de window). Em arrays grandes pode haver overhead, mas como msgs novas tipicamente vão no fim, o findIndex retorna -1 rápido (full scan apenas quando msg é antiga — caso raro pós-fix).

##### Rollback

`git revert` do commit. Bug 1 volta. Sem efeitos colaterais persistentes (o array é client-side; F5 limpa).

---

#### Fix 2 — Bug 2 (DateSeparator prop type)

**Squad:** @dev (Dex) → @qa (Quinn)
**Estimate:** 1 min código + 2 min spec
**Dificuldade:** Trivial
**Severidade:** Cosmética

##### Mudança

```js
// app/javascript/shared/components/DateSeparator.vue:5-9
props: {
  date: {
    type: [String, Date, Number],  // ← antes: String
    required: true,
  },
},
```

##### Critérios de aceite

- [ ] Console limpo de warn `Invalid prop: type check failed for prop "date"`
- [ ] Renderização inalterada (visualmente)

##### Risco

Mínimo. Aceitar tipos que já funcionavam por coerção. Sem mudança de comportamento.

##### Rollback

`git revert`. Warn volta, UI continua.

---

#### Fix 3 — Bug 3 (VoiceCallButton import faltando)

**Squad:** @dev (Dex) → @qa (Quinn)
**Estimate:** 2 min código
**Dificuldade:** Trivial
**Severidade:** Cosmética

##### Mudança

```vue
<!-- app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue -->
<script>
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
// ... outros imports

export default {
  components: {
    VoiceCallButton,  // ← adicionar
    // ... componentes existentes
  },
  // ...
};
</script>
```

##### Critérios de aceite

- [ ] Console limpo de warn `Failed to resolve component: VoiceCallButton`
- [ ] Botão de chamada de voz renderiza no `ContactInfo` (se feature flag ativada)

##### Risco

Mínimo. Adicionar componente que JÁ existe. Pior caso: botão aparece onde não devia → revisar feature flag dele.

##### Rollback

`git revert`. Warn volta.

---

### 🛡️ Sprint Preventivo (próxima — 1h)

#### P1 — Spec de regression da ordem cronológica

**Squad:** @qa (Quinn)
**Estimate:** 30 min

Spec Vitest dedicado em `app/javascript/dashboard/store/modules/conversations/specs/mutations.spec.js`:

```js
describe('ADD_MESSAGE order preservation', () => {
  it('inserts out-of-order message at correct position', () => {
    const state = {
      allConversations: [{
        id: 1,
        messages: [
          { id: 100, created_at: 1700000000 }, // 14-nov-2023
          { id: 200, created_at: 1750000000 }, // 15-jun-2025
          { id: 300, created_at: 1778025000 }, // 06-mai-2026
        ],
      }],
      conversationMap: { 1: null },
    };
    state.conversationMap[1] = state.allConversations[0];

    // Status sync re-emite msg antiga (status muda de sent->delivered)
    mutations[types.ADD_MESSAGE](state, {
      id: 150,
      conversation_id: 1,
      created_at: 1740000000, // 19-fev-2025 (entre 100 e 200)
    });

    const ids = state.allConversations[0].messages.map(m => m.id);
    expect(ids).toEqual([100, 150, 200, 300]);
  });

  it('appends to end when message is the newest', () => { /* ... */ });
  it('prepends when message is the oldest', () => { /* ... */ });
});
```

#### P2 — Helper de sort guard (opcional, futuro)

**Squad:** @architect (Aria)

Função pura em `helpers.js`:

```js
export const insertSortedByCreatedAt = (messages, message) => {
  const ts = m => Number(m.created_at) || new Date(m.created_at).getTime() / 1000;
  const idx = messages.findIndex(m => ts(m) > ts(message));
  if (idx === -1) messages.push(message);
  else messages.splice(idx, 0, message);
  return messages;
};
```

Reutilizável em `ADD_MESSAGE`, `SET_PREVIOUS_CONVERSATIONS` (se mensagens fora de ordem chegam no payload do servidor — improvável, mas defensivo).

#### P3 — ADR sobre invariantes de `chat.messages`

**Squad:** @architect (Aria)
**Output:** `docs/adr/0002-chat-messages-invariants.md`

Documenta:
- Invariante 1: `chat.messages` deve estar sempre em ordem ASC por `created_at`
- Invariante 2: nenhum id duplicado (já garantido pelas mudanças de hoje em SET_PREVIOUS/NEXT_CONVERSATIONS)
- Invariante 3: nenhuma mutation pode quebrar essas invariantes
- Como adicionar nova mutation/action que toca em `chat.messages`: checklist obrigatório

---

## 4. Sequenciamento e Dependências

```
HOJE (Sprint Hotfix — total ~30 min):
  ├─ Fix 1 (ADD_MESSAGE + updateMessage)
  ├─ Fix 2 (DateSeparator prop type)
  └─ Fix 3 (VoiceCallButton import)
       └─ pnpm eslint + bundle exec rubocop
       └─ commit unico
       └─ assets:precompile (RAILS_ENV=production)
       └─ sudo systemctl restart chatwoot.target
       └─ smoke test em conv 1177 produção
       └─ monitor Vue warns (deve cair a zero)

D+1 (Sprint Preventivo — opcional, ~1h):
  ├─ P1 (specs Vitest de regression)
  ├─ P2 (helper insertSortedByCreatedAt)
  └─ P3 (ADR 0002 sobre invariantes)
```

---

## 5. Checklist Pós-Implementação (CLAUDE.md)

Para cada fix:

- [ ] `pnpm vitest run` — specs afetados passando (mutations.spec.js)
- [ ] `pnpm eslint` — sem erros nos arquivos modificados
- [ ] `bundle exec rubocop` — zero offenses (não toca Ruby neste plano, mas safety)
- [ ] Verificou `enterprise/` para arquivos relacionados
- [ ] Apenas `en.yml`/`en.json` editados em strings (este plano não toca i18n)
- [ ] CLAUDE.md atualizado se descobriu novo pitfall (incluir: "ADD_MESSAGE mutation deve preservar ordem ASC")
- [ ] Validar `db:migrate:status` antes de restart (regra do vault — Incidente Pending Migration 24-abr-2026)

---

## 6. Telemetria de Validação Pós-Deploy

**Métricas-chave (24h após deploy):**

1. **Bug 1 (mensagens fora de ordem):**
   - Reports do canal de suporte com palavras-chave "fora de ordem|repetida|11 de abril|data errada" — deve cair a zero
   - Reabrir conv 1177 e confirmar fluxo end-to-end (msg outgoing → 10s → status sync → ordem mantém)
   - Métrica indireta: `journalctl -u chatwoot-worker.1 | grep "Performed Waha::MessageStatusSyncJob"` continua executando normal (não bloqueamos o backfill, só blindamos o frontend)

2. **Bug 2 (DateSeparator warn):**
   - Console do navegador limpo de "Invalid prop: type check failed for prop \"date\""

3. **Bug 3 (VoiceCallButton warn):**
   - Console do navegador limpo de "Failed to resolve component: VoiceCallButton"

---

## 7. Riscos e Rollback

| Fix | Risco | Mitigação | Rollback |
|---|---|---|---|
| 1 (Camada 1) | Skip de update legítimo se mensagem foi removida do array por outro motivo | findPendingMessageIndex já checa por id; apenas updates para msgs invisíveis são afetadas | `git revert` |
| 1 (Camada 2) | Custo O(n) em insertion para arrays grandes | window=500 limita; findIndex bate em -1 rápido no caso normal (msg nova vai no fim) | `git revert` |
| 2 | UX inalterada; risco zero | Spec | `git revert` |
| 3 | Botão aparece onde não devia | Verificar feature flag de chamadas em homologação primeiro | `git revert` |

---

## 8. Apêndices

### A. Evidências brutas

**Conv account 3 / 1177 (Leo Tozi, 06-mai-2026):**
- 1665 mensagens no DB
- Range cronológico: 2025-12-29 → 2026-05-06
- 0 inversões cronológicas no DB (id ↑ ⟺ created_at ↑)
- Inbox 2 (`simplex_996571379`) com `team_message_isolation: false`
- 20 últimas mensagens (default page) range: 2026-04-30 → 2026-05-06 (9 datas, todas em ordem ASC)

**Console warns (relato Walisson via Leo):**
```
[Vue warn]: Invalid prop: type check failed for prop "date".
  Expected String with value "Wed May 06 2026 07:54:51 GMT-0400 (Horário Padrão do Amazonas)", got Date
  at <DateSeparator key=0 date= Wed May 06 2026 07:54:51 GMT-0400 (...) >

[Vue warn]: Failed to resolve component: VoiceCallButton
  at <ContactInfo contact= Object channel-type=undefined >
```

### B. Referências de código

| Arquivo | Linhas | Responsabilidade |
|---|---|---|
| `app/javascript/dashboard/store/modules/conversations/index.js` | 290–309 | `ADD_MESSAGE` mutation (alvo Fix 1 Camada 2) |
| `app/javascript/dashboard/store/modules/conversations/actions.js` | 442–445 | `updateMessage` action (alvo Fix 1 Camada 1) |
| `app/javascript/dashboard/store/modules/conversations/helpers.js` | 3–8 | `findPendingMessageIndex` |
| `app/javascript/dashboard/components-next/message/MessageList.vue` | 314 | passa Date para DateSeparator |
| `app/javascript/shared/components/DateSeparator.vue` | 5–9 | prop type a corrigir (Fix 2) |
| `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue` | 24, 257 | import faltando (Fix 3) |
| `app/javascript/dashboard/components-next/Contacts/VoiceCallButton.vue` | — | componente que precisa ser importado |
| `app/jobs/send_reply_job.rb` | 39–45 | hook que disparou amplificação (Task 2.1) |
| `app/services/waha/message_status_sync_service.rb` | 34–51 | sincroniza status — origem do broadcast |

### C. Squad mapping (AIOX)

| Agente | Persona | Responsabilidade neste plano |
|---|---|---|
| @aiox-master (Orion) | Orquestrador 👑 | Coordenação, handoff entre fixes, validação final |
| @architect (Aria) | Arquiteto | Decisão Camada 1+2 do Fix 1, ADR 0002 |
| @dev (Dex) | Implementador | Código Fixes 1, 2, 3 + helper P2 |
| @qa (Quinn) | Qualidade | Specs Vitest (P1) + smoke test em homologação + validação produção |
| @devops (Gage) | Operações | `git push`, `assets:precompile`, `systemctl restart chatwoot.target` (após `db:migrate:status`) |

### D. Histórico relacionado

| Data | Evento | Doc |
|---|---|---|
| 2026-05-05 | Plano original 3 bugs (mensagens sumindo, edit timeout, dedupe) | `docs/plano-correcao-bugs-mensagens-2026-05-05.md` |
| 2026-05-05 21:40 UTC | Deploy commit `8bf795a6b` (Tasks 1.1, 1.2, 2.1, 3.1) | — |
| 2026-05-05 23:58 UTC | Deploy commit `d131b69e2` (team_message_isolation fixes) | `docs/adr/0001-team-message-isolation.md` |
| 2026-05-06 ~12:00 UTC | Report Leo Tozi sobre conv 1177 fora de ordem | este plano |

---

**Próximo passo:** Aprovação para iniciar Sprint Hotfix (Fix 1 + 2 + 3 em commit único). Ao confirmar, faço handoff para `@dev` e ao final `@devops` para deploy.

— Orion, orquestrando o sistema 🎯
