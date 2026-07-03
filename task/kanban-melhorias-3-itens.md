# Kanban ChatSPX — 3 melhorias para implementar

**Branch:** nicolas · **Flag guarda-chuva:** `kanban_ux_v2`
**Risco geral:** baixo — nenhuma migration nova; tudo usa API/campos já existentes.
**Validação:** staging `nicolas.chatspx.app` (build assets + restart `chatwoot.target`).

Ordem sugerida de execução: **1 → 2 → 3** (do que o usuário mais sente para o polimento).

---

## 1. Adicionar conversa manualmente a uma etapa (maior lacuna funcional)

**Por quê:** hoje um card só entra no funil por automação ou arraste. Não há como o usuário puxar uma conversa existente para uma etapa. A API já existe (`KanbanAPI.createItem` → `POST /funnels/:id/funnel_items`), falta só a UI.

**O que fazer:**
- Botão **"＋ Adicionar"** no rodapé (ou header) de cada `KanbanColumn.vue` — emitir evento `addCard(stage)` para o `KanbanBoard.vue` (o emit `addCard` já existia e foi removido por estar sem uso; reintroduzir).
- Novo modal **`AddConversationModal.vue`** (espelhar `MoveItemModal.vue`): campo de busca que lista conversas da conta (reusar busca de conversas existente, filtrando pelos `inbox_ids` do funil), seleção e confirmar.
- No board: `handleAddCard(stage)` → `store.dispatch('kanban/createItem', { funnelId, data: { conversation_id, funnel_stage_id: stage.id } })` → refetch da etapa.
- Garantir dedup: o backend já trata `(conversation_id, funnel_id)` único — tratar erro "já existe" com mensagem amigável.

**Arquivos:** `KanbanColumn.vue`, `KanbanBoard.vue`, novo `AddConversationModal.vue`, `store/modules/kanban/actions.js` (conferir/garantir action `createItem`), `kanban.json` (en/pt_BR: `ITEMS.ADD`, já existe; +placeholder de busca).

**Aceite:** usuário clica "＋ Adicionar" numa coluna, busca uma conversa, confirma, e o card aparece na etapa (e persiste após reload). Conversa já no funil → aviso, sem duplicar.

---

## 2. Trocar o responsável direto pelo card

**Por quê:** o card já mostra o avatar do assignee, mas não dá para mudar o responsável sem abrir a conversa. Fluxo comum em atendimento.

**O que fazer:**
- No `KanbanCard.vue`, transformar o avatar/ícone do assignee num **menu** (clique → lista de agentes de `agents/getAgents` + opção "Não atribuído").
- Ao escolher: `store.dispatch('conversations/assignAgent' ...)` ou o endpoint de assignment já usado no app (conferir o action existente em `store/modules/conversations`); atualizar o card localmente.
- `@click.stop` para não abrir a conversa ao clicar no menu.

**Arquivos:** `KanbanCard.vue` (+ um pequeno dropdown, pode reusar `KanbanFilterSelect.vue` ou um menu simples), conferir action de assignment em `store/modules/conversations`.

**Aceite:** clicar no avatar do responsável abre lista, escolher um agente reatribui a conversa (persiste) e o avatar atualiza. Não abre a conversa por engano.

---

## 3. Substituir popups nativos por modais (polimento de UX)

**Por quê:** excluir etapa, remover card e erros de validação ainda usam `window.confirm`/`alert()` do navegador — destoa do resto. O componente `Dialog` já é usado para cancelar agendadas (padrão a seguir).

**O que fazer:**
- Trocar os `window.confirm` por `Dialog` de confirmação:
  - `KanbanBoard.vue` — remover card (`KANBAN.ITEMS.CONFIRM_REMOVE`) e excluir etapa (`KANBAN.STAGES.CONFIRM_DELETE`).
  - `FunnelForm.vue` — excluir funil.
- Trocar os `alert()` de erro/validação por `useAlert()` (toast) — `StageForm.vue`, `MoveItemModal.vue`, `FunnelForm.vue`.

**Arquivos:** `KanbanBoard.vue`, `FunnelForm.vue`, `StageForm.vue`, `MoveItemModal.vue`.

**Aceite:** nenhuma ação destrutiva usa popup nativo; confirmações via `Dialog`, erros via toast. Comportamento (confirmar/cancelar) idêntico ao atual.

---

## Checklist final (qualquer um dos 3)
- [ ] ESLint 0 erros (`pnpm exec eslint --fix` nos arquivos tocados)
- [ ] Specs Vue do Kanban verdes (`pnpm exec vitest run app/javascript/dashboard/components-next/Kanban app/javascript/dashboard/routes/dashboard/kanban`)
- [ ] Build assets (`RAILS_ENV=production bundle exec rake assets:precompile`) + restart (`sudo /bin/systemctl restart chatwoot.target`)
- [ ] Validar no `nicolas.chatspx.app`
- [ ] Nada na frota; commits só após aprovação visual
