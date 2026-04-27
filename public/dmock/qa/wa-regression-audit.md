# WA Regression Audit — ChatSPX Redesign WhatsApp-fiel

**Auditor:** @qa (Quinn) — estática, sem browser
**Scope:** working tree `homologacao`, 120 arquivos (+1070/-547), `_wa-skin.scss` 1810 linhas
**Veredicto:** CONCERNS. Merge OK em homologação, aplicar fixes #1/#2/#4/#7 antes de produção.

---

## 1. Top 15 Regressões Potenciais

| # | Arquivo:linha | Risco | Como testar |
|---|---|---|---|
| 1 | `_wa-skin.scss:1778` | `.conversation:hover { bg:#f5f6f7 !important }` sem `:not(.active)` — empilha sobre active state (linha 299) enquanto mouse está em cima. | Hover na conversa atualmente aberta → cor ativa deve vencer. |
| 2 | `_wa-skin.scss:1055` + `_next-colors.scss:21` | `--slate-11` light mudou `84 101 111` → `102 119 129`: contraste sobre branco cai de 5.7:1 para 4.6:1 (AA limítrofe). | Timestamps/preview não lida em light. |
| 3 | `_next-colors.scss:162,314` | `--alpha-1` light=0.04, dark=0.08 (antes maiores). `bg-n-alpha-black1` em Avatar.vue:317 e backdrops de dropdown podem ficar quase invisíveis. | Avatar hover overlay + DropdownBody backdrop. |
| 4 | `InboxList.vue:227` | `lg:min/max-w-[380px]` — em 1280-1535px com ContactPanel (320px) + Copilot (320px) + sidebar 72px, sobra <480px pro conteúdo. Header conversa pode truncar/quebrar. | Monitor 1366×768 com ContactPanel aberto. |
| 5 | `ChatList.vue:1133` | Mesma largura 380/448 + `basis-full` condicional em `isOnExpandedLayout` — sem transição: flash ao alternar layouts. | Alternar layouts compacto/expandido. |
| 6 | `_wa-skin.scss:1624-1631` | `.wa-tabs ul { flex-wrap: nowrap; overflow-x: auto; scrollbar:none }`. Em 768px com 3 tabs + badges, scroll horizontal sem indicador visual. | Resize para 760px → tabs fora da tela descobríveis? |
| 7 | `_wa-skin.scss:1793-1802` | Tooltip `.v-popper--theme-tooltip` forçado dark (#233138) via `!important`. Em UI light pura (reports), tooltip destoa. | Hover ícones ArticleEditorControls em light. |
| 8 | `SnackbarContainer.vue:60` | `popover="manual"`: browsers antigos caem no fallback `position:fixed`. Se ancestral tiver transform, fica relativo ao pai — toast aparece longe. | Qualquer toast em navegador sem popover API completa. |
| 9 | `Sidebar.vue:97` | `isEffectivelyCollapsed = !isMobile` — sempre colapsado. Legacy `v-if` que testam `!isCollapsed` (SidebarAccountSwitcher:58,97) podem render duplicado. | Hover no account switcher no rail. |
| 10 | `_wa-skin.scss:1786` | `.conversation .unread` usa `#25d366` (WA light green), não `var(--wa-primary) #00a884`. Inconsistência visual + contraste 2.5:1 (falha AA). | Unread badges "99+". |
| 11 | `_wa-skin.scss:1060-1067` | Override global `[class*='hover\:bg-n-alpha-1']:hover` fora de `.dark` block — possivelmente vaza em light mode, matando hover de botões ghost. | Botões ghost Button.vue em light. |
| 12 | `Modal.vue:105` vs ContextMenu/LabelBox | Modal overlay `z-[9990]`, ContextMenu/LabelBox `z-[9999]`. LabelBox dentro de Modal OK. Mas SidebarCollapsedPopover `z-[100]` fica atrás de dropdowns filhos. | Abrir Modal + popover no rail. |
| 13 | `ExportConversationModal.vue:130` vs `ShareModal.vue:179` | 10000 vs 10001 — ordem não determinística se concorrentes. | — |
| 14 | `_wa-skin.scss:715,771` | `--wa-primary` definido 2x (light+dark) — sync futuro frágil. Dívida. | — |
| 15 | `_wa-skin.scss:1485` + `Sidebar.vue:100-145` | Handle `display:none` mas handlers `onResizeStart/Move/End` ainda registrados. ~40 linhas de código morto. | — |

---

## 2. "Toast abrindo longe" — Investigação

`SnackbarContainer.vue:60` usa `popover="manual"` + `showPopover()`. API moderna promove para **top-layer** (ignora transforms ancestrais). Porém:

- Em Safari ≤16.4 / Firefox ≤125 o fallback é `position:fixed` — qualquer ancestral com `transform`/`filter`/`contain` quebra o fixed.
- App.vue wrapper recebe font-size via `useFontSize` e RTL toggle — não injeta transform direto, mas se wrapper pai tiver `transform` via tema, quebra.
- Linhas 85-86 aplicam `transform: translateY(-6px) scale(0.98)` ao próprio container durante transition — em fallback browsers causa shift visível.

**Outros popovers candidatos ao nome "toast":** `DropdownContainer.vue:58` (9999 teleport body), `SidebarCollapsedPopover.vue:104` (fixed z-[100]), `ContextMenu.vue:89` (9999), `MentionBox.vue:76`, `FeatureSpotlightPopover`.

**Fix recomendado:** embrulhar `<div popover=manual>` em `<Teleport to="body">` — garante pai=body, zero transforms.

---

## 3. Z-Index Stacking

```
SidebarCollapsedPopover   z-[100]
dropdowns absolute        z-50/z-[100]
DropdownContainer teleport z-9999
ContextMenu               z-[9999]
Modal backdrop            z-[9990]
LabelBox/ConversationParticipant z-[9999]
ExportConversationModal   z-[10000]
YearInReviewModal         z-[9999]
ShareModal                z-[10001]
Snackbar popover          top-layer (ou fallback ~auto)
```

**Conflito real:** ShareModal (10001) pode cobrir Snackbar em fallback. **Modal legacy (9990) < ContextMenu (9999)**: context menu funciona dentro de modal (intencional? OK).

---

## 4. Acessibilidade

| Elemento | Ratio | WCAG |
|---|---|---|
| Botão brand `#00a884` + branco | 3.32:1 | falha AA normal; passa AA large |
| Unread `#25d366` + branco | 2.50:1 | falha AA |
| Secondary text `#667781`/branco (novo slate-11) | 4.59:1 | passa AA (era 5.72:1) |
| Tooltip `#233138`/`#e9edef` | 11.4:1 | AAA |

Focus rings (`Button.vue:105-166`): `focus-visible:bg-n-brand/20` = verde muito claro sobre bg WA light — pouco visível. Adicionar `outline-2 outline-n-brand` explícito.

---

## 5. Performance

- `[class*='hover\\:bg-n-alpha-1']:hover` (attr-substring) em ChatList grande pode causar jank ao rolar.
- ~150 `!important` em `_wa-skin.scss` — dívida técnica alta; cada novo componente precisa camada extra.
- Tooltip repaint desprezível (poucos simultâneos).
- `.wa-tabs ul` reflow OK (`overflow-x:auto` GPU-cheap).

---

## 6. Fixes Prioritários (top 10)

1. `_wa-skin.scss:1778` → `.conversation:not(.active):not(.router-link-active):hover { ... }`
2. `SnackbarContainer.vue:57` → embrulhar em `<Teleport to="body">`
3. `_wa-skin.scss:1786` → usar `var(--wa-primary)` ou escurecer para `#008c70`
4. `InboxList.vue:227` → trocar `lg:` para `xl:` nas min/max width
5. `_wa-skin.scss:1793-1802` → mover bloco dark para dentro de `.dark { ... }`, criar variante light
6. `_next-colors.scss:21` → reverter `--slate-11` para `84 101 111`
7. `Button.vue:111,119,133` → adicionar `focus-visible:outline-2 focus-visible:outline-n-brand`
8. `_wa-skin.scss:1060` → substituir attr-substring por classe explícita `.hover-wa-alpha:hover`
9. `Sidebar.vue:100-145` → remover handlers de resize (handle é `display:none`)
10. Padronizar escala z-index com CSS vars: `--z-modal:9990; --z-popover:9999; --z-toast:10010`

---

## 7. Áreas Intocadas (UI antigo visível)

| Área | Motivo |
|---|---|
| **Super Admin** | ERB legacy fora do skin Vue (`app/views/super_admin/**`) |
| **Settings integrations/SLA/customRoles** | Sem commits em diff |
| **Reports charts** | Headers/cards tocados, mas `ApexCharts`/`ChartStats.vue` usam paleta própria |
| **Portal público + HelpCenter público** | `app/views/public/**`, `app/javascript/portal/**` intocados |
| **Widget embed + Survey** | `app/javascript/widget/**`, `app/javascript/survey/**` sem touch |

**Recomendação:** abrir Fase 5 "cobertura dos cantos" pós-merge. Usuário verá paleta dissonante ao trocar contexto (inbox WA ↔ super admin legacy ↔ widget antigo).

---

**Sumário:** 0 bloqueantes. 4 alta prioridade (#1 hover active, #2 toast longe, #4 layout 1280, #7 focus rings). Dívida técnica: 150 `!important` em `_wa-skin.scss` merece refactor `@layer components` futuramente. Cobertura ausente em Super Admin, Widget, Survey, charts — Fase 5.
