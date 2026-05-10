# Copilot Redesign 2026 — Plano Mestre Executável

> **Objetivo:** Modernizar TODA a área do Copilot do Chat SPX (homologação branch `homologacao`).
> Visual atual está datado ("ChatGPT 2022"). Queremos identidade própria, fácil pro usuário leigo, responsivo.
> **Stack:** Vue 3 Composition API + Tailwind + `@egoist/tailwindcss-icons` (Lucide).
> **Branch:** `homologacao` (NÃO produção). Build com `RAILS_ENV=production bundle exec rake assets:precompile`.

---

## 🎯 Princípios

1. **Fácil pra usuário leigo** — cada elemento comunica claramente o que é/faz
2. **Identidade própria** — sparkle ✨ como linguagem visual unificada
3. **Profissional, não infantil** — "serious work, not entertainment"
4. **Mobile-first responsivo** — testar em 320px de largura
5. **Cores de marca** — verde brand + roxo accent só em IA
6. **Performance** — só CSS animations, sem JS pesado
7. **Reduced motion** — respeitar `prefers-reduced-motion` (composable `useReducedMotion` já existe)
8. **Dark mode** — testar todas as cores em ambos modos

---

## 📂 Arquivos afetados (mapa completo)

### Componentes Vue
- `app/javascript/dashboard/components-next/copilot/Copilot.vue`
- `app/javascript/dashboard/components-next/copilot/CopilotEmptyState.vue`
- `app/javascript/dashboard/components-next/copilot/CopilotInput.vue`
- `app/javascript/dashboard/components-next/copilot/CopilotLoader.vue`
- `app/javascript/dashboard/components-next/copilot/CopilotAgentMessage.vue`
- `app/javascript/dashboard/components-next/copilot/CopilotAssistantMessage.vue`
- `app/javascript/dashboard/components-next/copilot/CopilotLauncher.vue`
- `app/javascript/dashboard/components-next/copilot/ToggleCopilotAssistant.vue`
- `app/javascript/dashboard/components/widgets/conversation/copilot/CaptainLoader.vue`
- `app/javascript/dashboard/components/widgets/WootWriter/CopilotMenuBar.vue`

### Estilos
- `app/javascript/dashboard/assets/scss/_wa-skin.scss` (adicionar keyframes globais)

### i18n
- `app/javascript/dashboard/i18n/locale/en/conversation.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`

---

## 🏗️ FASE 0 — Fundação Visual

### Objetivo
Centralizar tokens reutilizáveis em CSS pra evitar inconsistência. Tudo que vier depois consome esses tokens.

### Arquivo
`app/javascript/dashboard/assets/scss/_wa-skin.scss`

### Adicionar ao final do arquivo
```scss
/* ============================================
   COPILOT 2026 — AI Animation Tokens
   Reutilizado por: Loader, EmptyState, Header,
   Launcher, Empty cards
   ============================================ */

@keyframes ai-sparkle-float {
  0%, 100% { transform: translateY(0) scale(1); opacity: 0.6; }
  50% { transform: translateY(-3px) scale(1.1); opacity: 1; }
}

@keyframes ai-shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

@keyframes ai-glow-pulse {
  0%, 100% {
    box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.4),
                0 0 20px 0 rgba(34, 197, 94, 0.2);
  }
  50% {
    box-shadow: 0 0 0 6px rgba(34, 197, 94, 0),
                0 0 30px 4px rgba(34, 197, 94, 0.3);
  }
}

@keyframes ai-launcher-pulse {
  0%, 100% { box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.5); }
  70% { box-shadow: 0 0 0 12px rgba(34, 197, 94, 0); }
}

.ai-sparkle {
  animation: ai-sparkle-float 2.4s ease-in-out infinite;
}
.ai-sparkle-delay-1 { animation-delay: 0.3s; }
.ai-sparkle-delay-2 { animation-delay: 0.6s; }
.ai-sparkle-delay-3 { animation-delay: 0.9s; }

.ai-shimmer {
  background: linear-gradient(
    90deg,
    rgba(148, 163, 184, 0.15) 0%,
    rgba(148, 163, 184, 0.35) 50%,
    rgba(148, 163, 184, 0.15) 100%
  );
  background-size: 200% 100%;
  animation: ai-shimmer 1.6s ease-in-out infinite;
}

.ai-glow {
  animation: ai-glow-pulse 2.8s ease-in-out infinite;
}

.ai-launcher-pulse {
  animation: ai-launcher-pulse 2.4s ease-in-out infinite;
}

@media (prefers-reduced-motion: reduce) {
  .ai-sparkle, .ai-shimmer, .ai-glow, .ai-launcher-pulse {
    animation: none;
  }
}
```

### Validação
- [ ] `bundle exec rake assets:precompile` passa
- [ ] Classes acessíveis via inspetor (`getComputedStyle` mostra animation)

---

## 🏗️ FASE 1 — Loaders Modernos (Sparkles + Shimmer)

### 1.1 — `CopilotLoader.vue` (painel lateral)

**Substituir TODO o conteúdo do arquivo** `app/javascript/dashboard/components-next/copilot/CopilotLoader.vue`:

```vue
<script setup>
// Copilot Loader 2026 — Sparkles + Shimmer
</script>

<template>
  <div class="flex justify-start w-full">
    <div class="flex items-start gap-2 w-full">
      <div class="relative flex items-center justify-center size-8 shrink-0">
        <span
          class="i-lucide-sparkles size-4 text-n-brand absolute ai-sparkle ai-sparkle-delay-1"
          style="top: 4px; left: 4px"
        />
        <span
          class="i-lucide-sparkle size-3 text-n-brand absolute ai-sparkle ai-sparkle-delay-2"
          style="top: 14px; left: 18px"
        />
        <span
          class="i-lucide-sparkle size-2.5 text-n-brand/70 absolute ai-sparkle ai-sparkle-delay-3"
          style="top: 22px; left: 8px"
        />
      </div>
      <div class="flex flex-col gap-2 flex-1 pt-1">
        <span class="text-xs text-n-slate-11 font-medium">
          {{ $t('CAPTAIN.COPILOT.LOADER') }}
        </span>
        <div class="space-y-1.5 w-full">
          <div class="h-2 rounded-full ai-shimmer w-3/4" />
          <div class="h-2 rounded-full ai-shimmer w-1/2" />
        </div>
      </div>
    </div>
  </div>
</template>
```

### 1.2 — `CaptainLoader.vue` (editor)

**Substituir TODO** `app/javascript/dashboard/components/widgets/conversation/copilot/CaptainLoader.vue`:

```vue
<script setup>
import Icon from 'next/icon/Icon.vue';
</script>

<template>
  <div class="relative inline-flex items-center justify-center">
    <div
      class="absolute inset-0 rounded-full ai-glow"
      aria-hidden="true"
    />
    <Icon
      v-once
      icon="i-woot-captain"
      class="relative z-10"
    />
  </div>
</template>
```

### 1.3 — i18n

`app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` — atualizar:
```json
"LOADER": "Pensando uma boa resposta…"
```

`app/javascript/dashboard/i18n/locale/en/conversation.json` — atualizar:
```json
"LOADER": "Thinking of a great response…"
```

### Validação
- [ ] Painel: ao enviar mensagem, mostra 3 sparkles + skeleton shimmer
- [ ] Editor: ao clicar "Melhorar", logo Captain com glow pulsante (sem pular)

---

## 🏗️ FASE 2 — Empty State Acolhedor

### Arquivo
`app/javascript/dashboard/components-next/copilot/CopilotEmptyState.vue`

### Substituir TODO o `<template>` por:

```vue
<template>
  <div class="flex-1 flex flex-col items-center justify-center gap-6 px-2 py-8 w-full">
    <div class="flex flex-col items-center text-center space-y-3">
      <div class="relative flex items-center justify-center size-16">
        <div
          class="absolute inset-0 rounded-full ai-glow bg-n-brand/10"
          aria-hidden="true"
        />
        <Icon icon="i-woot-captain" class="text-n-brand text-5xl relative z-10" />
      </div>
      <div class="space-y-1.5 max-w-[260px]">
        <h3 class="text-base font-semibold text-n-slate-12 leading-7">
          {{ $t('CAPTAIN.COPILOT.PANEL_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 leading-snug">
          {{ $t('CAPTAIN.COPILOT.KICK_OFF_MESSAGE') }}
        </p>
      </div>
    </div>

    <div v-if="!hasAssistants" class="w-full space-y-2 text-center">
      <p class="text-sm text-n-slate-11 leading-6">
        {{ $t('CAPTAIN.ASSISTANTS.NO_ASSISTANTS_AVAILABLE') }}
      </p>
      <router-link
        :to="{
          name: 'captain_assistants_create_index',
          params: { accountId: route.params.accountId },
        }"
        class="text-sm text-n-brand hover:underline"
      >
        {{ $t('CAPTAIN.ASSISTANTS.ADD_NEW') }}
      </router-link>
    </div>

    <div v-else class="w-full space-y-2.5">
      <span class="text-xs font-semibold text-n-slate-10 uppercase tracking-wider block px-1">
        {{ $t('CAPTAIN.COPILOT.TRY_THESE_PROMPTS') }}
      </span>
      <div class="flex flex-col gap-2">
        <button
          v-for="prompt in promptOptions"
          :key="prompt.label"
          class="group flex items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-left transition-all duration-200 hover:border-n-brand/40 hover:bg-n-brand/5 hover:-translate-y-0.5 hover:shadow-sm motion-reduce:hover:translate-y-0"
          @click="handleSuggestion(prompt)"
        >
          <span
            :class="prompt.icon"
            class="size-4 mt-0.5 shrink-0 text-n-brand"
          />
          <div class="flex flex-col gap-0.5 min-w-0">
            <span class="text-sm font-medium text-n-slate-12 leading-tight">
              {{ t(prompt.label) }}
            </span>
            <span class="text-xs text-n-slate-10 leading-snug">
              {{ t(prompt.description) }}
            </span>
          </div>
        </button>
      </div>
    </div>
  </div>
</template>
```

### Atualizar `<script setup>` — `routePromptMap`:
```js
const routePromptMap = {
  conversations: [
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.LABEL',
      description: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.HINT',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.CONTENT',
      icon: 'i-lucide-list',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.SUGGEST.LABEL',
      description: 'CAPTAIN.COPILOT.PROMPTS.SUGGEST.HINT',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.SUGGEST.CONTENT',
      icon: 'i-lucide-sparkles',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.RATE.LABEL',
      description: 'CAPTAIN.COPILOT.PROMPTS.RATE.HINT',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.RATE.CONTENT',
      icon: 'i-lucide-star',
    },
  ],
  dashboard: [
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.HIGH_PRIORITY.LABEL',
      description: 'CAPTAIN.COPILOT.PROMPTS.HIGH_PRIORITY.HINT',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.HIGH_PRIORITY.CONTENT',
      icon: 'i-lucide-flag',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.LIST_CONTACTS.LABEL',
      description: 'CAPTAIN.COPILOT.PROMPTS.LIST_CONTACTS.HINT',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.LIST_CONTACTS.CONTENT',
      icon: 'i-lucide-users',
    },
  ],
};
```

### i18n — adicionar/atualizar
`pt_BR/conversation.json` (chaves dentro de `CAPTAIN.COPILOT`):
```json
{
  "PANEL_TITLE": "Como posso ajudar você hoje?",
  "KICK_OFF_MESSAGE": "Sou o Copilot, sua IA de atendimento. Posso resumir conversas, sugerir respostas ou tirar dúvidas.",
  "TRY_THESE_PROMPTS": "Sugestões para começar",
  "PROMPTS": {
    "SUMMARIZE": { "LABEL": "Resumir esta conversa", "HINT": "Te conto rapidinho o que rolou" },
    "SUGGEST":   { "LABEL": "Sugerir uma resposta", "HINT": "Crio um rascunho pra você editar" },
    "RATE":      { "LABEL": "Avaliar esta conversa", "HINT": "Análise de tom e qualidade" },
    "HIGH_PRIORITY": { "LABEL": "Conversas urgentes", "HINT": "Mostro o que precisa de atenção agora" },
    "LIST_CONTACTS": { "LABEL": "Listar contatos", "HINT": "Visão geral da sua base" }
  }
}
```

`en/conversation.json` (mesma estrutura, traduzido):
```json
{
  "PANEL_TITLE": "How can I help you today?",
  "KICK_OFF_MESSAGE": "I'm Copilot, your support AI. I can summarize conversations, suggest replies, or answer questions.",
  "TRY_THESE_PROMPTS": "Suggestions to get started",
  "PROMPTS": {
    "SUMMARIZE": { "LABEL": "Summarize this chat", "HINT": "Quick recap of what happened" },
    "SUGGEST":   { "LABEL": "Suggest a reply", "HINT": "I draft something you can edit" },
    "RATE":      { "LABEL": "Rate this conversation", "HINT": "Tone and quality analysis" },
    "HIGH_PRIORITY": { "LABEL": "Urgent conversations", "HINT": "What needs attention right now" },
    "LIST_CONTACTS": { "LABEL": "List contacts", "HINT": "Overview of your contact base" }
  }
}
```

### Validação
- [ ] Avatar 64px com glow visível
- [ ] 3 cards verticais clicáveis
- [ ] Hover: cada card "levanta" 2px + sombra
- [ ] Click no card → envia o prompt
- [ ] Mobile (320px): cards ocupam largura total

---

## 🏗️ FASE 3 — Header com Identidade

### Arquivo
`app/javascript/dashboard/components-next/copilot/Copilot.vue`

### Substituir o bloco `<SidebarActionsHeader ... />` por header customizado

Localizar o `<template>` e trocar:
```vue
<SidebarActionsHeader
  :title="$t('CAPTAIN.COPILOT.TITLE')"
  :buttons="copilotButtons"
  @click="handleSidebarAction"
  @close="closeCopilotPanel"
/>
```

Por:
```vue
<div class="flex items-center justify-between px-4 h-[60px] border-b border-n-weak shrink-0">
  <div class="flex items-center gap-3 min-w-0">
    <div class="relative flex items-center justify-center size-9 shrink-0">
      <div
        v-if="!shouldShowLoader"
        class="absolute inset-0 rounded-full bg-n-brand/10 ai-glow"
        aria-hidden="true"
      />
      <Icon icon="i-woot-captain" class="relative z-10 text-n-brand text-2xl" />
      <span
        class="absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full ring-2 ring-n-solid-1"
        :class="statusDotColor"
        aria-hidden="true"
      />
    </div>
    <div class="flex flex-col min-w-0">
      <span class="text-[15px] font-semibold text-n-slate-12 leading-tight truncate">
        {{ $t('CAPTAIN.COPILOT.TITLE') }}
      </span>
      <span class="text-xs text-n-slate-10 leading-tight truncate">
        {{ statusLabel }}
      </span>
    </div>
  </div>
  <div class="flex items-center gap-1 shrink-0">
    <button
      v-for="btn in copilotButtons"
      :key="btn.key"
      v-tooltip="btn.tooltip"
      class="flex items-center justify-center size-8 rounded-lg hover:bg-n-slate-3 transition-colors"
      @click="handleSidebarAction(btn.key)"
    >
      <span :class="btn.icon" class="size-4 text-n-slate-11" />
    </button>
    <button
      class="flex items-center justify-center size-8 rounded-lg hover:bg-n-slate-3 transition-colors"
      @click="closeCopilotPanel"
    >
      <span class="i-lucide-x size-4 text-n-slate-11" />
    </button>
  </div>
</div>
```

### Adicionar ao `<script setup>` (depois das computed existentes):
```js
import Icon from 'next/icon/Icon.vue';

const statusLabel = computed(() => {
  if (props.hasTimedOut) return t('CAPTAIN.COPILOT.STATUS_OFFLINE');
  if (shouldShowLoader.value) return t('CAPTAIN.COPILOT.STATUS_THINKING');
  return t('CAPTAIN.COPILOT.STATUS_READY');
});

const statusDotColor = computed(() => {
  if (props.hasTimedOut) return 'bg-n-slate-9';
  if (shouldShowLoader.value) return 'bg-n-amber-9 animate-pulse';
  return 'bg-n-teal-9';
});
```

### i18n — adicionar
`pt_BR/conversation.json`:
```json
"STATUS_READY": "Pronto pra ajudar",
"STATUS_THINKING": "Pensando…",
"STATUS_OFFLINE": "Offline"
```

`en/conversation.json`:
```json
"STATUS_READY": "Ready to help",
"STATUS_THINKING": "Thinking…",
"STATUS_OFFLINE": "Offline"
```

### Validação
- [ ] Header tem avatar 36px com bolinha de status
- [ ] Idle: bolinha verde + "Pronto pra ajudar"
- [ ] Loading: bolinha âmbar pulsante + "Pensando…"
- [ ] Click X fecha o painel

---

## 🏗️ FASE 4 — Dropdown Reorganizado (Promptbook + Search + Sub-grupos)

### Arquivo
`app/javascript/dashboard/components/widgets/WootWriter/CopilotMenuBar.vue`

### Refactor crítico — manter:
- A computed `sections` original (para tooltips e disabled states)
- Lógica de `flatItems` para keyboard navigation
- `data-ai-tour="dropdown-first-item"` no primeiro item visível
- Eventos `executeCopilotAction`

### Adicionar ao `<script setup>` (depois dos imports):
```js
import { ref, computed } from 'vue';

const searchQuery = ref('');

// Promptbook: 4 ações destacadas no topo
const PROMPTBOOK_KEYS = ['summarize', 'reply_suggestion', 'improve', 'shorten'];

const promptbookItems = computed(() => {
  const allItems = sections.value.flatMap(s => s.items);
  return PROMPTBOOK_KEYS
    .map(key => allItems.find(i => i.key === key))
    .filter(Boolean);
});

const filteredSections = computed(() => {
  if (!searchQuery.value.trim()) return sections.value;
  const q = searchQuery.value.toLowerCase();
  return sections.value
    .map(section => ({
      ...section,
      items: section.items.filter(i =>
        i.label.toLowerCase().includes(q) ||
        i.description.toLowerCase().includes(q)
      ),
    }))
    .filter(s => s.items.length > 0);
});

// Sub-agrupamento da categoria "rewrite"
const REWRITE_SUBGROUPS = {
  polish:   { label: t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.SUBGROUPS.POLISH'),  keys: ['improve', 'fix_spelling_grammar'] },
  tone:     { label: t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.SUBGROUPS.TONE'),    keys: ['professional', 'friendly', 'casual', 'confident', 'straightforward'] },
  size:     { label: t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.SUBGROUPS.SIZE'),    keys: ['shorten', 'expand'] },
};

const buildRewriteSubgroups = (rewriteItems) => {
  return Object.entries(REWRITE_SUBGROUPS).map(([key, group]) => ({
    key,
    label: group.label,
    items: group.keys.map(k => rewriteItems.find(i => i.key === k)).filter(Boolean),
  }));
};
```

### Substituir o `<template>` inteiro por:
```vue
<template>
  <DropdownBody
    ref="menuRef"
    class="min-w-[20rem] max-w-[22rem] z-50 [&>ul]:gap-0 [&>ul]:px-0 [&>ul]:py-0 origin-top motion-safe:animate-copilot-menu-in"
    :class="{
      'absolute ltr:left-[var(--selection-left)] rtl:right-[var(--selection-right)]':
        hasSelection && isEditorMenuPopover,
    }"
    :style="hasSelection && isEditorMenuPopover ? selectionMenuStyle : {}"
    role="menu"
    :aria-label="t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.MENU_LABEL')"
    @keydown="handleKeydown"
  >
    <div class="flex flex-col">
      <!-- Search -->
      <div class="px-3 py-2 border-b border-n-weak">
        <div class="relative">
          <span class="i-lucide-search absolute left-2.5 top-1/2 -translate-y-1/2 size-3.5 text-n-slate-10" />
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.SEARCH_PLACEHOLDER')"
            class="w-full reset-base pl-8 pr-2 py-1.5 text-xs bg-n-slate-2 border border-transparent rounded-md focus:outline-none focus:border-n-brand/50 focus:bg-n-solid-1 placeholder:text-n-slate-9 text-n-slate-12"
          >
        </div>
      </div>

      <!-- Promptbook (oculto durante search) -->
      <div v-if="!searchQuery && promptbookItems.length" class="px-2 pt-2 pb-1">
        <div class="px-2 py-1 text-[10px] font-semibold uppercase tracking-wider text-n-slate-10">
          {{ t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.QUICK_ACTIONS') }}
        </div>
        <div class="grid grid-cols-2 gap-1.5 px-1 pb-1">
          <button
            v-for="item in promptbookItems"
            :key="`pb-${item.key}`"
            v-tooltip="item.disabled && item.disabledTooltipKey ? t(item.disabledTooltipKey) : t(item.tooltipKey)"
            type="button"
            class="group flex items-start gap-2 p-2 rounded-lg border border-n-weak text-left transition-all duration-150"
            :class="item.disabled
              ? 'opacity-40 cursor-not-allowed'
              : 'cursor-pointer hover:border-n-brand/40 hover:bg-n-brand/5 motion-safe:hover:-translate-y-0.5'"
            :aria-disabled="item.disabled ? 'true' : 'false'"
            :tabindex="item.disabled ? -1 : 0"
            @click="handleMenuItemClick(item)"
          >
            <Icon :icon="item.icon" class="size-4 mt-0.5 shrink-0 text-n-brand" />
            <span class="text-xs font-medium text-n-slate-12 leading-tight">
              {{ item.label }}
            </span>
          </button>
        </div>
      </div>

      <!-- Sections -->
      <div class="flex flex-col py-1 max-h-[60vh] overflow-y-auto">
        <template v-for="(section, sectionIndex) in filteredSections" :key="section.id">
          <div v-if="sectionIndex > 0 || !searchQuery" class="mx-3 my-1 h-px bg-n-strong/40" aria-hidden="true" />

          <div class="px-4 pt-2 pb-1 text-[10px] font-semibold uppercase tracking-wider text-n-slate-10">
            {{ section.title }}
          </div>

          <!-- Rewrite com sub-grupos -->
          <template v-if="section.id === 'rewrite' && !searchQuery">
            <div
              v-for="subgroup in buildRewriteSubgroups(section.items)"
              :key="`sg-${subgroup.key}`"
              class="px-4 py-1.5"
            >
              <span class="text-[11px] font-medium text-n-slate-11 mb-1 block">{{ subgroup.label }}</span>
              <div class="flex flex-wrap gap-1.5">
                <button
                  v-for="item in subgroup.items"
                  :key="item.key"
                  :ref="el => setItemRef(item.key, el)"
                  v-tooltip="item.disabled && item.disabledTooltipKey ? t(item.disabledTooltipKey) : t(item.tooltipKey)"
                  type="button"
                  role="menuitem"
                  class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium transition-all duration-150"
                  :class="item.disabled
                    ? 'opacity-40 cursor-not-allowed border-n-weak text-n-slate-10'
                    : 'cursor-pointer border-n-weak text-n-slate-11 hover:border-n-brand/50 hover:bg-n-brand/10 hover:text-n-brand'"
                  :aria-disabled="item.disabled ? 'true' : 'false'"
                  :tabindex="item.disabled ? -1 : 0"
                  @click="handleMenuItemClick(item)"
                >
                  <Icon :icon="item.icon" class="size-3 shrink-0" />
                  {{ item.label }}
                </button>
              </div>
            </div>
          </template>

          <!-- Outras categorias OU busca ativa: lista padrão -->
          <template v-else>
            <button
              v-for="(item, itemIndex) in section.items"
              :key="item.key"
              :ref="el => setItemRef(item.key, el)"
              v-tooltip="item.disabled && item.disabledTooltipKey ? t(item.disabledTooltipKey) : t(item.tooltipKey)"
              type="button"
              role="menuitem"
              class="group flex w-full items-start gap-3 px-4 py-2 min-h-[40px] text-left transition-all duration-150 ease-out outline-none focus:ring-2 focus:ring-n-brand/40 focus:ring-inset"
              :class="item.disabled
                ? 'opacity-40 cursor-not-allowed'
                : 'cursor-pointer hover:bg-n-brand/5 active:bg-n-brand/10'"
              :aria-disabled="item.disabled ? 'true' : 'false'"
              :tabindex="item.disabled ? -1 : 0"
              :data-ai-tour="sectionIndex === 0 && itemIndex === 0 ? 'dropdown-first-item' : null"
              @click="handleMenuItemClick(item)"
            >
              <Icon
                :icon="item.icon"
                class="mt-0.5 size-4 shrink-0 text-n-slate-11 transition-colors duration-150"
                :class="{ 'group-hover:text-n-brand': !item.disabled }"
              />
              <div class="flex min-w-0 flex-1 flex-col gap-0.5">
                <span class="text-xs font-medium text-n-slate-12 leading-tight">{{ item.label }}</span>
                <span class="text-[11px] leading-snug text-n-slate-10">{{ item.description }}</span>
              </div>
            </button>
          </template>
        </template>

        <div v-if="filteredSections.length === 0" class="px-4 py-6 text-center text-xs text-n-slate-10">
          {{ t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.NO_RESULTS') }}
        </div>
      </div>

      <div class="mx-3 my-1 h-px bg-n-strong/40" aria-hidden="true" />

      <button
        :ref="el => setItemRef(askCopilotItem.key, el)"
        v-tooltip="t(askCopilotItem.tooltipKey)"
        type="button"
        role="menuitem"
        class="group mx-3 my-1 flex items-center justify-center gap-2 rounded-lg border border-dashed border-n-strong px-3 py-2 min-h-[40px] text-xs font-medium text-n-slate-11 transition-all duration-150 ease-out outline-none cursor-pointer hover:border-n-brand/50 hover:bg-n-brand/5 hover:text-n-brand"
        @click="handleMenuItemClick(askCopilotItem)"
      >
        <Icon :icon="askCopilotItem.icon" class="size-4 shrink-0" />
        <span>{{ askCopilotItem.label }}</span>
      </button>
    </div>
  </DropdownBody>
</template>
```

### i18n — adicionar
`pt_BR/conversation.json` em `INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS`:
```json
"SEARCH_PLACEHOLDER": "Buscar ação…",
"QUICK_ACTIONS": "Mais usadas",
"NO_RESULTS": "Nenhuma ação encontrada",
"SUBGROUPS": {
  "POLISH": "Polir",
  "TONE": "Mudar o tom",
  "SIZE": "Mudar o tamanho"
}
```

`en/conversation.json` (mesma estrutura, traduzido):
```json
"SEARCH_PLACEHOLDER": "Search action…",
"QUICK_ACTIONS": "Most used",
"NO_RESULTS": "No actions found",
"SUBGROUPS": {
  "POLISH": "Polish",
  "TONE": "Change tone",
  "SIZE": "Change length"
}
```

### Validação
- [ ] Search filtra em tempo real
- [ ] Promptbook 2x2 visível
- [ ] Categoria "rewrite" usa chips inline (não lista)
- [ ] Outras categorias mantêm formato lista
- [ ] Keyboard nav (↑↓ Enter Esc) funciona
- [ ] `data-ai-tour="dropdown-first-item"` preservado

---

## 🏗️ FASE 5 — Mensagens Enriquecidas

### 5.1 — `CopilotAssistantMessage.vue`

Adicionar barra de ações **abaixo** do bubble (depois do botão "Use" existente):

```vue
<div v-if="!hasEmptyMessageContent" class="flex items-center gap-1 mt-2 px-1 opacity-60 hover:opacity-100 transition-opacity">
  <button
    v-tooltip="$t('CAPTAIN.COPILOT.ACTIONS.COPY')"
    class="flex items-center justify-center size-6 rounded hover:bg-n-slate-3 text-n-slate-11"
    @click="copyToClipboard"
  >
    <span class="i-lucide-copy size-3.5" />
  </button>
  <button
    v-tooltip="$t('CAPTAIN.COPILOT.ACTIONS.GOOD')"
    class="flex items-center justify-center size-6 rounded hover:bg-n-slate-3 text-n-slate-11"
    :class="{ '!text-n-teal-10 !bg-n-teal-3': feedback === 'up' }"
    @click="setFeedback('up')"
  >
    <span class="i-lucide-thumbs-up size-3.5" />
  </button>
  <button
    v-tooltip="$t('CAPTAIN.COPILOT.ACTIONS.BAD')"
    class="flex items-center justify-center size-6 rounded hover:bg-n-slate-3 text-n-slate-11"
    :class="{ '!text-n-ruby-10 !bg-n-ruby-3': feedback === 'down' }"
    @click="setFeedback('down')"
  >
    <span class="i-lucide-thumbs-down size-3.5" />
  </button>
</div>
```

Adicionar ao `<script setup>`:
```js
import { ref } from 'vue';
import { useToast } from 'dashboard/composables/useToast';

const feedback = ref(null);
const { showToast } = useToast();

const copyToClipboard = async () => {
  try {
    await navigator.clipboard.writeText(props.message.content || '');
    showToast({ message: t('CAPTAIN.COPILOT.ACTIONS.COPIED'), type: 'success' });
  } catch (e) { /* noop */ }
};

const setFeedback = (val) => {
  feedback.value = feedback.value === val ? null : val;
  // TODO backend: emit('feedback', { messageId: props.message.id, value: feedback.value })
};
```

> **NOTE:** Se `useToast` não existir no projeto, usar `emitter.emit('newToastMessage', ...)` ou outro mecanismo de toast já presente. Buscar antes em `dashboard/helpers/`.

### i18n
`pt_BR/conversation.json` (em `CAPTAIN.COPILOT`):
```json
"ACTIONS": {
  "COPY": "Copiar",
  "COPIED": "Copiado!",
  "GOOD": "Boa resposta",
  "BAD": "Não ajudou"
}
```

`en/conversation.json`:
```json
"ACTIONS": {
  "COPY": "Copy",
  "COPIED": "Copied!",
  "GOOD": "Good answer",
  "BAD": "Not helpful"
}
```

### Validação
- [ ] Hover na mensagem do assistant: ações ficam mais visíveis
- [ ] Click em copy: toast "Copiado!"
- [ ] Click em 👍 ou 👎: ícone fica com cor sólida
- [ ] Click novamente no mesmo: desmarca

---

## 🏗️ FASE 6 — Input Convidativo

### Arquivo
`app/javascript/dashboard/components-next/copilot/CopilotInput.vue`

### Mudanças no `<template>`:
- Botão send com glow quando há texto
- Hint embaixo do input

```vue
<template>
  <div class="space-y-1.5">
    <form class="relative flex items-end gap-2" @submit.prevent="sendMessage">
      <textarea
        ref="textareaRef"
        v-model="message"
        :placeholder="$t('CAPTAIN.COPILOT.SEND_MESSAGE')"
        class="w-full reset-base bg-n-solid-1 ltr:pl-3 ltr:pr-3 rtl:pl-3 rtl:pr-3 py-2 text-sm border border-n-weak rounded-lg focus:outline-0 focus:outline-none focus:ring-1 focus:ring-n-brand/20 focus:border-n-brand/50 resize-none overflow-hidden max-h-[200px] mb-0 text-n-slate-12 placeholder:text-n-slate-9"
        rows="1"
        @input="handleInput"
        @keydown.enter.exact="handleEnterKey"
      />
      <button
        class="size-8 flex-shrink-0 flex items-center justify-center rounded-full text-white transition-all duration-200"
        :class="hasContent
          ? 'bg-n-brand hover:bg-n-brand-hover shadow-md shadow-n-brand/30'
          : 'bg-n-brand/40 cursor-not-allowed'"
        :disabled="!hasContent"
        type="submit"
      >
        <i class="i-lucide-send-horizontal size-4" />
      </button>
    </form>
    <p class="text-[10px] text-n-slate-9 px-1">
      {{ $t('CAPTAIN.COPILOT.INPUT_HINT') }}
    </p>
  </div>
</template>
```

Adicionar ao `<script setup>`:
```js
import { computed } from 'vue';
const hasContent = computed(() => message.value.trim().length > 0);
```

### i18n
`pt_BR`: `"INPUT_HINT": "Enter para enviar · Shift+Enter para quebrar linha"`
`en`: `"INPUT_HINT": "Enter to send · Shift+Enter for new line"`

### Validação
- [ ] Botão acinzentado quando vazio
- [ ] Botão verde com sombra quando tem texto
- [ ] Hint visível abaixo

---

## 🏗️ FASE 7 — Launcher com Pulse

### Arquivo
`app/javascript/dashboard/components-next/copilot/CopilotLauncher.vue`

### Trocar a `class` do `ButtonGroup` por:
```vue
<ButtonGroup
  class="rounded-full bg-n-brand/90 backdrop-blur-lg p-1 shadow-lg hover:shadow-xl transition-shadow ai-launcher-pulse"
>
```

### Validação
- [ ] Botão flutuante tem onda de pulse a cada ~2.4s
- [ ] `prefers-reduced-motion` desliga animação

---

## 🏗️ FASE 8 — Mobile Responsivo

### 8.1 — `CopilotMenuBar.vue` — Bottom sheet em mobile

Adicionar ao `<DropdownBody>`:
```html
class="... max-md:fixed max-md:bottom-0 max-md:left-0 max-md:right-0 max-md:rounded-t-2xl max-md:rounded-b-none max-md:max-w-full max-md:min-w-full max-md:max-h-[80vh]"
```

Adicionar handle visual no topo (em mobile):
```vue
<div class="md:hidden flex justify-center pt-2 pb-1">
  <div class="w-10 h-1 rounded-full bg-n-slate-6" />
</div>
```

### 8.2 — `Copilot.vue` (painel) — gestures swipe-to-close *(opcional)*

Pode ser deixado pra Sprint posterior. Painel já fecha pelo botão X.

### Validação
- [ ] Em mobile (<768px): menu sobe de baixo com handle
- [ ] Cobre 80% da altura
- [ ] Tap no handle não faz nada (visual só)
- [ ] Em desktop: comportamento original (dropdown)

---

## ✅ Checklist Final de Aceite

Após todas as fases:

- [ ] `pnpm eslint` passa sem novos erros
- [ ] `RAILS_ENV=production bundle exec rake assets:precompile` exit 0
- [ ] `sudo systemctl restart chatwoot.target` aplicado
- [ ] Visual em https://chatspx.app/app/login — abrir conversa, testar:
  - [ ] Empty state: 3 cards, avatar com glow
  - [ ] Header: avatar + bolinha verde + "Pronto pra ajudar"
  - [ ] Enviar mensagem: loader sparkles + shimmer (não 3 dots)
  - [ ] Resposta do assistant: ações copy/👍/👎 visíveis
  - [ ] Input: botão verde quando tem texto, hint abaixo
  - [ ] Botão IA no editor: dropdown com search + promptbook 2x2 + chips inline
  - [ ] Editor "Melhorar": logo Captain com glow (não pulando)
  - [ ] Launcher flutuante: pulse sutil
- [ ] Dark mode: tudo legível
- [ ] Mobile (DevTools 375px): bottom sheet aparece corretamente
- [ ] i18n: textos em pt_BR e en aplicados

---

## 🚨 Restrições Operacionais

1. **Branch:** `homologacao` (verificar com `git branch --show-current`)
2. **NUNCA** fazer push sem confirmação do usuário
3. **NUNCA** mergear pra `producao`
4. **NUNCA** rodar `git reset --hard` ou `git push --force`
5. Commit msgs: Conventional Commits (`feat(copilot): ...`)
6. Build com `RAILS_ENV=production` é seguro (esta VM 192.168.8.232 = homologação)
7. Restart: `sudo systemctl restart chatwoot.target`
8. Antes de cada fase: ler arquivos atuais com `Read` (não confiar em diffs antigos)
9. Após cada fase: `git status` pra confirmar arquivos alterados
10. Testes Vue (specs): apenas se a fase modificar lógica — visual puro não precisa

---

## 🗂️ Divisão por Squad

Trabalho em **4 sprints** ordenados. Cada sprint é uma "missão" independente.

| Sprint | Fases | Tempo | Quem (especialização) |
|--------|-------|:-----:|----------------------|
| **A — Fundação + Visual** | 0, 1, 2 | ~2h | UI/UX Vue dev |
| **B — UX Crítico** | 3, 4 | ~2h30 | Frontend dev sênior |
| **C — Polish** | 5, 6, 7 | ~1h45 | UI/UX Vue dev |
| **D — Mobile** | 8 | ~45min | Mobile/responsive specialist |

Cada sprint **pode ser executado em paralelo** se rodando em worktrees separados (vide CLAUDE.md "Codex Worktree Workflow"). Em chat único, executar **sequencialmente Sprint A → B → C → D**.

---

## 📝 Log obrigatório

Ao finalizar cada fase, append em `prompts/copilot-redesign/EXECUTION-LOG.md`:
```
## Fase X — <Nome>
- ✅ ou ❌
- Arquivos modificados: [...]
- Build: exit code
- Notas: <qualquer issue>
- Timestamp: ISO 8601
```

Ao final de tudo, criar `prompts/copilot-redesign/FINAL-REPORT.md` com sumário visual e capturas de comparação.

---

**FIM DO PLANO. Tudo aqui é executável. Não pause pra perguntar — só execute na ordem.**
