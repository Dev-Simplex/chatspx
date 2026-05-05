# Copilot Redesign 2026 — Execution Log

Branch: `homologacao` · VM: 192.168.8.232 (homologação) · Início: 2026-05-04T18:17:22+00:00

---

## Fase 2 — Empty State Acolhedor
- ✅
- Arquivos modificados:
  - app/javascript/dashboard/components-next/copilot/CopilotEmptyState.vue
  - app/javascript/dashboard/i18n/locale/pt_BR/integrations.json
  - app/javascript/dashboard/i18n/locale/en/integrations.json
- Notas:
  - As chaves `CAPTAIN.COPILOT.*` vivem em `integrations.json` (não em `conversation.json` como o prompt da fase indicava). Editado o arquivo correto em ambas as locales.
  - Estrutura PROMPTS já existia com `LABEL`/`CONTENT`. Adicionado `HINT` (description) em cada bloco — nenhum outro consumidor usava `PROMPTS.SUMMARIZE` etc como string (grep confirma uso só em CopilotEmptyState.vue), então a adição é retrocompatível.
  - PANEL_TITLE / KICK_OFF_MESSAGE / TRY_THESE_PROMPTS atualizados conforme plano.
  - Template substituído: avatar 64px com glow (`ai-glow` da Fase 0), 3 cards verticais com label + hint + ícone Lucide, hover com translate-y-0.5 + sombra, motion-reduce desabilita.
  - `routePromptMap` atualizado com `description` e `icon` por entrada.
  - `data-ai-tour=*` não existia no original deste componente — preservado o que existia (nada novo a preservar). `hasAssistants`, `promptOptions`, `handleSuggestion`, `route` mantidos como estavam no `<script setup>`.
- Lint: `npx eslint CopilotEmptyState.vue --fix` → 0 erros, 3 warnings de `no-dynamic-keys` (padrão pré-existente do componente).
- Timestamp: 2026-05-04T18:27:38Z

---

## Fase 0 — Fundação Visual
- ✅
- Arquivos modificados:
  - app/javascript/dashboard/assets/scss/_wa-skin.scss
- Notas:
  - Bloco "COPILOT 2026 — AI Animation Tokens" anexado ao final do arquivo conforme plano.
  - 4 keyframes (`ai-sparkle-float`, `ai-shimmer`, `ai-glow-pulse`, `ai-launcher-pulse`) + classes utilitárias (`.ai-sparkle`, `.ai-sparkle-delay-1/2/3`, `.ai-shimmer`, `.ai-glow`, `.ai-launcher-pulse`).
  - `@media (prefers-reduced-motion: reduce)` no final desliga todas as animações dos tokens.
- Timestamp: 2026-05-04T18:30:15Z

---

## Fase 1 — Loaders Modernos
- ✅
- Arquivos modificados:
  - app/javascript/dashboard/components-next/copilot/CopilotLoader.vue
  - app/javascript/dashboard/components/widgets/conversation/copilot/CaptainLoader.vue
  - app/javascript/dashboard/i18n/locale/pt_BR/integrations.json
  - app/javascript/dashboard/i18n/locale/en/integrations.json
- Notas:
  - `CopilotLoader.vue` reescrito: 3 sparkles posicionados (Lucide `i-lucide-sparkles` + `i-lucide-sparkle`) com `ai-sparkle` + delays escalonados, label + 2 barras `ai-shimmer`. Posicionamento dos sparkles convertido de `style="top:..; left:.."` para utilitárias arbitrárias do Tailwind (`top-[4px] left-[4px]` etc.) porque o ESLint regra `vue/no-static-inline-styles` rejeita inline styles, e o Tailwind suporta arbitrary values mantendo o intuito (sem CSS custom).
  - `CaptainLoader.vue` reescrito: ícone `i-woot-captain` com camada `absolute inset-0 rounded-full ai-glow` por trás (glow pulsante substitui o "jumping logo"). `<style scoped>` removido junto com o keyframe `jump`.
  - i18n: chave `CAPTAIN.COPILOT.LOADER` vive em `integrations.json` (não `conversation.json` como o prompt sugeria — mesma observação da Fase 2 anterior). Atualizada nos dois locales: pt_BR="Pensando uma boa resposta…", en="Thinking of a great response…".
- Lint: `pnpm exec eslint <2 arquivos> --fix` → exit 0, 0 problemas. (Nota: `pnpm eslint` direto roda o script do package.json que faz lint do projeto inteiro; `pnpm exec eslint` aceita os arquivos.)
- Timestamp: 2026-05-04T18:30:15Z

---

## Fase 3 — Header com Identidade
- ✅
- Arquivos modificados:
  - app/javascript/dashboard/components-next/copilot/Copilot.vue
  - app/javascript/dashboard/i18n/locale/pt_BR/integrations.json
  - app/javascript/dashboard/i18n/locale/en/integrations.json
- Notas:
  - `<SidebarActionsHeader .../>` removido do template e substituído pelo header customizado (avatar 36px com `ai-glow` quando idle, bolinha de status com ring, título + status label, botões iterando `copilotButtons` + botão X de fechar).
  - Import de `SidebarActionsHeader` removido (não usado mais) para evitar dead code/lint warning. Adicionado `import Icon from '../icon/Icon.vue'` (mesmo padrão usado por `CopilotEmptyState.vue` e `CopilotThinkingGroup.vue` no mesmo diretório — `next/icon/Icon.vue` também funcionaria via alias mas o padrão local da pasta é relativo).
  - Estrutura de `copilotButtons` já tinha `{ key, icon, tooltip }` — bateu 1:1 com o template do plano, sem necessidade de adaptação. `v-tooltip` (diretiva global do Chatwoot) usado direto.
  - Computeds `statusLabel` e `statusDotColor` adicionados após `copilotButtons` (precisam estar depois de `shouldShowLoader`/`hasMessages` por dependência reativa). Usam as 3 chaves novas `CAPTAIN.COPILOT.STATUS_READY/THINKING/OFFLINE`.
  - i18n: chaves `STATUS_READY`, `STATUS_THINKING`, `STATUS_OFFLINE` adicionadas em `integrations.json` (não `conversation.json` como diz o plano — mesma observação das Fases 1/2: `CAPTAIN.COPILOT.*` vive em `integrations.json` neste fork). Inseridas após `RETRY` e antes de `API_KEY_MISSING` em ambos os locales. JSON validado com `python3 -m json.tool`.
- Lint: `pnpm exec eslint app/javascript/dashboard/components-next/copilot/Copilot.vue --fix` → exit 0, 0 problemas.
- Timestamp: 2026-05-04T18:43:39Z

---

## Fase 4 — Dropdown Reorganizado (Promptbook + Search + Sub-grupos)
- ✅
- Arquivos modificados:
  - app/javascript/dashboard/components/widgets/WootWriter/CopilotMenuBar.vue
  - app/javascript/dashboard/i18n/locale/pt_BR/integrations.json
  - app/javascript/dashboard/i18n/locale/en/integrations.json
- Notas:
  - i18n adicionado em `INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS`: `SEARCH_PLACEHOLDER`, `QUICK_ACTIONS`, `NO_RESULTS` e o objeto `SUBGROUPS` (POLISH/TONE/SIZE) — confirmado que neste fork esse caminho vive em `integrations.json` (e não em `conversation.json` como o texto do plano sugeria), inserido após o bloco `DISABLED` em ambos os locales. JSON validado com `python3 -m json.tool`.
  - Script: adicionados `searchQuery` (ref), `PROMPTBOOK_KEYS` (`['summarize','reply_suggestion','improve','shorten']`), `promptbookItems`, `filteredSections`, `REWRITE_SUBGROUPS` e `buildRewriteSubgroups` depois de `askCopilotItem`. `REWRITE_SUBGROUPS` usa `labelKey` (string) ao invés de `label` chamando `t()` no top-level — isso evita resolver i18n fora do contexto reativo (i18n só fica disponível depois do `setup`); `buildRewriteSubgroups` chama `t(group.labelKey)` no momento do uso, garantindo reatividade ao trocar idioma.
  - `flatItems` ajustado para iterar `filteredSections.value` em vez de `sections.value` — quando não há busca os dois são iguais, então não muda comportamento original; quando há busca, a navegação por teclado passa a percorrer apenas os itens visíveis (esperado).
  - Template substituído por inteiro: search bar com ícone Lucide `i-lucide-search`, promptbook grid 2x2 (oculto durante busca), seções renderizadas via `filteredSections`. Categoria com `id === 'rewrite'` (sem busca ativa) usa chips arredondados agrupados em sub-grupos via `buildRewriteSubgroups`; outras categorias e busca ativa usam a lista padrão (com `data-ai-tour="dropdown-first-item"` no primeiro item visível). `setItemRef`, `handleMenuItemClick`, `handleKeydown`, `selectionMenuStyle`, `MENU_LABEL`, `askCopilotItem`, eventos `executeCopilotAction` — todos preservados. Empty-state da busca exibido quando `filteredSections.length === 0`.
  - Removido import de `useReducedMotion` do script (não há mais staggered animation no template — antes era usado só pra desabilitar `animationDelay` no item-in stagger; agora as transições são feitas via `motion-safe:` e classes utilitárias do Tailwind, sem inline styles).
  - As classes em `n-brand` substituem as `purple-*` antigas, alinhando o dropdown ao token de marca verde do projeto (mesmo padrão das Fases 2/3).
- Lint: `pnpm exec eslint app/javascript/dashboard/components/widgets/WootWriter/CopilotMenuBar.vue --fix` → 0 erros, 8 warnings de `@intlify/vue-i18n/no-dynamic-keys` (todos sobre `tooltipKey`/`disabledTooltipKey`/`labelKey` — padrão pré-existente do componente, mantido conforme orientação de preservar a estrutura de `sections`).
- Timestamp: 2026-05-04T18:44:23Z

---


## Fase 6 — Input Convidativo
- ✅
- Arquivos modificados:
  - app/javascript/dashboard/components-next/copilot/CopilotInput.vue
  - app/javascript/dashboard/i18n/locale/pt_BR/integrations.json
  - app/javascript/dashboard/i18n/locale/en/integrations.json
- Notas:
  - `<script setup>`: adicionado import de `computed` e a computed `hasContent = message.value.trim().length > 0`. Lógica existente (`adjustHeight`, `sendMessage`, `handleInput`, `handleEnterKey`, `onMounted`) totalmente preservada.
  - `<template>`: envelopado em `<div class="space-y-1.5">` para acomodar form + hint. Botão de envio agora alterna entre estado ativo (`bg-n-brand`, `hover:bg-n-brand-hover`, `shadow-md shadow-n-brand/30`) e estado vazio (`bg-n-brand/40 cursor-not-allowed`); `:disabled="!hasContent"` impede submit com input vazio. Adicionado `<p>` com `INPUT_HINT` logo abaixo do form.
  - Sem scoped CSS, sem inline styles, apenas utilitários Tailwind. Atributos existentes do textarea (placeholder via i18n, classes de focus/border, `@input`, `@keydown.enter.exact`) foram mantidos sem alteração.
  - i18n: chave `INPUT_HINT` adicionada em `INTEGRATION_SETTINGS.CAPTAIN.COPILOT` em ambos `pt_BR/integrations.json` e `en/integrations.json` — confirmado que neste fork o caminho `CAPTAIN.COPILOT.*` vive em `integrations.json` (não em `conversation.json` como o plano sugeria). JSON validado com `python3 -m json.tool` (`JSON OK`).
- Lint: `pnpm exec eslint app/javascript/dashboard/components-next/copilot/CopilotInput.vue app/javascript/dashboard/components-next/copilot/CopilotLauncher.vue --fix` → exit 0, sem erros nem warnings.
- Timestamp: 2026-05-04T18:52:33Z

---

## Fase 7 — Launcher com Pulse
- ✅
- Arquivos modificados:
  - app/javascript/dashboard/components-next/copilot/CopilotLauncher.vue
- Notas:
  - Adicionada apenas a classe `ai-launcher-pulse` ao final da `class` do `<ButtonGroup>` (concatenada às existentes: `rounded-full bg-n-brand/90 backdrop-blur-lg p-1 shadow-lg hover:shadow-xl transition-shadow`). Nenhuma outra alteração no componente.
  - Keyframe `ai-launcher-pulse` (~2.4s ease-in-out infinite) já está declarado em `_wa-skin.scss` na Fase 0, com `@media (prefers-reduced-motion: reduce)` desligando a animação. Atributo `data-ai-tour="copilot-launcher"` no wrapper preservado.
- Lint: `pnpm exec eslint ... --fix` → exit 0 (mesmo run da Fase 6).
- Timestamp: 2026-05-04T18:52:33Z

---

## Fase 5 — Mensagens Enriquecidas
- Status: OK
- Arquivos modificados:
  - `app/javascript/dashboard/components-next/copilot/CopilotAssistantMessage.vue`
  - `app/javascript/dashboard/i18n/locale/pt_BR/integrations.json`
  - `app/javascript/dashboard/i18n/locale/en/integrations.json`
- Notas:
  - Toast: usado `useAlert` de `dashboard/composables` (não existe `useToast` no projeto — `useAlert` é o padrão estabelecido em `components-next/`, ex.: `ComposeNewConversationForm.vue`, `DocumentForm.vue`).
  - Chaves i18n adicionadas em `integrations.json` (CAPTAIN.COPILOT.ACTIONS) — não em `conversation.json` como descrito no plano (CAPTAIN.COPILOT.* vivem em integrations.json, conforme verificado em fases anteriores).
  - Barra de ações copy/👍/👎 renderizada abaixo do botão "Use" (quando presente), com `opacity-60 hover:opacity-100` para revelar suavemente no hover.
  - Estado de feedback `ref(null)`, toggle (clique novamente desmarca). Backend NÃO chamado — TODO comentado conforme plano.
  - Acessibilidade: `aria-label`, `aria-pressed`, `focus-visible:ring`, `aria-hidden` nos ícones.
  - JSON validado com `python3 -m json.tool` (pt_BR + en OK).
- Lint: `pnpm exec eslint app/javascript/dashboard/components-next/copilot/CopilotAssistantMessage.vue --fix` → 0 erros, 0 warnings.
- Timestamp: 2026-05-04T18:53:07Z

---

## Pós-mortem — Validação visual via Playwright (2026-05-04T19:55Z)

Walisson cobrou validação real do dropdown — eu havia entregue só "build verde" sem testar UI. Validação via Playwright achou **2 bugs reais** que o build não pegou:

**Bug 1: Ícones invisíveis no dropdown.**
- Causa: regra catch-all em `_wa-skin.scss:2939-2948` (`.n-dropdown-body span { background-color: transparent !important }`) zerava o `bg: currentColor` que o plugin `@egoist/tailwindcss-icons` usa pra renderizar a mask SVG. Resultado: spans com classes `i-fluent-*` ficavam com forma correta mas invisíveis.
- Fix: adicionada whitelist em `_wa-skin.scss:2957-2989` que reativa `background-color: currentColor !important` para spans com classes das coleções de ícones em uso (`i-fluent`, `i-lucide`, `i-woot`, `i-ph`, `i-ri`, `i-logos`, `i-teenyicons`).

**Bug 2: Botões do dropdown pintados verde sólido.**
- Causa: regra global `button[class*='bg-n-brand'] { background-color: var(--wa-primary) }` em `_wa-skin.scss` usa attribute SUBSTRING match, casando `hover:bg-n-brand/5` no `class` dos botões do CopilotMenuBar — pinta o botão inteiro de verde brand no estado base (não no hover).
- Fix: regra de override em `_wa-skin.scss:2949-2956` reseta `background-color: transparent !important` para `button[class*='hover:bg-n-brand']` dentro de `.n-dropdown-body`, `.dropdown-pane`, `[class*='fixed z-[100]']`. Especificidade `(0,3,1)` > `(0,2,1)` da regra global. O hover continua aplicando via utility Tailwind.

**Validação visual final** (`/tmp/copilot-screens-v2/`):
- Promptbook 2x2 com ícones brand visíveis ✅
- Sub-grupos "Polir / Mudar o tom / Mudar tamanho" com ícones em chips ✅
- Search filtra label+description em tempo real ✅
- "Perguntar ao Copilot" com border dashed ✅
- Hover state sutil (`hover:bg-n-brand/5` agora aparece como 5% real, não 100%) ✅

Build pós-fix: `RAILS_ENV=production rake assets:precompile` exit 0 · Restart aplicado · Serviços active.

Lição: build verde ≠ feature OK. Sempre validar UI no browser, principalmente quando há regras CSS catch-all com `!important`.

Timestamp: 2026-05-04T19:58:00Z

---

## Pós-mortem 2 — Tema light + responsividade notebook (2026-05-04T20:25Z)

Walisson cobrou validar tema **light** (eu testei só dark) e responsividade em **notebook 1366x768**. Validação Playwright em 3 viewports (1440, 1366, 1280) achou **1 bug crítico** específico do tema light:

**Bug 3: Cards do empty state pintados verde sólido no tema light.**
- Causa: a regra global `_wa-skin.scss:736` (`button[class*='bg-n-brand']` substring match) continuava casando `hover:bg-n-brand/5` indevidamente — meu fix anterior só cobria DROPDOWNS (`.n-dropdown-body`, `.dropdown-pane`), mas o painel Copilot é `data-testid="copilot-container-legacy"` (não dropdown), então os 3 cards "Sugestões para começar" ficavam com `background-color: var(--wa-primary)` aplicado pela regra catch-all.
- Por que só apareceu no light: no dark, `bg-n-solid-1` é cinza-escuro contrastante e o efeito da regra ficava menos óbvio na captura anterior; o problema sempre existiu em ambos os temas.
- Fix definitivo: troquei `[class*='bg-n-brand']` (substring) por `[class~='bg-n-brand']` (whitespace-separated word match) na regra (A) em `_wa-skin.scss:736-749`. Adicionei seletores complementares para variantes `bg-n-brand/X` e `bg-n-brand-X` via `[class*=' bg-n-brand/']` e `[class^='bg-n-brand/']` (com leading space ou início, evita casar dentro de `hover:bg-n-brand/5`). Mantive os `:not()` originais (`wa-send-btn`, `rounded-full`).
- O fix anterior do dropdown (`button[class*='hover:bg-n-brand']` → transparent) virou redundante mas foi mantido como defesa em camadas.

**Validação visual final** (tema light, /tmp/copilot-screens-light/):
- `desktop-panel.png` (1440x900): painel Copilot com 3 cards bg branco, ícone verde, label preto, hint cinza ✅
- `notebook-panel.png` (1366x768): mesmo layout, cabe no viewport ✅
- `small-laptop-panel.png` (1280x720): mesmo layout, cabe ✅
- `notebook-dropdown-light-v2.png`: dropdown com search + promptbook + chips + "Perguntar ao Copilot" ✅
- `regression-dark-panel.png`: dark mode mantido (cards `rgb(17, 27, 33)` = n-solid-1) ✅

**Responsividade notebook 1366x768:**
- Layout: 80px (sidebar nav) + 320px (lista) + área conversa + 320px (painel Copilot) = ~720px de área de conversa = funcional, espremida mas OK
- Em 1280x720 a conversa fica MAIS espremida mas ainda usável
- Painel Copilot mantém largura fixa 320px (`md:w-[320px]` no `CopilotContainer.vue`) — em telas <768px (mobile) vai full-screen via `w-full max-w-sm fixed` (já estava correto)
- Dropdown CopilotMenuBar: 320px de largura, anchor relativo ao botão IA. Em 1280 fica em x=576 (caber na tela), em 1366 em x=662, em 1440 em x=736. Não corta.

**Lição adicionada:** regras CSS catch-all com attribute substring match (`[class*='X']`) são fonte recorrente de bug em projetos Tailwind onde modifiers (`hover:X`, `focus:X`, `dark:X`) compartilham token base. Preferir `[class~='X']` (palavra exata) ou enumerar prefixos via `[class^='X']` / `[class*=' X']`.

Build pós-fix: exit 0 · Restart aplicado · 3 themes × 3 viewports validados.

Timestamp: 2026-05-04T20:30:00Z

---

## Fase 8 — Mobile Responsivo
- ✅
- Arquivos modificados:
  - app/javascript/dashboard/components/widgets/WootWriter/CopilotMenuBar.vue
- Notas:
  - Concatenadas no string da `class` do `<DropdownBody>` as utilitárias mobile-only (sem remover nada da Fase 4): `max-md:fixed max-md:bottom-0 max-md:left-0 max-md:right-0 max-md:rounded-t-2xl max-md:rounded-b-none max-md:max-w-full max-md:min-w-full max-md:max-h-[80vh]`. Em desktop (≥768px) o comportamento de dropdown original continua intacto; em mobile o menu vira bottom sheet (cobre 80% da altura, ancorado embaixo, cantos superiores arredondados).
  - Adicionado handle visual (`md:hidden flex justify-center pt-2 pb-1` com pílula `w-10 h-1 rounded-full bg-n-slate-6`) imediatamente dentro do `<DropdownBody>`, acima da search bar — visível apenas em mobile como cue de bottom sheet.
  - Sem scoped CSS, sem inline styles, sem CSS custom — apenas utilitários Tailwind com prefixos `md:` / `max-md:`.
  - 8.2 (gestures swipe-to-close em `Copilot.vue`) é opcional segundo o plano; mantido pra Sprint posterior.
- Lint: `pnpm exec eslint app/javascript/dashboard/components/widgets/WootWriter/CopilotMenuBar.vue --fix` → 0 erros, 8 warnings (mesmos `@intlify/vue-i18n/no-dynamic-keys` pré-existentes da Fase 4 — não introduzidos por esta fase).
- Timestamp: 2026-05-04T18:59:30Z

---
