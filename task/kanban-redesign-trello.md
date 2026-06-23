# Redesign do Kanban — padrão Trello (ChatSPX)

**Branch:** nicolas · **Flag guarda-chuva:** `kanban_ux_v2` (já existe, `enabled: true`)
**Estilo escolhido:** Trello (card limpo, faixa de cor no topo, chips de label, avatar do assignee)
**Escopo:** Fases 0–4 (quadro + List + Calendar + dark + animações + extras)
**Risco:** baixo — sem backend novo nas Fases 0–3; todos os dados já existem no serializer/store.
**Validação:** sempre em `nicolas.chatspx.app` antes de qualquer frota.

---

## 0. Dados já disponíveis (não precisa backend)

O serializer `_funnel_item.json.jbuilder` já entrega, por card:
- `conversation`: `id, display_id, status, contact_id, inbox_id, assignee_id, last_activity_at`
- `contact`: `id, name, phone_number, thumbnail`
- `last_message`: `content, processed_message_content, created_at`

No store/getters do front já dá pra cruzar:
- **Labels** → `labels/getLabels` + labels da conversation (filtro já usa `labelIds`)
- **Assignee** → `agents/getAgents` por `assignee_id`
- **Canal/inbox** → `inboxes/getInboxById(inbox_id)` (tipo p/ ícone WhatsApp/web/email)
- **Agendadas pendentes** → `kanban/getScheduledMessagesByConversation`

> Conclusão: o card rico é 100% montável com dados existentes. Qualquer campo que faltar (ex.: labels não vir no serializer) → ver §6 (único ponto que *pode* exigir +1 campo no jbuilder).

---

## Fase 0 — Tokens & fundação (habilitador, sem mudança visível isolada)

**Objetivo:** parar de espalhar sombras/raios/cores soltos e centralizar um "design system" do Kanban.

**Arquivo novo:** `app/javascript/dashboard/components-next/Kanban/_kanban-tokens.css` (ou bloco `:root` em arquivo de estilo do Kanban). Tokens:

```css
:root {
  --kanban-card-radius: 0.625rem;        /* 10px */
  --kanban-card-shadow: 0 1px 2px rgba(16,24,40,.06), 0 1px 3px rgba(16,24,40,.10);
  --kanban-card-shadow-hover: 0 4px 8px rgba(16,24,40,.10), 0 2px 4px rgba(16,24,40,.06);
  --kanban-card-shadow-drag: 0 16px 28px -8px rgba(16,24,40,.22);
  --kanban-col-width: 304px;
  --kanban-col-gap: 0.75rem;
  --kanban-board-bg: var(--n-background);
  --kanban-accent-fallback: #94a3b8;
}
```

**Helper de cor** (novo composable) `Kanban/composables/useStageColor.js`:
- `topStripStyle(color)` → faixa sólida no topo
- `softBg(color, alpha)` → fundo translúcido derivado (para header de coluna)
- `contrastText(color)` → preto/branco legível sobre a cor (para pills)

**Drag-ghost padronizado:** trocar os 3 blocos `#2dc46f` duplicados (em `KanbanBoard.vue`, `KanbanColumn.vue`) por classe compartilhada usando os tokens. Hoje a cor verde está hardcoded em 3 lugares.

**Critério de aceite:** build verde, visual idêntico (tokens ainda não aplicados em massa).

---

## Fase 1 — Card rico (MAIOR impacto visual)

**Arquivo:** `components-next/Kanban/KanbanCard.vue` (reescrita do `<template>` + `<style>`; lógica de `<script>` quase intacta).

### Layout-alvo (Trello card)
```
┌──────────────────────────┐
│▓▓▓▓ faixa cor do estágio ▓│  ← topo, h-1.5, cor = accentColor
│ [vendas] [urgente]        │  ← chips de label (máx 3 + "+N")
│ 🟢 João Silva        📱WA │  ← avatar contato + nome · ícone canal
│ "Bom dia, gostaria de..." │  ← última msg, line-clamp-2
│ ───────────────────────── │
│ ⏰há 2h  ✉2    📞num  👤Ana│  ← tempo · agendadas · fone · avatar assignee
└──────────────────────────┘
   hover → sombra sobe + ações (clock/move/x) aparecem à direita
```

### Mudanças concretas no template
1. **Faixa de topo** substitui a borda esquerda de 3px. Remover `border-left` do `<style>` e `:style="{ borderLeftColor }"`; adicionar `<div class="kanban-card__strip" :style="{ background: accentColor }"/>`.
2. **Chips de label** (novo bloco no topo): computar `cardLabels` a partir de `labels/getLabels` ∩ labels da conversation. Render como pills `rounded` com `background: softBg(label.color)`, texto `contrastText`. Limitar a 3, excedente vira `+N`.
3. **Ícone de canal** ao lado do nome: `channelIcon = computed` mapeando `inbox.channelType` → `i-lucide-*` (WhatsApp `i-ri-whatsapp-line`, web `i-lucide-globe`, email `i-lucide-mail`, etc.). Tooltip = nome do inbox.
4. **Status como pill com texto** (não só bolinha): usar `statusTitle` já existente + cor. Mantém ícone, adiciona label curto em telas largas.
5. **Rodapé reorganizado**: tempo relativo (`formatDistanceToNow` do date-fns, locale ptBR — já usado no CalendarView) + badge de agendadas pendentes + telefone + **avatar do assignee** (novo: `agents/getAgents` por `assignee_id`, fallback "não atribuído").
6. **Micro-interações**: `transition` de sombra via tokens; hover eleva 1px (`translate-y-[-1px]`). Ações já têm o padrão `opacity-0 group-hover:opacity-100`.

### `<script>` — acréscimos
- `cardLabels`, `assignee`, `channelIcon`, `relativeTime`, `pendingScheduledCount` (todos `computed` sobre getters existentes).
- Nenhuma mudança na detecção drag-vs-click (linhas 154–194 ficam).

### i18n
- Novas chaves em `kanban.json` (en + pt_BR): `CARD.UNASSIGNED`, `CARD.SCHEDULED_COUNT`, `CARD.LABELS_MORE`.

**Critério de aceite:** card mostra label/assignee/canal/tempo quando existem; degrada graciosamente quando não; drag e click de abrir conversa continuam funcionando; specs ajustados.

---

## Fase 2 — Coluna & Board (estilo board Trello)

### 2a. `KanbanColumn.vue`
1. **Barra de topo colorida** no header da coluna (`h-1` na `stage.color`) + header com `softBg(stage.color, .08)`.
2. **Contador estilizado** (pill maior, peso semibold) e o color-dot vira redundante → remover dot, manter barra.
3. **Botão "＋ Adicionar card"** fixo no rodapé da coluna (abre o fluxo de adicionar conversation ao estágio — emite novo evento `addCard(stage)`; ligação no board pode reusar `MoveItemModal`/seleção de conversa). *Se o fluxo de "adicionar conversa avulsa" não existir hoje, marcar como TODO e deixar o botão atrás de `v-if` até a ação existir.*
4. **Colapsar coluna**: botão no header → estado `collapsed` (local + persistir em `localStorage` por `stageId`). Colapsada = faixa vertical de ~44px com nome rotacionado + contador.
5. Manter lazy-load/IntersectionObserver intactos.

### 2b. `KanbanBoard.vue`
1. **Fundo de board** sutil (gradiente/tom levemente distinto do `n-background`) usando `--kanban-board-bg`.
2. **Coluna-fantasma "＋ Adicionar estágio"** ao final do `draggable` (botão tracejado, largura da coluna) → abre `StageForm` em modo create.
3. **Drag-ghost/drop-zone** repaginados via tokens da Fase 0 (remover `#2dc46f` hardcoded; usar accent translúcido).
4. Larguras e gaps via tokens (`--kanban-col-width`, `--kanban-col-gap`).

**Critério de aceite:** colunas com identidade visual por cor, colapsam e lembram estado; board tem "adicionar estágio" inline; reorder de estágios continua via `handleStageReorder`.

---

## Fase 3 — Polimento & consistência

1. **ListView.vue** — alinhar badges de stage/status ao novo design (pills + cores derivadas), avatar do assignee na linha, ícone de canal. Manter grid/sort atuais.
2. **CalendarView.vue** — chips de evento na cor do estágio; consistência tipográfica.
3. **Dark mode** — revisar todos os `softBg`/contraste; garantir tokens com variante dark.
4. **Animações** — `TransitionGroup` na lista de cards da coluna (entrada/saída suave ao mover/filtrar). Cuidado com `vuedraggable` (usar `:component-data` ou transição só em adições, p/ não brigar com o sortable).
5. **Estados vazios** — ilustração/ícone + copy melhor (hoje é `i-lucide-inbox` simples).
6. **Responsivo** — board com snap horizontal em mobile; card já tem fallback `opacity-100` em telas pequenas.

**Critério de aceite:** 3 views coesas, dark mode ok, animações sem glitch de drag, specs verdes.

---

## Fase 4 — Extras "Monday" (opcional, só estética/conveniência)

1. **Densidade configurável** — toggle compacto/confortável (altura do card, line-clamp), persistido em `localStorage`. Reduz padding e oculta última msg no modo compacto.
2. **Cor de capa do card** — opção de pintar topo inteiro do card com a cor da label principal (estilo Trello "cover").
3. **Rodapé de coluna com somatório** — contador total + (futuro) soma de valor se algum dia houver campo de valor/deal. Por ora: total + nº de agendadas no estágio.
4. **Filtro rápido por label** clicando no chip do card.

> Fase 4 é "nice to have"; recomendo só depois de Fases 1–3 aprovadas no staging.

---

## Ordem de PRs sugerida
1. **PR-0**: tokens + helper de cor + dedupe do ghost (invisível, base). 
2. **PR-1**: card rico ← *aprovar visual aqui antes de seguir*.
3. **PR-2**: coluna + board.
4. **PR-3**: list + calendar + dark + animações.
5. **PR-4**: extras (se desejado).

Cada PR: `pnpm build` (vite) verde + specs Vue dos componentes tocados + validação manual no staging (`assets:precompile` + `sudo systemctl restart chatwoot.target`).

---

## Arquivos que serão tocados (resumo)
| Fase | Arquivos |
|---|---|
| 0 | `_kanban-tokens.css` (novo), `composables/useStageColor.js` (novo), ghost em Board/Column |
| 1 | `KanbanCard.vue`, `kanban.json` (en/pt_BR), `KanbanColumn.spec.js` (ajuste) |
| 2 | `KanbanColumn.vue`, `KanbanBoard.vue`, `StageForm.vue` (hook create), `kanban.json` |
| 3 | `ListView.vue`, `CalendarView.vue`, tokens dark, `KanbanIndex.spec.js` (ajuste) |
| 4 | `KanbanCard.vue`, `KanbanColumn.vue`, `KanbanIndex.vue` (toggle densidade) |

## Pontos a confirmar antes de codar
- **Labels no serializer**: confirmar se labels da conversation chegam ao front no contexto do Kanban; se não, adicionar `conversation.labels` (ou `label_list`) em `_funnel_item.json.jbuilder` (único toque possível de backend, trivial).
- **"Adicionar card" (Fase 2.3)**: existe fluxo de adicionar conversa avulsa a um estágio? Se não, o botão fica atrás de flag até a ação existir.
