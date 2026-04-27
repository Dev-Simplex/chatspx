# Auditoria UI ChatSPX — WA-skin (findings + fixes aplicados)

Auditoria estática por @ux-design-expert (Alex). Base: branch `homologacao`, working tree.

---

## Fixes aplicados (5 fixes, working tree, sem commit)

| # | Arquivo | Mudança | Motivo |
|---|---|---|---|
| 1 | `app/javascript/dashboard/assets/scss/_wa-skin.scss` | Removida margem `6px` em placements `right/left` do `.v-popper__popper`; unificada para `margin: 0` em todos placements. | Distance agora vem do FloatingVue config global (`themes.tooltip.distance = 6`). A margem SCSS somava com o distance e afastava o tooltip do rail de 72px. |
| 2 | `app/javascript/dashboard/components/Snackbar.vue` | Variante default trocada de `bg-n-slate-12 dark:bg-n-slate-7` para `bg-[#233138]` fixo com `ring-1 ring-black/10 shadow-lg`. | `slate-7` em dark é um cinza médio (#4a5459), contraste fraco e alheio à paleta WA. `#233138` é o header-bg-dark do WA — consistente em light e dark, alto contraste com `text-white`. |
| 3 | `app/javascript/dashboard/components-next/Inbox/InboxCard.vue` | `transition-all duration-300 ease-in-out` → `transition-colors duration-150 ease-out`. | WA é calmo (100-200ms). `transition-all` em 300ms anima até layout-shift — quebra a sensação nativa. |
| 4 | `app/javascript/dashboard/components-next/label/LabelItem.vue` | `transition-all duration-300` → `transition-[width,background-color] duration-150 ease-out`. | Mesma razão — 300ms é lento demais para um chip de label. |
| 5 | `app/javascript/dashboard/components-next/phonenumberinput/PhoneNumberInput.vue` | 2 ocorrências de `transition-all duration-500 ease-in-out` → `transition-[outline-color,background-color] duration-150 ease-out` e `transition-opacity duration-150 ease-out` para a msg de erro. | 500ms é absurdo para um input outline/erro. |

---

## Parte 1 — Diagnóstico (10 pontos do brief)

### 1. Tooltip distante do rail 72px — RESOLVIDO

**Estado inicial (pré-sessão):**
- `entrypoints/dashboard.js` (linhas 88-92): FloatingVue config sem `themes` — placement/distance default.
- `_wa-skin.scss` linhas 1804-1809: `.v-popper__popper[data-popper-placement^='right']` com `margin-left: 6px !important`, mesmo para `left`.

**Estado atual (após edits concorrentes + meu fix):**
- `dashboard.js` já tinha recebido `themes: { tooltip: { placement: 'top', distance: 6, delay: {show: 300, hide: 0} }, dropdown: { distance: 4 } }` em paralelo a esta auditoria (provavelmente outro worker/clone).
- **Conflito detectado:** margens SCSS + `distance: 6` do FloatingVue empilham = tooltip ficando ~12px do anchor. Corrigi zerando todas as margens de placements (`margin: 0 !important`). Agora a gap vem exclusivamente do config JS → 6px uniforme.
- `arrowOverflow: false` não adiciona espaço — remove overflow da seta somente. Não é causa do "tooltip longe".

### 2. Toast / Snackbar posicionamento e dark mode

**Posicionamento:**
- `components/SnackbarContainer.vue` usa `popover="manual"` (top-layer nativa) + `fixed top-4 left-1/2 -translate-x-1/2`.
- Top-layer do HTML **ignora** transforms ancestrais (é o ponto da API). Então o `translate-x-1/2` sobre `left-1/2` centraliza no **viewport** corretamente, não dentro do content area. **OK.**
- **Observação:** em tablets/768px, o `max-w-[25rem] w-[calc(100%-2rem)]` funciona bem. Não há regressão.

**Dark mode (corrigido):**
- Default antes: `bg-n-slate-12 dark:bg-n-slate-7 text-white`. `slate-7` dark = #4a5459. Texto branco → contraste OK (~5:1) mas visualmente **frio e genérico**.
- Agora: `bg-[#233138]` (WA header dark) em ambos os temas. Contraste >11:1 com white. Consistente com tooltip (mesma cor) e header mobile WA.

### 3. Dropdowns / popovers / ComboBox

- `components-next/dropdown-menu/base/DropdownContainer.vue`: usa teleport para `body` **apenas** quando `placement === 'top'`. Default (`bottom`) fica in-flow, safe. Cores: `bg-n-solid-1 border-n-weak` — OK (solid-1 tem versão dark via `_next-colors.scss`).
- `components-next/sidebar/SidebarCollapsedPopover.vue`: usa `TeleportWithDirection` (body) + cálculo `fixed top/left` baseado em `triggerRect`. Cores: `bg-n-solid-1 dark:bg-[#233138]` — consistente com WA. **OK.**
- **Risco residual:** ancestral com `transform` pode afetar `position: fixed` do popover calculado a partir de `getBoundingClientRect()`. Não vi ancestor crítico (apenas `<aside>` sem transform), mas fique atento se a `sidebar` ganhar alguma transform de animação.

### 4. Conversation card hover — JÁ ESTAVA RESOLVIDO

- `_wa-skin.scss` linhas 1779-1789 já está correto (outro clone aplicou antes):
  - `.conversation:not(.active):hover` (exclui ativa)
  - `.conversation.active, .conversation.active:hover` — ativa blindada com tom WA `#f0f2f5`.
- Nenhum fix meu aqui.

### 5. Status indicators (open/pending/resolved/snoozed) e pills

- Cores derivadas de `_next-colors.scss`:
  - amber (pending), ruby (urgente), teal (success/resolved), violet (snoozed) — paleta Radix.
  - Status pills `bg-n-*-9 text-white` têm contraste 4.5:1+ com white.
- **Não encontrei offenders críticos.** Paleta harmoniosa, cores corretas para WCAG AA.
- `Snackbar.vue` usa `bg-n-ruby-9 / bg-n-amber-9 / bg-n-teal-9` para error/warning/success — consistente.

### 6. Tabs breakpoint — validado

- Lista: `w-[380px] 2xl:w-[448px]` (ChatList.vue linha 1133).
- Tabs: `chat-list-tabs` com `flex-wrap: nowrap` (linhas 1331-1334 no skin), `padding: 5px 11px`, `font-size: 13px`.
- Math: "Minhas (12) • Não atribuídas (36) • Todas (248)" com px compactos cabe em 380px até ~viewport 1023. Não observei overflow; se chegar a vazar em labels longas, reduzir para `padding: 4px 9px` resolve. **Não aplicado agora** — sem evidência de quebra real em 380px.

### 7. Sidebar rail 72px — OK

- `components-next/sidebar/Sidebar.vue` linha 877: `width: '72px'` quando collapsed.
- Ícones centralizados via `justify-center px-1` (linha 887).
- Active state: o rail usa SidebarGroupLeaf com `bg-n-alpha-2` + `text-n-slate-12` — discreto. Active de grupo (com sub-menu) abre `SidebarCollapsedPopover`. Badges de contagem seguem `SidebarNotificationBell.vue` — não vazam em 72px.

### 8. Dark mode coverage — hex hardcoded

Top arquivos com `bg-[#xxxxxx]` (61 ocorrências em 40 arquivos):

| Arquivo | Count |
|---|---|
| `settings/wahaConnections/Index.vue` | 6 |
| `year-in-review/ShareModal.vue` | 5 |
| `year-in-review/YearInReviewModal.vue` | 5 |
| `widgets/conversation/components/GalleryView.vue` | 3 |
| `widgets/conversation/conversationBulkActions/AgentSelector.vue` | 2 |
| `widgets/conversation/conversationBulkActions/TeamActions.vue` | 2 |
| `widgets/conversation/ConversationSearchBar.vue` | 2 |
| `routes/dashboard/inbox/components/InboxDisplayMenu.vue` | 2 |
| `components-next/feature-spotlight/FeatureSpotlightPopover.vue` | 2 |
| `components/buttons/ResolveAction.vue` | 2 |

**Maioria são cores WA intencionais** (ex.: `bg-[#233138]` para tooltip/popover dark). Só vale refatorar os de `year-in-review/` e `wahaConnections/` caso apareça como inconsistência visual em dark — fora do escopo de 20 min.

### 9. Animações / transitions

Encontrados 10+ arquivos com `transition-all duration-300/500`. **Corrigidos os 3 mais visíveis (InboxCard, LabelItem, PhoneNumberInput — itens 3/4/5 da tabela).**

Não corrigidos (deliberadamente, fora do fluxo principal de conversas):
- `year-in-review/*` (10 ocorrências de 300ms ease-out) — é um modal sazonal, lento é aceitável para drama.
- `combobox/ComboBox.vue`, `dialog/Dialog.vue`, `textarea/TextArea.vue`, `avatar/Avatar.vue`, `input/Input.vue`, `changelog-card/*`, `HelpCenter/Pages/ArticleEditorPage/ArticleEditorHeader.vue` — revisão em segunda passada.

### 10. Border-radius inconsistencies

- `ConversationCard.vue` usa `rounded-full` apenas no Avatar (size-5 badge, linha 98, 109) — correto.
- `_wa-skin.scss` usa radius 6/8/12/16 (tabs chip = 16 OK, msg composer = 8, tooltip = 6) — dentro do sistema WA.
- **Não encontrei `rounded-3xl` em containers** no escopo auditado. Nada para corrigir.

---

## Remaining tasks (não deu tempo em 20min)

1. **Animations segunda passada:** revisar `ComboBox.vue`, `Dialog.vue`, `TextArea.vue`, `Avatar.vue`, `Input.vue` e trocar `transition-all` por `transition-colors|transition-opacity` conforme necessário.
2. **Hex hardcoded em `wahaConnections/Index.vue` (6x)** — validar em dark mode no navegador e substituir por tokens n-* onde fizer sentido.
3. **Teste ao vivo do tooltip no rail 72px** — depois de `pnpm run build` (ou Vite dev), abrir homologacao e validar:
   - Gap visual do tooltip é exatamente 6px? (agora só 1 fonte: FloatingVue distance)
   - Placement top ativa corretamente em botões top-bar?
4. **Toast em dark:** smoke test com snack de cada variante (success/error/warning/default) em dark mode.
5. **Tabs em 768-1023px:** smoke test com labels i18n pt-BR ("Não atribuídas") em viewport de tablet — se vazar, reduzir `padding` a `4px 9px`.
6. **Status pill contrast audit:** não tinha regra `.status-*` no skin. Validar `SidebarBadge` e `ConversationStatusPill` em dark.

---

## Resumo executivo

| Alvo | Estado |
|---|---|
| Tooltip distance global | Corrigido (duplo gap eliminado) |
| Snackbar dark mode | Corrigido (WA-fiel, #233138) |
| Animations exageradas | 3 corrigidos (InboxCard, LabelItem, PhoneNumberInput) |
| Conversation hover active | Já resolvido por outro fix paralelo |
| Dropdowns / popovers | Sem problemas críticos encontrados |
| Tabs breakpoint | OK (não quebra em 380px) |
| Dark mode coverage | Aceitável (hex hardcoded são intencionais WA) |
| Border-radius | Consistente |

**5 fixes cirúrgicos aplicados no working tree, zero commits, ESLint sem erros novos.**
