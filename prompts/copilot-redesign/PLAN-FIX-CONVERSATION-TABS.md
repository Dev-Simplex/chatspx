# Fix — Tabs Minhas / Não atribuídas / Todos (overflow invisível)

> Status: análise / proposta. Nenhum código foi alterado.
> Branch: `homologacao` · Reportado por: Walisson · Reproduzido visualmente em notebook 1366px.

---

## Sintoma

Na lista de conversas, a aba "Todos" pode ficar parcialmente cortada (clipada à direita) em
viewports tipo notebook (1366px ou menor), especialmente quando os badges crescem para 2-3 dígitos
(`Minhas 2`, `Não atribuídas 35`, `Todos 55+`). Como o container usa
`overflow-x-auto` com a utility `.no-scrollbar`, o conteúdo é roláveis, mas:

- não há barra de rolagem visível (utility esconde via `scrollbar-width: none` + `::-webkit-scrollbar { display: none }`)
- não há gradiente, fade ou seta indicando overflow nesse viewport
- o usuário não percebe que pode arrastar/scrollar para ver "Todos"

Resultado: a tab parece "quebrada" — só metade aparece, e clicar nela é impossível porque a área
da label está fora da viewport.

HTML atual (renderizado por `Tabs.vue`):

```html
<div class="wa-tabs flex items-center w-full">
  <ul class="flex items-center gap-1.5 px-3 py-1.5 list-none mb-0
             overflow-x-auto no-scrollbar flex-1 min-w-0">
    <li><button class="wa-tab-item ...">Minhas <span>2</span></button></li>
    <li><button class="wa-tab-item ...">Não atribuídas <span>35</span></button></li>
    <li><button class="wa-tab-item ...">Todos <span>55</span></button></li>
  </ul>
</div>
```

---

## Diagnóstico (causa raiz)

### Componente

- Arquivo: `app/javascript/dashboard/components/ui/Tabs/Tabs.vue` (`<woot-tabs>`)
- Filho: `app/javascript/dashboard/components/ui/Tabs/TabsItem.vue` (`<woot-tabs-item>`)
- Wrapper de uso: `app/javascript/dashboard/components/widgets/ChatTypeTabs.vue` (passa `items` com
  `name`, `count`, `icon`)
- Consumidor: `app/javascript/dashboard/components/ChatList.vue` linha ~221 (`assigneeTabItems`)

### CSS envolvido

- `.wa-tab-item` em `app/javascript/dashboard/assets/scss/_wa-skin.scss:2421`
  - `padding-inline: 10px; height: 28px; font-size: 13px;`
- Container `<ul>`: `flex items-center gap-1.5 px-3 py-1.5 ... overflow-x-auto no-scrollbar flex-1 min-w-0`
- Utility `.no-scrollbar`: declarada em **dois** lugares:
  - `app/javascript/dashboard/assets/scss/_woot.scss:67` (dentro de `@layer utilities`)
  - `app/javascript/dashboard/assets/scss/_base.scss:4` (top-level)
  - Resultado: scrollbar nativa removida em todos os browsers.

### Lógica de scroll já existe (parcial)

`Tabs.vue` JÁ tem chevrons `‹›` controlados por `hasScroll`:

```js
hasScroll.value = tabsList.value.scrollWidth > tabsList.value.clientWidth + 20;
```

Os botões `‹` e `›` aparecem quando há overflow `> 20px`. Porém:

1. Em notebook 1366px, dependendo da sidebar lateral aberta, o painel de chat list fica em torno
   de **300-340px** de largura útil. Vamos calcular o pior caso:
   - `gap-1.5` (6px) entre itens + `px-3` no `<ul>` (12px cada lado) = `12 + 12 + 6 + 6 = 36px` overhead
   - Cada `wa-tab-item` com `padding-inline: 10px` + ícone 14px (`size-3.5`) + `mr-1.5` (6px)
     + label + badge `min-w-[18px] px-1.5 ml-1.5` (6+6+18 = 30px do badge)
   - "Minhas" (~50px texto) → ~120px total
   - "Não atribuídas" (~120px texto) → ~190px total
   - "Todos" (~50px texto) → ~120px total
   - Total: `36 + 120 + 190 + 120 = 466px`
   - Em 300-340px de container, sobra ~130-160px de overflow → chevrons DEVERIAM aparecer.

2. **Por que não aparecem (suspeita confirmada)?** O cálculo do `hasScroll` é feito após resize,
   mas o threshold de `+ 20` pode mascarar overflow pequeno. Mais grave: o ícone das tabs (`i-lucide-user`,
   `i-lucide-user-round-x`, `i-lucide-users`) faz cada label ainda maior, e o threshold ignora overflow
   < 20px — ainda assim, o caso descrito pelo Walisson tem overflow muito maior que isso, então o
   `hasScroll` deveria ativar. **Hipótese mais provável**: o container tem `flex-1 min-w-0` mas
   `tabsContainer` (o `div.wa-tabs`) está dentro de um wrapper sem `min-w-0` adequado em alguma
   profundidade da árvore (ex.: `ChatList.vue`), fazendo o flex parent estourar e o `clientWidth`
   reportar valor maior que o real visível na viewport, a chevron nunca aparece.

3. **Falta acessibilidade**: nem com chevron a tab cortada faz `scrollIntoView` quando recebe foco
   por teclado.

### Por que `.no-scrollbar` está aplicada

Decisão estética do redesign WhatsApp-fiel — barras horizontais nativas no Linux/Windows são
"feias" e quebram a estética limpa. Aceitável para listas verticais (sidebar), problemático
quando o conteúdo é navegável e não tem affordance alternativa.

---

## Opções propostas

### Opção A — Mostrar barra de scroll horizontal nativa

Remover `no-scrollbar` do `<ul>` em `Tabs.vue`.

- Trade-off: simples e funciona em 100% dos casos, mas barra horizontal nativa fica visível e
  destoa do skin WA-fiel; em macOS some quando idle, em Linux/Windows fica permanentemente.
- Esforço: **S**.

### Opção B — Gradiente fade + chevrons confiáveis

1. Corrigir o cálculo `hasScroll` (forçar recompute em `ResizeObserver` no documento e remover
   threshold `+20`).
2. Adicionar pseudo-elementos `::before/::after` no `.wa-tabs` com gradiente (white → transparent
   no light, surface → transparent no dark) com 16-24px de largura, controlados por classe
   `data-overflow-left` / `data-overflow-right` setadas via JS conforme `scrollLeft`.
3. Manter chevrons já existentes, mas só aparecerem em `:hover` no container (ou sempre, se
   acessibilidade prioriza).

- Trade-off: visual mais polido (estilo iOS/Material), preserva a estética do skin. Custo de JS
  para sincronizar fade com scroll. Não resolve sozinho mobile/touch (mas touch já tem swipe
  nativo via `overflow-x-auto`).
- Esforço: **M**.

### Opção C — Layout compacto (icon-only) quando overflow detectado

Se `tabsList.scrollWidth > clientWidth`, esconder a label e manter só ícone + badge,
com `aria-label` e tooltip.

- Trade-off: cabe sempre, mas perde clareza ("Não atribuídas" vira só um ícone) — pode confundir
  usuários novos. Requer testar tooltip em mobile/touch (não tem hover).
- Esforço: **M**.

### Opção D — Dropdown "Filtrar" em viewports estreitos

Em `< 1280px` (ou quando overflow detectado), colapsar as 3 tabs em um botão "Filtrar: Minhas"
com `<v-dropdown>` listando as opções.

- Trade-off: máxima compactação, libera espaço para outros controles. Custo: muda mental model
  do usuário (3 cliques visíveis viram 1 click + dropdown). Em desktop não compactar.
- Esforço: **L** (precisa dropdown novo, sincronizar contagens, manter atalhos `Alt+N`).

### Opção E — Reduzir gap/padding/font em viewports estreitos

Adicionar variantes responsivas: `xl:gap-1.5 lg:gap-1 md:gap-0.5`, `xl:px-3 lg:px-2`, `text-sm
lg:text-xs`, encolher badge para `min-w-[16px] h-4`.

- Trade-off: ganha 30-50px de espaço, suficiente para o caso do Walisson na maioria das vezes.
  Não resolve o caso extremo (badges 4 dígitos, label localizada longa). Acumula com B sem custo.
- Esforço: **S**.

### Opção F — IntersectionObserver por tab (precisão cirúrgica)

Observar cada `<li>` e ativar fade/chevron lateral só quando uma tab está parcialmente fora.
Pode marcar a tab cortada com `data-clipped="true"` e estilizá-la (ex.: `box-shadow`
indicando recorte).

- Trade-off: solução elegante e precisa, mas exige IO em cada tab e re-observação a cada update
  do conteúdo. Overkill para 3 tabs fixas.
- Esforço: **M-L**.

---

## Acessibilidade

Independente da opção visual, três coisas precisam acontecer:

1. **Foco rola para a tab focada**:

   ```js
   const onTabFocus = e => e.target.scrollIntoView({ inline: 'nearest', block: 'nearest' });
   ```

   Aplicar no `<button>` em `TabsItem.vue` (`@focus="onTabFocus"`).

2. **ARIA**: o `<ul>` deveria ter `role="tablist"`, cada `<button>` `role="tab"` +
   `aria-selected="true|false"` + `aria-controls="<panel-id>"`. O componente atualmente não tem
   isso. Adicionar como parte do fix.

3. **Touch swipe**: já funciona via `overflow-x-auto` (browsers móveis fazem swipe nativo).
   Apenas confirmar que `touch-action: pan-x` está implícito (default é `auto`, ok).

4. **Teclado**: `ArrowLeft`/`ArrowRight` deveriam navegar entre tabs (padrão WAI-ARIA Tabs
   pattern). Hoje só há `Alt+N` cyclar tabs em `ChatTypeTabs.vue`.

5. **Reduced motion**: `tabsList.scrollTo({ behavior: 'smooth' })` deveria respeitar
   `prefers-reduced-motion: reduce` → trocar para `'instant'`.

---

## Recomendação

**Combinação B + E + acessibilidade** (acessibilidade é não-negociável):

1. Corrigir cálculo `hasScroll` (remover threshold `+20`, adicionar `ResizeObserver` no
   `document` para reagir a abrir/fechar sidebar). Garantir que chevrons aparecem sempre que há
   overflow real.
2. Adicionar **gradiente fade** nas bordas do `.wa-tabs ul` (16px) que aparece via classe sincronizada
   com `scrollLeft` e `scrollWidth - clientWidth - scrollLeft`. Mantém estética WA, dá pista
   visual clara mesmo sem chevron clicado.
3. **Reduzir gap/padding em `< 1280px`**: `lg:gap-1 lg:[&_ul]:px-2`, garantindo que no caso
   normal nem precise rolar.
4. **Acessibilidade**: `role="tablist"`/`role="tab"`/`aria-selected`, `scrollIntoView` no foco,
   `ArrowLeft/Right` para navegar.

Não recomendamos D (dropdown) porque muda mental model e perde quick-access. Não recomendamos C
(icon-only) porque "Não atribuídas" sem texto é ambíguo. F (IntersectionObserver) é overkill
para 3 itens.

### Mockup textual

```
Estado normal (cabe tudo):
┌─────────────────────────────────────────────────────────┐
│  [Minhas 2]  [Não atribuídas 35]  [Todos 55]            │
└─────────────────────────────────────────────────────────┘

Estado com overflow (notebook 1366, sidebar aberta):
┌──────────────────────────────────────────┐
│ ‹ [Minhas 2]  [Não atribuídas 35]  [Todo░│  ← fade + chevron à direita
└──────────────────────────────────────────┘
                    após scroll →
┌──────────────────────────────────────────┐
│░ihas 2]  [Não atribuídas 35]  [Todos 55] │  ← fade + chevron à esquerda
└──────────────────────────────────────────┘
```

---

## Validação proposta

Viewports a testar (Playwright + screenshot diff):

- **Mobile**: 375 (sidebar colapsada)
- **Tablet**: 768
- **Notebook small**: 1280, 1366 (caso do Walisson)
- **Desktop**: 1440, 1920

Casos de conteúdo:

1. 3 tabs com 1 dígito (`2 / 5 / 8`) — não deve aparecer chevron/fade.
2. 3 tabs com 2-3 dígitos (`12 / 35 / 999`) — chevron + fade quando overflow.
3. 3 tabs com 4 dígitos (`1234 / 5678 / 9999`) — chevron sempre, scroll funcionando.
4. Sidebar aberta + sidebar fechada (mudança de `clientWidth` em runtime).
5. Modo dark — gradiente deve usar surface dark, não white.
6. RTL (locale `he` ou `ar`) — fade lateral deve inverter (não aplica a pt-BR/en, mas vale
   testar para não regredir).
7. Teclado: Tab navega, ArrowLeft/Right entre tabs, `scrollIntoView` no foco.
8. Touch: swipe horizontal funciona em mobile (375 emulado).
9. `prefers-reduced-motion`: scroll vira instant.

---

## Arquivos afetados

Arquivos que serão modificados (sem mexer ainda — apenas listagem):

- `app/javascript/dashboard/components/ui/Tabs/Tabs.vue`
  - Corrigir `hasScroll` (remover threshold `+20`, adicionar `ResizeObserver`)
  - Adicionar estado `hasOverflowLeft` / `hasOverflowRight` ouvindo `scroll`
  - Renderizar pseudo-fade via classes `data-overflow-left`/`data-overflow-right`
  - Adicionar `role="tablist"` no `<ul>`
  - Variantes responsivas `lg:gap-1 lg:[&_ul]:px-2`

- `app/javascript/dashboard/components/ui/Tabs/TabsItem.vue`
  - `role="tab"`, `aria-selected`, `tabindex` dinâmico (0 ativo, -1 outros)
  - `@focus="scrollIntoView({ inline: 'nearest' })"`
  - `@keydown.left` / `@keydown.right` para navegar entre tabs

- `app/javascript/dashboard/assets/scss/_wa-skin.scss`
  - Adicionar `.wa-tabs` com `position: relative` + `::before`/`::after` para fade
  - Variantes light/dark do gradiente
  - Respeitar `prefers-reduced-motion`

- `app/javascript/dashboard/components/widgets/ChatTypeTabs.vue`
  - Possível ajuste do prop `is-compact` para refletir viewport (se decidirmos por C como
    fallback extremo). Por enquanto, sem mudança.

- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` / `en.json`
  - Sem mudanças de texto. (Apenas confirmar que labels não são absurdamente longas em outros
    locales — fora do escopo deste fix.)

Arquivos só de leitura/contexto (não tocar):

- `app/javascript/dashboard/components/ChatList.vue` (consumidor — `assigneeTabItems`)
- `app/javascript/dashboard/assets/scss/_base.scss` e `_woot.scss` (declarações `.no-scrollbar` —
  manter intactas; o fix usa o utility, não remove)

---

## Notas finais

- O CSS `.no-scrollbar` está duplicado (`_base.scss:4` e `_woot.scss:71`). Não é problema do
  bug, mas vale uma limpeza num PR separado.
- O componente `Tabs.vue` é genérico (`<woot-tabs>`). O fix beneficia todos os usos no app, não
  só a chat list. Verificar consumo via `grep -rn "<woot-tabs" app/javascript` antes do merge
  para confirmar que nenhum outro caso quebra com `role="tablist"` e nova navegação por seta.
