# Fix UX — Tooltip do rail + Input "Buscar conversas"

## Problema 1 — Tooltip do Capitão sobrepõe o ícone

### Causa raiz
`FloatingVue` (via `@floating-ui/dom`) aplica `distance` como **mainAxis offset** entre o anchor e o `.v-popper__wrapper` (via `transform: translate3d()`). Porém o `.v-popper__arrow-outer` do floating-vue fica **fora do wrapper**, com `left:-6px` (placement=right). Isso significa que a ponta visível do arrow fica 6px ANTES do wrapper.

Com `distance: 2`:
- Anchor termina em x=55 (ícone `size-10` em x=15 + 40px).
- Wrapper posicionado em x=57 (anchor_right + distance=2). Correto.
- Mas arrow começa em x=51 (57-6) → **arrow invade 4px do ícone**.

O `translate3d(53px, ...)` observado pelo Walisson é o `.v-popper__popper` root (que tem o mesmo origin do wrapper mais offset interno de ~4px do arrow-container). Em ambos os cálculos, a conclusão é: distance=2 é insuficiente porque não reserva espaço para arrow-outer (6px) + folga visual (≥2px).

A regra `margin: 0 !important` no `_wa-skin.scss` NÃO causa o problema — floating-vue usa `transform`, não margin.

### Fix aplicado
**Arquivo:** `app/javascript/entrypoints/dashboard.js` linha 95

```diff
 themes: {
   tooltip: {
     placement: 'top',
-    distance: 2,
+    distance: 10,
     delay: { show: 250, hide: 0 },
     html: false,
   },
```

`distance: 10` garante: arrow-outer (6px) + folga (4px) = tooltip começa em x=61, 6px fora do ícone. Alinhado ao WhatsApp Web.

---

## Problema 2 — Input "Buscar conversas" inconsistente

### Inventário dos inputs
1. `ConversationSearchBar.vue` — usado em `ChatListHeader.vue:337`. **Wrapper completo WA-fiel** (bg `#202c33` dark, ícone `i-lucide-search`, altura 35px, rounded-lg, border focus verde). **Correto.**
2. `ConversationSearchModal.vue` — usado em `ChatList.vue:1307`. **Input "cru"** com classes Chatwoot genéricas (`border-n-weak`, `placeholder:text-n-slate-9`, `py-2`, sem ícone search, sem bg `#202c33`). **Divergente do padrão WA.**

O input cru do modal é a "Forma A" que o Walisson viu. Ambos tem o mesmo placeholder `CONVERSATION.SEARCH_CONVERSATIONS` (pt-BR: "Buscar conversas...") mas visual diferente.

### Fix aplicado
**Arquivo:** `app/javascript/dashboard/components/widgets/conversation/ConversationSearchModal.vue` linhas 108-125

Troquei o input cru pelo wrapper WA-fiel idêntico ao `ConversationSearchBar.vue`:
- Wrapper `flex items-center h-[35px] rounded-lg px-3 gap-3 bg-n-solid-1 dark:bg-[#202c33]`
- Ícone `i-lucide-search size-4 text-[#54656f] dark:text-[#aebac1]` (ou Spinner quando buscando)
- Input com `text-[15px] leading-[35px]`, caret verde, placeholder `#8696a0`
- Focus-within border verde (`var(--wa-primary)`)
- Removido spinner absoluto (agora in-line substituindo o ícone search, padrão WA)

---

## Arquivos alterados
- `/home/chatwoot/chatwoot/app/javascript/entrypoints/dashboard.js` (1 linha)
- `/home/chatwoot/chatwoot/app/javascript/dashboard/components/widgets/conversation/ConversationSearchModal.vue` (17 linhas)

## Validação pós-build
Após `pnpm dev` ou precompile:
1. Rail colapsado → hover "Capitão" → tooltip aparece **fora do rail**, gap ≥4px do ícone.
2. Abrir modal de busca global (ChatList) → input idêntico ao da sidebar (mesmo bg, mesma altura, mesmo ícone search, mesmo placeholder styling).
