# Kanban — Auditoria de Usabilidade (visão do atendente)

**Data:** 2026-06-24 · **Base:** branch `nicolas` (Fases 5–7 no ar no staging) · **Método:** mapeamento dos fluxos reais por 3 agentes + verificação no código.

Foco: o que **trava ou confunde o atendente** no uso diário. Cada item tem severidade, evidência (arquivo:linha) e recomendação.

---

## P0 — Bug funcional (corrigir)

### 1. Botão "Mover" do card não faz nada
- **O que acontece:** o ✛ (mover) do card emite `move` → coluna emite `moveItem` **sem** o estágio de destino (`@move="emit('moveItem', { item })"`, `KanbanColumn.vue:491`). No board, `handleMoveItem` aborta logo no início porque `stageId` é `undefined` (`KanbanBoard.vue:265-269`).
- **Consequência:** clicar em "Mover" **não abre nada e não move**. O `MoveItemModal.vue` existe mas **nunca é importado/usado** (busca no projeto: 0 referências).
- **Impacto:** botão morto num lugar de destaque → atendente acha que está quebrado. Em mobile/touch (sem drag fácil), é a única forma de mover e não funciona.
- **Recomendação:** ligar o `MoveItemModal` (selecionar estágio → `handleMoveItem({ item, stageId })`) **ou** remover o botão se o drag basta. Recomendo ligar — drag é ruim em telas pequenas.

---

## P1 — Descoberta (o atendente não acha / não entende)

### 2. Sinais de aging sem legenda
- **Evidência:** termômetro (`KanbanCard.vue:431-466`) e ampulheta (`595-603`) — ícones de floco de neve / ampulheta com cor, mas **nenhuma legenda**. O significado só aparece no tooltip (hover).
- **Impacto:** atendente vê "❄️ 3" no rodapé da coluna e a ampulheta no card sem saber o que é "parado", "frio", "neste estágio".
- **Recomendação:** legenda/ajuda no board (um "?" com mini-legenda) **ou** texto curto junto ao ícone no card (ex.: "5d no estágio"). Cobrir também no guia do atendente.

### 3. Controles de exibição são só ícones (densidade, capa)
- **Evidência:** botões de densidade (`rows-2/3`) e capa (`paintbrush`) no header (`KanbanIndex.vue:636-657`) — sem rótulo, só `title` no hover; só aparecem na visão Kanban.
- **Impacto:** recursos úteis (compacto, capa colorida) ficam invisíveis; ninguém descobre o "pincel".
- **Recomendação:** agrupar num menu "Exibição" com rótulos, ou tooltip mais explícito; documentar no guia.

### 4. Limite WIP escondido + `window.prompt`
- **Evidência:** definido pelo menu ⋮ da coluna → "Definir limite WIP" via `window.prompt` (`KanbanColumn.vue:71-95`).
- **Impacto:** ninguém acha; e o `prompt` nativo é tosco (sem validação visual, quebra o "feeling" do produto).
- **Recomendação:** trocar o `window.prompt` por um mini-modal/input inline com validação; deixar o acesso mais visível (ex.: clicar no contador da coluna).

---

## P2 — Feedback e consistência

### 5. Erro ao atribuir não reverte o avatar (update otimista)
- **Evidência:** `assignTo` faz update otimista (`localAssigneeId`) e, no `catch`, mostra alerta mas **não reverte** (`KanbanCard.vue` ~195-228).
- **Impacto:** se a atribuição falha, o card mostra o responsável errado até recarregar.
- **Recomendação:** no `catch`, voltar `localAssigneeId` ao valor anterior.

### 6. Mensagem de erro enganosa ao remover do funil
- **Evidência:** `performRemoveItem` usa `KANBAN.ITEMS.MOVE_ERROR` ("Erro ao mover") quando o delete falha (`KanbanBoard.vue:345-355`).
- **Recomendação:** usar uma chave própria (ex.: `ITEMS.REMOVE_ERROR`).

### 7. Filtrar por label não dá feedback explícito
- **Evidência:** clicar no chip filtra e mostra um anel na label ativa (`KanbanCard.vue` filterByLabel/isLabelActive) — bom — mas não há aviso de "filtro aplicado".
- **Recomendação:** o contador de filtros ativos do header já cobre parcialmente; opcional: micro-toast "Filtrando por: <label>".

### 8. Filtros não persistem na URL
- **Evidência:** filtros vão p/ `localStorage` por conta/usuário, não para a URL (`KanbanIndex.vue:97-100`).
- **Impacto:** não dá para compartilhar/salvar um link de board filtrado.
- **Recomendação (opcional):** refletir filtros em query params.

---

## P3 — Copy / clareza (rápidos)

### 9. Seleção de inbox no funil ambígua
- **Evidência:** campo "Inboxes — deixe vazio para mostrar todas" (`FunnelForm`): "vazio = todas" não é óbvio.
- **Recomendação:** trocar por opção explícita "Todas as caixas" vs "Caixas selecionadas".

### 10. "Estágio padrão" detectado por nome em PT hardcoded
- **Evidência:** estágios padrão são identificados por nome ("Abertos/Em Andamento/Resolvidos") ou `automation_type` (`FunnelForm.vue:178-186`, `StageForm.vue:42-46`).
- **Impacto:** renomear/usar outro idioma quebra a proteção do estágio.
- **Recomendação:** marcar "padrão" por flag do backend, não por nome.

---

## O que JÁ está bom (manter)
- Empty states com CTA claro (sem funil / sem estágio / coluna vazia).
- Colapsar coluna com persistência; barra de funil clicável; drawer de agendadas com filtros e polling.
- Detecção clique-vs-drag para abrir conversa; chips de label clicáveis com anel de estado.
- Confirmação antes de remover do funil e antes de excluir funil/estágio (com aviso de cascata).

---

## Priorização sugerida
1. **#1 (botão Mover morto)** — bug, corrigir primeiro.
2. **#2/#3/#4 (descoberta)** — maior ganho de "parece profissional e fácil".
3. **#5/#6 (feedback/erros)** — robustez.
4. **#9/#10 (copy/robustez)** — quando sobrar.
