# ChatSPX — WhatsApp-Fiel Design System

> Spec unico e aplicavel. Base: tokens em `_next-colors.scss` + skin `_wa-skin.scss`. Target: desktop 1280–1920, dark obrigatorio.
> Autor: @ux-design-expert (Alex). Status: v1 — pronto para implementacao.

---

## 1. Principios de design

1. **Calmo e previsivel.** Cores planas, zero gradientes de hype. Superficies sao `slate-1..5`; acento `iris-9` e raro.
2. **Informacao > decoracao.** Densidade alta na lista (48px avatar, 2 linhas), silencio na conversa (bubbles respiram, metadata discreta).
3. **Mensagem primeiro.** O centro da tela e a thread: quem fala, o que fala, quando. Todo resto e chrome de suporte.
4. **Previsibilidade motora.** Durations curtas (120–200ms), easing padrao `ease-out`, nunca bounce. Hover nunca desloca > 1px.
5. **Paridade WhatsApp, personalidade Simplex.** Copiamos grid/comportamento WA; diferenciamos em acento `iris` (verde `#00a884`) sem tocar na forma.

---

## 2. Color tokens

Tokens em `rgb(var(--slate-N) / <alpha>)`. Todos ja existem em `_next-colors.scss` (linhas 7–321).

| Token | Light | Dark | Uso semantico | Status |
|-------|-------|------|---------------|--------|
| `n-slate-1` | #ffffff | #0b141a | App root / chat pane bg | OK |
| `n-slate-2` | #f9fafb | #111b21 | Sidebar list bg | OK |
| `n-slate-3` | #f0f2f5 | #202c33 | Panel / header bg | OK |
| `n-slate-4` | #e9edef | #233138 | Subtle surface, modal bg | OK |
| `n-slate-5` | #d9dbdf | #2a3942 | Hover/active row | OK |
| `n-slate-6` | #d1d7db | #374045 | Border divisor | OK |
| `n-slate-7` | #c7c9cc | #4a5459 | Border forte, scrollbar | OK |
| `n-slate-9` | #8696a0 | #8696a0 | Icone inativo, meta text | OK |
| `n-slate-11` | #54656f | #d1d7db | Secondary text | OK |
| `n-slate-12` | #111b21 | #e9edef | Primary text | OK |
| `n-iris-3` | #d9fdd3 | #083d31 | Bubble out (light) | OK |
| `n-iris-4` | #b8f1e0 | #005c4b | Bubble out (dark) — usar `solid-blue` dark | OK |
| `n-iris-9` | #00a884 | #25d366 | Brand / CTA / unread dot | OK |
| `n-iris-10` | #008c70 | #4de598 | CTA hover | OK |
| `n-ruby-9` | #e54666 | #e54666 | Destroy / erro | OK |
| `n-amber-9` | #ffc53d | #ffc53d | Pendente / private note | OK |
| `n-background` | #ffffff | #111b21 | Body background | OK |
| `n-solid-blue` | #d9fdd3 | #005c4b | **Bubble out fill** (alias) | OK |
| `n-strong` | #d1d7db | #374045 | Border forte | OK |
| `n-weak` | #e9edef | #2a3942 | Border fraco / divisor | OK |
| `n-solid-1..3` | #ffffff | #202c33/#233138/#2a3942 | Chips/botoes secund. | OK |
| `n-solid-active` | #f0f2f5 | #374045 | Pressed state | OK |

**Ajuste pendente (quick win):** criar alias `--bubble-in` e `--bubble-out` mapeando para `slate-1`/`iris-3` (light) e `slate-3`/`solid-blue` (dark) para uso direto em `MessageBubble.vue`.

---

## 3. Tipografia

Fonte: **Inter** (ja usada) com fallback `-apple-system, "Segoe UI", Roboto, sans-serif`. Nao importar fonte WA (licenca).

| Nivel | Size | Line-height | Weight | Tracking | Uso |
|-------|------|-------------|--------|----------|-----|
| Micro | 11px | 14px | 400 | 0.2px | timestamp em bubble, badge count |
| Meta | 12px | 16px | 400 | 0 | list item time, read receipts, status |
| Body-sm | 13px | 18px | 400 | 0 | list snippet, input helper |
| Body | 14.2px | 19px | 400 | 0 | **texto de mensagem WA** (nao 14 nem 15 — 14.2 e o exato WA) |
| Body-strong | 14px | 20px | 500 | 0 | list item title, contact name |
| Title-sm | 15px | 20px | 500 | 0 | header da conversa (nome) |
| Title | 16px | 22px | 500 | -0.1px | drawer section title, modal title |
| Title-lg | 18px | 24px | 600 | -0.2px | empty state, settings page title |
| Display | 20px | 26px | 600 | -0.3px | onboarding hero |
| Display-lg | 24px | 30px | 700 | -0.4px | raro — splash |

Regras: sem `font-weight: 700` em UI chrome. Numeros em badges usam `font-variant-numeric: tabular-nums`.

---

## 4. Spacing + grid

Base 4px. Tailwind scale (default) ja e compativel.

| Token | px | Tailwind | Uso |
|-------|----|----------|----|
| `space-0.5` | 2 | `p-0.5` | gap icone dentro de chip |
| `space-1` | 4 | `p-1` | gap minimo |
| `space-1.5` | 6 | `p-1.5` | padding interno badge |
| `space-2` | 8 | `p-2` | gap entre icone+label |
| `space-2.5` | 10 | `p-2.5` | bubble padding-y |
| `space-3` | 12 | `p-3` | bubble padding-x, list row padding-y |
| `space-4` | 16 | `p-4` | list row padding-x, header padding |
| `space-5` | 20 | `p-5` | drawer padding |
| `space-6` | 24 | `p-6` | modal padding, section gap |
| `space-8` | 32 | `p-8` | hero padding |
| `space-12` | 48 | `p-12` | empty state vertical gap |

**Grid principal do app:**

```
[ Rail 72px ] [ List 380px ] [ Chat pane fluido (min 600) ] [ Drawer 400px (toggle) ]
```

- Rail: fixo 72px, borda direita `n-weak`.
- List: largura **380px** (WA usa 390, nossa lista tem badges — 380 evita overflow). Min 320, max 480 via drag.
- Chat pane: `flex: 1 1 auto`, min 600px.
- Drawer: **400px** fixo quando aberto, colapsa para 0.

**Paddings internos:**
- List row: `12px 16px` (py py-3 px-4).
- Bubble: `6px 7px 8px 9px` (assimetria WA) + `max-width: 65%`.
- Header conversa: altura **59px**, padding `0 16px`.
- Reply box wrapper: altura min 62px, padding `10px 16px`.

---

## 5. Elevation + border radius

**Shadow scale — WA e quase flat:**

| Nivel | Valor | Uso |
|-------|-------|-----|
| `shadow-0` | none | default de tudo |
| `shadow-1` | `0 1px 2px rgba(11,20,26,.06)` | header fixo, reply box |
| `shadow-2` | `0 2px 5px rgba(11,20,26,.1)` | dropdown menu, tooltip |
| `shadow-3` | `0 8px 24px rgba(11,20,26,.14)` | modal, popover grande |

No dark, reduzir alpha para `.35/.5/.7` e aumentar y-offset em 1px.

**Radius scale:**

| Token | px | Uso |
|-------|----|----|
| `r-none` | 0 | separadores, hair-lines |
| `r-sm` | 4 | chips, badges, input bord |
| `r-md` | 6 | botoes secundarios, small cards |
| `r-lg` | 8 | **bubble WA (3 cantos)** |
| `r-xl` | 12 | cards grandes, modal |
| `r-2xl` | 16 | drawer headers, empty state illust |
| `r-full` | 9999 | avatares, FAB, unread dot |

Bubble WA tem radius **assimetrico**: `8px 8px 8px 2px` (recebida, tail bottom-left) e `8px 8px 2px 8px` (enviada, tail bottom-right).

---

## 6. Estados interativos

Transicao padrao: `transition: background-color 120ms ease-out, color 120ms ease-out, border-color 120ms ease-out;`. Nunca animar `transform` exceto em icones rotacionais.

| Componente | base | hover | active | focus | disabled |
|------------|------|-------|--------|-------|----------|
| **Button primary** | bg `iris-9`, text `#fff` | bg `iris-10` | bg `iris-11`, scale 0.98 | ring 2px `iris-9/50` offset 2 | bg `slate-4`, text `slate-9` |
| **Button secondary** | bg `slate-3`, text `slate-12`, border `slate-6` | bg `slate-4` | bg `slate-5` | ring 2px `iris-9/40` | opacity 50 |
| **Icon button** | bg transparent, text `slate-11` | bg `slate-3`, text `slate-12` | bg `slate-5` | ring 2px `slate-9/30` | opacity 40 |
| **Input** | bg `slate-3` (light) / `slate-4` (dark), border none, text `slate-12` | bg `slate-3` | bg `slate-3` | border `iris-9` 1px, shadow 0 | bg `slate-2`, text `slate-9` |
| **Tab** | text `slate-11`, border-b 3px transparent | text `slate-12`, bg `slate-2` | text `iris-9` | ring 2px | — |
| **Tab active** | text `iris-9`, border-b 3px `iris-9` | — | — | — | — |
| **List item (conversation)** | bg `slate-1` | bg `slate-3` | bg `slate-5` | ring inset 2px `iris-9/30` | — |
| **List item selected** | bg `slate-4` (light) / `slate-5` (dark) | bg `slate-4` | bg `slate-5` | — | — |
| **Menu item** | bg transparent, text `slate-12` | bg `slate-3` | bg `slate-5` | — | text `slate-9` |
| **Card** | bg `slate-1`, border `slate-6` | — (no hover for cards) | — | ring 2px `iris-9/40` | — |

---

## 7. Micro-interactions (10)

1. **Check-marks de leitura** animam `slate-9 → #53bdeb` em 200ms `ease-out` quando `read=true`. Transform: none; so cor.
2. **Bubble entrada** fade-in 140ms + translateY(4px→0), stagger 20ms se batch > 1.
3. **Typing indicator** — 3 dots, `keyframes blink` 1.4s, `animation-delay` 0/.2/.4s, scale 0.6→1.
4. **Unread badge count** decrementa com `number-roll` 180ms (y-shift) ao marcar lido.
5. **Reply box grow** — textarea auto-resize com `transition: height 80ms linear` (WA e quase instantaneo).
6. **Send button pulse** — quando texto > 0, fade-in do mic→send em 120ms crossfade.
7. **Attachment popup** — scale 0.95→1 + opacity, 160ms `cubic-bezier(.16,1,.3,1)` (overshoot leve WA-style).
8. **List row hover** — bg transition 100ms `ease-out` apenas (sem elevation).
9. **Delivery status ring** — circular spinner `stroke-dasharray` enquanto envia; morph para check em 220ms.
10. **Active conversation indicator** — 3px barra esquerda `iris-9` slide-in de left: -3 → 0 em 140ms quando item e selecionado.

**NAO fazer:** sidebar que escorrega, botao que levita, card que tilta, parallax, blur cinematico.

---

## 8. Componentes chave (spec visual)

### Sidebar rail (72px)
- Width: **72px** fixa. Bg `slate-2`. Border-right 1px `n-weak`.
- Item: 56px tall, icon 24px centralizado, text hidden (tooltip direita).
- Active: bg `slate-4` + barra esquerda 3px `iris-9` (radius 0 2 2 0).
- Hover: bg `slate-3`.
- Badge: circulo 18px `iris-9` no top-right do icone, offset `-4px -4px`, text 11px/bold `#fff`.
- Avatar user no rodape: 36px, margin-bottom 16px.

### Conversation list item (72px tall)
- Padding: `12px 16px`. Border-bottom 1px `n-weak` (apenas entre itens, nao ultimo).
- Avatar: **48px**, radius-full, margin-right 12px. Badge presence 10px bottom-right (`iris-9` + border 2px `slate-1`).
- Row 1 (flex justify-between): Title 14px/500 `slate-12` (truncate 1 linha) | Time 12px `slate-9`.
- Row 2 (flex justify-between): Snippet 13px `slate-11` (truncate 1 linha, max 240px) | Badge unread 18px radius-full `iris-9` text `#fff` 11px/bold, min-width 18.
- Pinned icon: 14px `slate-9`, antes do badge.
- Channel icon (WA/insta): 14px bottom-left do avatar (overlay circular bg `slate-1` border 2px).
- Selected: bg `slate-4` (sem underline).

### Message bubble
- Max-width: **65%** da chat pane (min 480 => 312px).
- Padding: `6px 7px 8px 9px` (incoming) / `6px 9px 8px 7px` (outgoing).
- Radius: `8px 8px 8px 2px` (in) / `8px 8px 2px 8px` (out).
- Bg in: `slate-1` (light) / `slate-3` (dark).
- Bg out: `iris-3` (light, `#d9fdd3`) / `solid-blue` dark (`#005c4b`).
- Shadow: `0 1px .5px rgba(11,20,26,.13)` — sombra quase imperceptivel WA-style.
- Tail: SVG 8x13px absolute bottom: 0; left/right: -7px; fill same as bubble bg; apenas no **primeiro bubble** de sequencia (group by sender, gap < 60s).
- Text: 14.2px/19px. Timestamp inline no fim: 11px `slate-9`, padding-left 6px, wrap com `float: right`.
- Reply quote (prefixo): border-left 3px `iris-9`, bg `slate-2/5` alpha, padding `4px 8px`, radius 4, font 13px.

### Reply box
- Wrapper: bg `slate-3`, padding `10px 16px`, border-top 1px `n-weak`.
- Textarea: bg `slate-1` (light) / `slate-4` (dark), radius 8, padding `9px 12px`, font 14.5/20, min-height 42, max-height 120 (scrollable acima).
- Toolbar left: emoji 22px, attach 22px (gap 8px, cor `slate-9`).
- Toolbar right: mic 22px OU send 22px (crossfade), bg `iris-9` circular 42px quando send ativo.
- Private note mode: bg wrapper vira `amber-2` (light) / `amber-3` alpha (dark), border-top `amber-6`.

### Header da conversa (59px)
- Bg `slate-3`. Padding `0 16px`. Border-bottom 1px `n-weak`.
- Left: Avatar 40px | Stack (nome 16/500 `slate-12` + status 13/400 `slate-11` — "online" ou "digitando..." italic `iris-9`).
- Right: Icon buttons 40x40 radius-full (search, menu, call). Gap 4px. Hover bg `slate-4`.
- Click no avatar ou nome abre drawer.

### Contact drawer (400px)
- Bg `slate-2`. Border-left 1px `n-weak`. Slide-in 200ms `ease-out`.
- Hero: avatar 200px centrado, nome 20/600, numero 14/400 `slate-11`, padding-y 32.
- Accordion headers: 44px tall, bg `slate-3`, text 14/500, chevron 16 `slate-9`, border-bottom 1 `n-weak`.
- Body accordion: padding 16, font 13/400.

### Modal
- Overlay: `rgba(11,20,26,.5)` (dark: `rgba(0,0,0,.75)`).
- Container: bg `slate-1` (light) / `slate-4` (dark), radius 12, shadow-3, max-width 480, padding 0 (header/body/footer internos).
- Header: padding `20px 24px 12px`, title 18/600, close X 20 `slate-9` top-right.
- Body: padding `12px 24px 20px`, font 14/20.
- Footer: padding `16px 24px`, border-top 1 `n-weak`, flex justify-end gap 8. CTA secondary + primary.

---

## 9. Acessibilidade

- **Contrast AA minimo:** todos text-on-bg validados.
  - `slate-12` em `slate-1`: 15.6:1 (AAA).
  - `slate-11` em `slate-1`: 7.8:1 (AAA).
  - `slate-9` em `slate-1`: 3.4:1 (usar so para meta >= 12px/500 — AA large).
  - `#fff` em `iris-9`: 3.2:1 — **borderline**; aumentar peso texto para 500+ em botoes.
- **Focus ring** sempre visivel: 2px solid `iris-9` com offset 2px (`outline-offset: 2px`). Nunca `outline: none` sem replacement.
- **Touch targets** min 40x40 (botoes icone). Rail items 56 tall ok.
- **ARIA criticos:**
  - `aria-label` em todos icon buttons (sem text).
  - `role="log" aria-live="polite"` no messages view.
  - `aria-selected="true"` no list item ativo.
  - `aria-pressed` em toggle mic/send/emoji.
  - `role="dialog" aria-modal="true"` em modals.
- **Keyboard:** Tab order rail → list → header → messages → reply. Esc fecha modal/drawer. `/` foca search. Enter envia, Shift+Enter quebra linha.

---

## 10. Responsive breakpoints

Target principal e desktop, mas degradacao deve existir.

| Range | Layout | Regras |
|-------|--------|--------|
| `< 768px` (mobile) | Single column | Rail vira bottom-bar 56px. Lista full-width. Chat substitui lista ao selecionar (back button). Drawer vira modal fullscreen. Reply box sticky bottom. |
| `768–1023px` (tablet) | Rail + (list OU chat) | Rail 64px visivel. Lista 320px OU chat (toggle por selecao, back button no header). Drawer = modal fullscreen. |
| `1024–1439px` (desktop) | Rail + list + chat | Rail 72, lista 360, chat fluido. Drawer toggavel (botao no header), 380px quando aberto, overlaps chat. |
| `>= 1440px` (wide) | 4 colunas | Rail 72, lista 380, chat fluido max 1100, drawer persistente 400px. Content central max-width 1100 centralizado quando drawer fechado. |

Container queries > media queries quando possivel (ja disponivel em Tailwind 3.4+).

---

## 11. Quick wins imediatos (5 — priorizados)

1. **Bubble radius + bg + tail** — trocar `MessageBubble.vue` para radius assimetrico `8/8/8/2` e bg `n-solid-blue` outgoing / `n-slate-1` incoming + tail SVG no primeiro da sequencia. **Impacto: 40% do visual WA.** (touch: 1 arquivo)
2. **Conversation list row** — altura 72px, avatar 48px, 2 linhas, snippet truncate, badge unread `iris-9` circular 18px. Remover qualquer padding/elevation/hover-shift atual. **Impacto: a lista e a primeira coisa que o atendente ve.**
3. **Header da conversa** 59px bg `slate-3` + icon buttons 40px radius-full — hoje e provavelmente maior/com sombra. **Impacto: enquadra toda a tela.**
4. **Reply box** bg wrapper `slate-3`, textarea interno radius 8 bg `slate-1`, botao send circular 42px `iris-9`. Remover bordas/sombras pesadas. **Impacto: zona de acao principal do atendente.**
5. **Sidebar rail** 72px com item 56px + active bar 3px `iris-9`. Sem labels, so icon+tooltip. **Impacto: libera 100+px horizontais para lista/chat.**

Ordem sugerida: 2 → 3 → 4 → 1 → 5 (comeca pela lista porque e a tela mais olhada, depois chat chrome, depois bubbles, por ultimo rail).

---

**Proximo passo:** @architect valida token aliases (`--bubble-in`/`--bubble-out`, `--chat-header-h: 59px`, `--chat-list-w: 380px`, `--rail-w: 72px`) em `_next-colors.scss`; @dev executa quick wins na ordem acima, cada um em commit separado, com screenshot antes/depois no PR.
