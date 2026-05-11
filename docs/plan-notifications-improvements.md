# Plano de Execução — Melhorias de Notificação ChatSPX

> **Status:** 🟢 Pronto pra execução (aprovado pelo Walisson)
> **Data:** 2026-04-25
> **Branch:** `homologacao`
> **Escopo:** 3 features de notificação + destaque visual de mensagens atrasadas

---

## 🎯 Decisões aprovadas

| # | Item | Decisão |
|---|---|---|
| 1 | Cap do contador de title | `99+` (acima de 99 vira "(99+)") |
| 2 | Toast in-app | Som + toast juntos (config user pode desligar cada um) |
| 3 | Vermelho escalado | 3 níveis: âmbar (5min) / laranja (15min) / vermelho (30min) |
| 4 | SLA do inbox | Respeitar quando configurado, senão usar defaults acima |

---

## 📋 Feature 1 — Title da aba `(N) SPX - CHAT`

### Comportamento esperado
- Sem mensagens pendentes: `SPX - CHAT`
- Com 3 mensagens pendentes: `(3) SPX - CHAT`
- Com 150 pendentes: `(99+) SPX - CHAT`
- Volta pro padrão quando user marca todas como lidas
- Atualiza em tempo real conforme stats mudam

### O que conta como "N"
Soma de:
- `notifications/getUnreadCount` (notificações do agente — menções, atribuições, SLA)
- `conversationStats.unattendedAssignedCount` (conversas atribuídas a mim, sem resposta)

**Nota:** sem dupla contagem — esses 2 já vêm do backend separados.

### Arquivos a criar
- `app/javascript/dashboard/composables/useDocumentTitle.js` (novo)

### Arquivos a modificar
- `app/javascript/dashboard/App.vue` — importar e inicializar o composable

### Pseudocódigo

```js
// useDocumentTitle.js
import { computed, watchEffect } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const BASE_TITLE = 'SPX - CHAT';
const MAX_DISPLAY = 99;

export function useDocumentTitle() {
  const unreadNotifs = useMapGetter('notifications/getUnreadCount');
  const stats = useMapGetter('conversationStats/getStats');

  const totalCount = computed(() => {
    const n = unreadNotifs.value || 0;
    const u = stats.value?.unattendedAssignedCount || 0;
    return n + u;
  });

  const displayCount = computed(() => {
    if (totalCount.value === 0) return null;
    if (totalCount.value > MAX_DISPLAY) return `${MAX_DISPLAY}+`;
    return String(totalCount.value);
  });

  watchEffect(() => {
    document.title = displayCount.value
      ? `(${displayCount.value}) ${BASE_TITLE}`
      : BASE_TITLE;
  });
}
```

### Critérios de aceitação
- [ ] Title atualiza ao receber notificação (sem F5)
- [ ] Cap em "(99+)" quando count > 99
- [ ] Volta pro padrão `SPX - CHAT` ao zerar
- [ ] Não conflita com hot-reload do dev

### Tempo: ~1h

---

## 📋 Feature 2 — Toast in-app de nova mensagem (com som)

### Comportamento esperado
- Quando chega mensagem nova de cliente:
  - **Som toca** (já funciona — respeita config `none/all/mine/unassigned/notme`)
  - **Toast aparece** no canto inferior direito da tela com:
    - Avatar do contato
    - Nome do contato (bold)
    - Preview da mensagem (1 linha, truncada)
    - Botão "Abrir" (clica → router.push pra conversa)
  - Auto-dismiss em **6 segundos**
  - Click no toast = abrir conversa
- **NÃO mostra** se:
  - User está com a aba inativa (já vai ter desktop notification + favicon badge)
  - User já está NA conversa (não polui)
  - Config de notificação tá `none`

### Arquivos a criar
- `app/javascript/dashboard/components-next/notifications/MessageToast.vue` (novo)

### Arquivos a modificar
- `app/javascript/dashboard/helper/AudioAlerts/DashboardAudioNotificationHelper.js` — disparar toast junto com som
- `app/javascript/dashboard/composables/index.js` (se precisar registrar evento `messageToast`)

### Pseudocódigo

```js
// MessageToast.vue (novo)
<template>
  <div class="fixed bottom-4 right-4 z-[100] ...">
    <Avatar :src="contactAvatar" :name="contactName" :size="40" />
    <div>
      <div class="font-medium">{{ contactName }}</div>
      <div class="text-sm text-n-slate-11 truncate">{{ messagePreview }}</div>
    </div>
    <button @click="navigateToConversation">{{ $t('OPEN') }}</button>
  </div>
</template>
```

```js
// DashboardAudioNotificationHelper.js (modificar)
onNewMessage(message) {
  // ...código existente que toca som...

  // Adicionar: dispara toast se condições OK
  if (
    document.visibilityState === 'visible' &&
    !this.isUserInThisConversation(message.conversation_id) &&
    this.audioSetting !== 'none'
  ) {
    emitter.emit('messageToast', {
      contactName: message.sender?.name,
      contactAvatar: message.sender?.thumbnail,
      messagePreview: message.content?.substring(0, 80),
      conversationId: message.conversation_id,
    });
  }
}
```

```js
// App.vue (modificar)
<MessageToast />  // listener global
```

### Critérios de aceitação
- [ ] Toast aparece ao receber mensagem nova
- [ ] Som toca junto (não substitui)
- [ ] Click navega pra conversa
- [ ] Auto-dismiss em 6s
- [ ] Não aparece quando estou na conversa
- [ ] Respeita config de áudio (none/mine/etc)

### Tempo: ~3h

---

## 📋 Feature 3 — Destaque escalado de não-respondidas

### Comportamento esperado

Conversas atribuídas a mim, com última mensagem do contato sem resposta, ganham destaque visual escalado por tempo:

| Tempo desde última msg | Cor do timestamp + ring | Faixa lateral |
|---|---|---|
| 0–5 min | cinza (normal) | nenhuma |
| 5–15 min | 🟡 âmbar `#f59e0b` | âmbar lateral fina |
| 15–30 min | 🟠 laranja `#f97316` | laranja lateral média |
| 30+ min | 🔴 vermelho `#ef4444` | vermelho lateral grossa + pulse sutil |

### Filtro (entra na lógica só se TODAS forem true)
- `conversation.assignee_id == currentUser.id`
- `conversation.status == 'open'`
- `last_message.message_type == 'incoming'` (cliente)
- `unread_count > 0`

### SLA do inbox
- Se `inbox.sla_first_response_threshold` existe → usa esses thresholds (em segundos)
- Senão → usa defaults `[5*60, 15*60, 30*60]` segundos

### Arquivos a modificar
- `app/javascript/dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue` — adicionar lógica de cor escalada
- `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue` (legado, se ainda em uso) — mesma lógica

### Arquivos a criar
- `app/javascript/dashboard/composables/useConversationUrgency.js` (novo) — composable que calcula nível 0-3

### Pseudocódigo

```js
// useConversationUrgency.js
import { computed } from 'vue';
import { differenceInSeconds } from 'date-fns';

const DEFAULT_THRESHOLDS = [5 * 60, 15 * 60, 30 * 60]; // segundos

export function useConversationUrgency(conversation, currentUserId) {
  const urgencyLevel = computed(() => {
    const c = conversation.value;
    if (!c) return 0;

    // Filtro
    const assignedToMe = c.meta?.assignee?.id === currentUserId.value;
    const isOpen = c.status === 'open';
    const lastMsg = c.messages?.[c.messages.length - 1];
    const isFromContact = lastMsg?.message_type === 0; // 0 = incoming
    const hasUnread = (c.unread_count || 0) > 0;

    if (!(assignedToMe && isOpen && isFromContact && hasUnread)) return 0;

    // Calcular delay
    const lastTime = lastMsg?.created_at;
    if (!lastTime) return 0;
    const elapsed = differenceInSeconds(new Date(), new Date(lastTime * 1000));

    // Thresholds — usa SLA se inbox tem
    const sla = c.inbox?.sla_policy?.first_response_threshold;
    const thresholds = sla
      ? [sla * 0.33, sla * 0.66, sla]
      : DEFAULT_THRESHOLDS;

    if (elapsed >= thresholds[2]) return 3; // vermelho crítico
    if (elapsed >= thresholds[1]) return 2; // laranja urgente
    if (elapsed >= thresholds[0]) return 1; // âmbar atenção
    return 0;
  });

  const colorClass = computed(() => {
    return ['', 'urgency-1', 'urgency-2', 'urgency-3'][urgencyLevel.value];
  });

  return { urgencyLevel, colorClass };
}
```

```css
/* CSS scoped no ConversationCard ou _wa-skin.scss */
.urgency-1 .timestamp { color: #f59e0b; }
.urgency-1 { border-left: 2px solid #f59e0b; }

.urgency-2 .timestamp { color: #f97316; }
.urgency-2 { border-left: 3px solid #f97316; }

.urgency-3 .timestamp { color: #ef4444; }
.urgency-3 { border-left: 4px solid #ef4444; }
.urgency-3::before {
  /* pulse sutil */
  animation: urgency-pulse 2s ease-in-out infinite;
}
```

### Critérios de aceitação
- [ ] Conversa atribuída a mim com >5min sem resposta vira âmbar
- [ ] >15min vira laranja
- [ ] >30min vira vermelho com pulse
- [ ] Conversa aguardando cliente (última msg minha) NÃO destaca
- [ ] Conversa fechada NÃO destaca
- [ ] Conversa atribuída a outro NÃO destaca pra mim
- [ ] SLA configurado override defaults

### Tempo: ~4h

---

## 🚀 Ordem de execução

1. **Feature 1 (Title)** — 1h, baixíssimo risco
2. **Feature 2 (Toast)** — 3h, médio risco (toca em fluxo de mensagens)
3. **Feature 3 (Destaque)** — 4h, médio risco (UI complexa, SLA opcional)
4. **QA final consolidado** — 30min via Playwright

**Total: ~8h30**

## ✅ Checklist de QA final

- [ ] Title atualiza ao receber mensagem
- [ ] Title cap em 99+
- [ ] Som toca + toast aparece simultâneos
- [ ] Toast click abre conversa
- [ ] Toast NÃO aparece se já estou na conversa
- [ ] Conversa atribuída + atrasada vira âmbar/laranja/vermelho
- [ ] ESLint clean nos arquivos novos/modificados
- [ ] `bundle exec rubocop -a` sem offenses
- [ ] Bundle JS gerado, restart OK, HTTP 200

## ⚠️ Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Title flicker em re-render rápido | watchEffect + computed (Vue otimiza) |
| Toast spam se chegar 10 msgs juntas | Debounce 500ms + agrupar por contact_id |
| ConversationCard re-render constante por timer | Calcular nível 1x ao montar + recomputar a cada 30s |
| SLA do inbox vir undefined | Fallback pros defaults sempre presente |

## 📦 Deliverables

- 3 features funcionais no `homologacao`
- Working tree (NÃO commitar até Walisson aprovar TUDO)
- Screenshot final mostrando os 3 efeitos
- Doc `docs/plan-notifications-improvements.md` (este arquivo)
