# Kanban ChatSPX — tempo real de verdade (board multi-usuário)

> ## Resultado da Fase 0 (staging `nicolas`, 2026-08-03)
>
> Rodado na branch `nicolas` (HEAD `cf77fc4a0`), que **contém** `cbf5a75775` (`git merge-base --is-ancestor` → ok). Sidekiq vivo (`chatwoot-worker.1.service`), fila `:critical` com profundidade 0 e latência 0s.
>
> Prova de cadeia (mover cartão #565 do funil #2 dentro de transação com rollback, com `ActionCableBroadcastJob.perform_later` interceptado):
>
> - **O backend dispara.** `evento=funnel_item.moved`, 18 tokens, payload `{id, funnel_id, funnel_stage_id, conversation_id, moved_at, moved_by_id, position, account_id}`. Logo o F5 **não** é falta de deploy — é buraco de front (B1/B2) e de cobertura (B3–B8).
> - **B2 confirmado:** o payload não tem nada de renderizável (sem contato, status, prioridade, labels).
> - **Armadilha 4 confirmada e pior do que o texto sugeria:** o funil #2 tem `team_id=1` e o time #1 está **vazio**; pela `FunnelPolicy` só os 2 administradores conseguem abrir esse funil, mas o broadcast vai para os **18** usuários da conta. 16 pessoas recebem metadado de card que não podem ver. A restrição da 1.4 é obrigatória, não opcional.
> - **Correção de rota na 1.4:** o alcance certo é o da `FunnelPolicy` (admin **ou** membro do `funnel.team_id`; funil "Geral" com `team_id` nil = **só admin**), e não os membros das inboxes como o texto original propunha — `inbox_ids` filtra quais conversas entram no funil, não quem enxerga o funil.
>
> **Desvio do plano — flag `kanban_realtime` não foi criada.** `accounts.feature_flags` é bitmask `bigint` (máx 63 bits) e o fork já tem 65 entradas em `config/features.yml`; uma flag nova nasceria no bit 66 e daria `RangeError` ao habilitar — seria código morto. Em vez disso os dispatches novos têm um **kill switch por ENV** (`KANBAN_REALTIME_ENABLED=false`), que dá a mesma válvula operacional do §Rollout sem gastar bit.

**Problema relatado:** duas pessoas com o mesmo Kanban aberto. Uma arrasta o card, a outra só vê depois de dar F5.

**Branch base:** `producao` (`f542675b77`) · **Flag guarda-chuva:** `kanban_realtime` (nova, ver §Rollout)
**Risco geral:** médio — nenhuma migration, mas mexe em serviços que já rodam em produção e adiciona tráfego na fila `:critical` do Sidekiq.
**Validação:** staging (`nicolas.chatspx.app`) com **dois navegadores diferentes** (não duas abas — ver §Aceite).

> Ordem de execução: **Fase 0 → 1 → 2 → 3 → 4 → 5**. As fases 1 e 2 resolvem ~90% do que o usuário sente. As fases 3–5 fecham o resto. Cada fase é entregável e testável isoladamente.

---

## 0. Leia isto antes de começar — metade já existe

Não comece do zero. A infraestrutura de tempo real do move **já foi implementada** no commit `cbf5a75775` ("feat(kanban): Fase 4 — real-time de moves + notas internas no card", 24/06/2026) e está na branch `producao`. A cadeia completa hoje é:

| # | Camada | Arquivo | O que faz |
|---|--------|---------|-----------|
| 1 | Serviço | `app/services/funnel_items/move_service.rb:63-72` | `broadcast_move` → `dispatcher.dispatch(FUNNEL_ITEM_MOVED, ...)`, só quando `stage_changed` |
| 2 | Evento | `lib/events/types.rb:72` | `FUNNEL_ITEM_MOVED = 'funnel_item.moved'` |
| 3 | Dispatcher | `app/dispatchers/sync_dispatcher.rb` | `ActionCableListener` é listener **síncrono** (roda na thread do request) |
| 4 | Listener | `app/listeners/action_cable_listener.rb:138-145` | `funnel_item_moved` → `broadcast(account, account.users.pluck(:pubsub_token), ...)` |
| 5 | Broadcast | `app/listeners/action_cable_listener.rb:336-345` | injeta `account_id` + `performer` (via `Current.user`) e enfileira `ActionCableBroadcastJob` |
| 6 | Job | `app/jobs/action_cable_broadcast_job.rb` | `ActionCable.server.broadcast(pubsub_token, {event:, data:})` — fila `:critical` |
| 7 | Frontend (socket) | `app/javascript/dashboard/helper/actionCable.js:44,57-59` | `'funnel_item.moved'` → `onFunnelItemMoved` → `kanban/applyRemoteMove` |
| 8 | Frontend (store) | `app/javascript/dashboard/store/modules/kanban/actions.js:798-843` | `applyRemoteMove`: guard de self-echo por `performer.id`, last-write-wins por `moved_at`, commit `UPDATE_FUNNEL_ITEM` |
| 9 | Teste | `spec/services/funnel_items/move_service_broadcast_spec.rb` | 4 examples cobrindo dispatch/no-op/falha |

**Conclusão:** o trabalho aqui é **fechar buracos numa cadeia existente**, não construir uma nova. Reescrever a cadeia é retrabalho e vai quebrar o spec acima.

---

## 1. Por que ainda pede F5 — os 10 buracos

Ordenados por impacto no que o usuário relatou.

### B1 — O card desconhecido é descartado (causa nº 1 do F5)

`actions.js:814-815`:
```js
// We can only relocate an item we already hold; otherwise it shows on next load.
const existing = state.funnelItems[data.id];
if (!existing) return;
```

Se a pessoa B não tem aquele card no store, o evento é **silenciosamente jogado fora**. E B frequentemente não tem:
- `kanban_cursor_loading` está **ligado** (`config/features.yml:230-233`) → as colunas carregam paginadas por cursor; card fora da primeira página não está no store;
- filtro/saved view ativo em B pode ter excluído o card;
- coluna colapsada / não carregada.

Cenário exato do relato: A arrasta um card **de uma coluna que B não carregou até o fim** → B não vê nada até o F5.

### B2 — O payload é magro demais para renderizar um card

`app/models/funnel_item.rb:65-78` manda só `id, funnel_id, funnel_stage_id, conversation_id, moved_at, moved_by_id, position`. Não tem nome do contato, status, prioridade, labels, avatar, última mensagem. Ou seja: **mesmo que o front quisesse inserir o card de B1, não teria o que desenhar.** B1 e B2 têm que ser resolvidos juntos.

### B3 — Card novo entrando no board não aparece

- Conversa nova entrando no funil via `MoveService` (primeira colocação): dispara o evento, mas o receptor cai em B1 → invisível.
- **Cartão de tarefa** (`app/controllers/concerns/kanban/funnel_item_task_cards.rb`, via `FunnelItemsController#create`): **não dispara evento nenhum**.
- Backfill (`Kanban::BackfillFunnelItemsJob`) e automações (`Kanban::AutomationEngineService`, `Kanban::MoveConversationToAutomatedStageService`, `Kanban::SlaMonitorJob`) idem — passam pelo `MoveService`, então disparam, mas esbarram em B1.

### B4 — Exclusão de card não é transmitida

`FunnelItemsController#destroy` faz `@funnel_item.destroy!` + `head :ok`, sem dispatch. O card vira **fantasma** na tela do outro: some para A, continua clicável para B, e clicar nele dá 404.

### B5 — Reordenação dentro da coluna não é transmitida

`app/services/funnel_items/reorder_service.rb` usa `update_all` (de propósito, para não disparar `set_moved_at`) e **não emite evento algum**. Arrastar para cima/baixo na mesma coluna nunca chega no outro.

### B6 — Colunas não são tempo real

`app/controllers/api/v1/accounts/funnel_stages_controller.rb` (`create`/`update`/`destroy`) e `funnels#reorder_stages` não disparam nada. Criar, renomear, recolorir, apagar ou reordenar coluna → F5 obrigatório. Pior: se A **apaga** uma coluna e B arrasta um card para ela, B toma erro 404 sem explicação.

### B7 — Bulk move vira tempestade de eventos

`app/controllers/concerns/kanban/funnel_items_bulk_actions.rb:16` chama `FunnelItems::MoveService` **por item**. Mover 50 cards de uma vez = 50 dispatches → 50 `ActionCableBroadcastJob` na fila `:critical`, cada um fazendo N `ActionCable.server.broadcast` (um por usuário da conta). Numa conta com 30 agentes isso é 1.500 publicações. Precisa de evento agregado.

### B8 — Zero resync ao reconectar

`app/javascript/dashboard/helper/ReconnectService.js:125-137` — `handleRouteSpecificFetch` só trata rota de conversa, inbox e notificação. As rotas `kanban_index` e `kanban_funnel` (`app/javascript/dashboard/routes/dashboard/kanban/routes.js:16,22`) **não têm branch**. Resultado: qualquer queda de websocket (troca de wifi, notebook que dormiu, deploy) deixa o board desatualizado **para sempre** — exatamente o sintoma "só o F5 resolve".

### B9 — Sem feedback visual

O card teleporta sem nenhuma indicação de que foi outra pessoa. Gera desconfiança ("bugou?") e move acidental por cima do move do colega.

### B10 — Filtro e dedupe ignorados na inserção

Dois detalhes que **vão gerar bug se ignorados** quando a Fase 2 passar a inserir cards vindos do socket:
- `state.viewFilters` (saved views / `KanbanFilterSelect.vue`) — inserir sem filtrar faz aparecer card que o usuário filtrou fora;
- `deduplicate_by_contact_phone` (`funnel_items_controller.rb`) — o `index` **colapsa cards por telefone normalizado** (com o ajuste do 9º dígito BR). Um card inserido pelo socket pode duplicar visualmente um que já está na tela com outro `id`. O dedupe precisa ser replicado no front na inserção.

---

## 2. Armadilhas técnicas (leia antes de escrever código)

1. **O payload passa por Sidekiq com `strict_args`.** `ActionCableBroadcastJob` é enfileirado, então o payload precisa ser **só tipo JSON nativo**. Já existe cicatriz disso em `funnel_item.rb:73-76` (`position&.to_f`, porque `BigDecimal` é rejeitado). Regra: nada de `BigDecimal`, `Time`/`ActiveSupport::TimeWithZone` cru (use `.iso8601`), objeto ActiveRecord ou `Symbol` fora de chave de Hash.

2. **`Current.user` só existe no request.** O `broadcast` injeta `performer` a partir de `Current.user` (linha 342). Em move disparado por job (`SlaMonitorJob`, `AutomationEngineService`, backfill) `Current.user` é `nil` → **sem `performer`**. Logo o guard de self-echo do front não pode ser a única defesa contra reaplicar evento: a lógica precisa ser idempotente por si (comparar estado atual vs. alvo antes de commitar). O código atual já faz isso em `actions.js:817-821` — preserve esse padrão nos handlers novos.

3. **O listener é síncrono.** `ActionCableListener` está no `SyncDispatcher`, ou seja, roda **dentro da transação/request**. Qualquer coisa cara ali (query pesada para montar payload) entra no tempo de resposta do drag. Monte o payload com os dados já carregados; se precisar de query, use `includes` no serviço, não no listener.

4. **Broadcast é account-wide, sem checagem de permissão.** `action_cable_listener.rb:143` faz `account.users.pluck(:pubsub_token)` — manda para **todos** os usuários da conta, inclusive quem não tem acesso àquele funil/inbox/time. Isso já é o comportamento atual e vaza metadado de card (nome de contato, telefone) para quem não deveria ver, especialmente com `team_message_isolation` ligado. **Tratar na Fase 1** (ver tarefa 1.4) — não é aceitável ampliar o payload (B2) mantendo o alcance atual.

5. **O partial jbuilder não serve direto para broadcast.** `app/views/api/v1/models/_funnel_item.json.jbuilder` depende de `@labels_by_title` e `@last_messages_by_conversation_id`, populados só pelo controller. Ele é defensivo (`|| {}`, `&.[]`), então não quebra, mas devolveria labels sem cor e sem última mensagem. **Decisão: montar o payload em Ruby (`FunnelItem#push_event_data` estendido), não renderizar jbuilder fora do controller.** Manter os dois em sincronia é responsabilidade da Fase 1 (tarefa 1.2).

6. **A lista do `vuedraggable` é one-way.** O store já aplica move e reorder **otimisticamente** e reverte no erro (`actions.js:591-626` e `636-653`, com comentário explicando que esperar o PATCH fazia o card voltar e pular — 0,26s a 1,63s medidos). Não remova o otimismo ao adicionar o tempo real; o evento remoto é para os **outros**, não para quem arrastou.

---

## Fase 0 — Diagnóstico (obrigatória, ~30 min, antes de qualquer código)

**Por quê:** o código do §0 está na branch `producao` desde 24/06, mas a frota nem sempre está no HEAD da branch. Se a VM onde o problema foi relatado estiver rodando build anterior a `cbf5a75775`, **nenhum move é tempo real** e o diagnóstico muda de figura (deploy resolve parte).

**O que fazer:**

1. Descobrir **em qual VM/cliente** o problema foi relatado.
2. Na VM, confirmar se o commit está no build rodando:
   ```bash
   cd /home/chatwoot/chatwoot
   git log -1 --format='%h %ad %s' --date=short
   git merge-base --is-ancestor cbf5a75775 HEAD && echo "TEM realtime de move" || echo "NAO TEM — deploy resolve parte do problema"
   ```
3. Confirmar que o **assets** buildado corresponde ao código (o front é o lado que consome o evento):
   ```bash
   ls -la public/packs/ | head    # data do build vs. data do commit
   ```
4. Reproduzir com dois navegadores e o **DevTools aberto no receptor**:
   - Aba Network → filtro `WS` → frame do `ActionCable` → arrastar card no navegador A;
   - **Chegou frame com `"event":"funnel_item.moved"`?**
     - **Não chegou** → problema é backend/deploy: cheque `Sidekiq` fila `:critical` (`bundle exec sidekiq` rodando? fila entupida?) e o log por `MoveService broadcast failed`.
     - **Chegou mas o card não mexeu** → é B1 (card não estava no store) ou B10. Confirme no console: `$store.state.kanban.funnelItems[<id>]`.
5. Registrar o resultado no topo deste documento antes de seguir.

**Aceite:** você sabe dizer, com evidência, se o evento chega no navegador do receptor hoje. Isso define se a Fase 1 é "corrigir" ou "corrigir + deployar".

---

## Fase 1 — Move de card confiável (o núcleo)

**Por quê:** resolve o cenário exato do relato, incluindo o caso em que o receptor não tem o card carregado (B1+B2).

### 1.1 — Engordar o payload do card
Estender `FunnelItem#push_event_data` (`app/models/funnel_item.rb:65-78`) para carregar tudo que o `KanbanCard.vue` precisa desenhar — espelhando os campos de `app/views/api/v1/models/_funnel_item.json.jbuilder`:

- básico já existente: `id, funnel_id, funnel_stage_id, conversation_id, moved_at, moved_by_id, position`
- cartão de tarefa: `is_task, title, description, assignee_id, assignee{id,name,thumbnail}`
- conversa: `conversation{ id, display_id, status, priority, contact_id, inbox_id, account_id, assignee_id, last_activity_at, waiting_since, custom_attributes (só `funnel_<id>_*`), labels[{title,color}], contact{id,name,phone_number,thumbnail} }`

Regras:
- **tipos JSON nativos** (armadilha 1): `moved_at`/`last_activity_at`/`waiting_since` → `.iso8601`; `position` → `.to_f` (já é assim);
- labels: buscar as cores com **uma** query indexada por título (`account.labels.index_by`), não N+1 — e como o listener é síncrono (armadilha 3), fazer isso no **serviço**, passando o resultado pronto no `event.data`, ou aceitar cor default `#94a3b8` no broadcast (como o partial já faz quando `@labels_by_title` é nil). **Recomendação: cor default no broadcast** — mais barato e o front já tem a paleta;
- `last_message`: **fora do payload** (exigiria query extra no caminho síncrono do drag). O card remoto mostra a última mensagem que já tinha, ou vazio até o próximo `message.created` (que já é tratado por `syncConversationFromRealtime`).

Adicionar comentário no partial jbuilder e no `push_event_data` apontando um para o outro ("mantenha em sincronia").

### 1.2 — Um teste que trava os dois em sincronia
Spec novo (`spec/models/funnel_item_push_event_data_spec.rb`) garantindo que as chaves de `push_event_data` são um **superconjunto compatível** dos campos do partial, e que o payload sobrevive a `JSON.generate` sem tipo exótico (protege contra a armadilha 1).

### 1.3 — Frontend: parar de descartar card desconhecido
Em `applyRemoteMove` (`actions.js:798-843`), trocar o `if (!existing) return;` por:
- se **não existe** e o payload traz `conversation`/`title` → `commit(types.ADD_FUNNEL_ITEM, data)` (mutação já existe em `mutation-types.js`);
- **antes de inserir**, aplicar (B10): (a) filtro de `state.viewFilters`; (b) dedupe por telefone normalizado espelhando `deduplicate_by_contact_phone` do controller — extrair isso para um helper testável, ex. `store/modules/kanban/helpers/dedupe.js`;
- se **existe** → mantém o caminho atual (relocate + last-write-wins).

Manter o guard de `performer.id` e o comparativo `targetStage === currentStage` (armadilha 2 — idempotência).

### 1.4 — Restringir o alcance do broadcast (armadilha 4)
Em `action_cable_listener.rb:138-145`, trocar `account.users.pluck(:pubsub_token)` por um conjunto que respeite o acesso ao funil:
- usuários **administradores** da conta; **mais**
- membros das inboxes do funil (`funnel.inbox_ids`) — espelhar o helper `user_tokens(account, inbox.members)` já usado por `assignee_changed` (linha 129-134);
- se `funnel.team_id` presente, restringir aos membros do time.

Spec: usuário sem acesso ao funil **não** recebe o token no broadcast.

> Se essa restrição se mostrar arriscada (regressão de "não vejo mais nada"), entregue-a atrás da flag `kanban_realtime` e mantenha o comportamento antigo desligado — mas **não** amplie o payload da 1.1 sem ela.

**Arquivos:** `app/models/funnel_item.rb`, `app/listeners/action_cable_listener.rb`, `app/services/funnel_items/move_service.rb` (se precisar pré-carregar associações), `app/javascript/dashboard/store/modules/kanban/actions.js`, novo `helpers/dedupe.js`, specs.

**Aceite:**
- A arrasta card entre colunas → B vê em **< 2s**, sem F5.
- Funciona **mesmo quando B nunca rolou até aquele card** (teste com uma coluna de 100+ cards e `kanban_cursor_loading` ligado).
- O card que aparece em B está **completo** (nome, avatar, labels, prioridade), não um esqueleto.
- Card que não passa no filtro ativo de B **não** aparece em B.
- Não duplica card do mesmo contato.
- Quem arrastou (A) não vê o card pular duas vezes.

---

## Fase 2 — Card entra e sai do board

**Por quê:** fecha B3 e B4 — hoje card novo e card apagado exigem F5.

### 2.1 — `funnel_item.created`
- Novo evento em `lib/events/types.rb`: `FUNNEL_ITEM_CREATED = 'funnel_item.created'`.
- Disparar em: `FunnelItemsController#create` quando for **cartão de tarefa** (`Kanban::FunnelItemTaskCards#create_task_card`).
- Para conversa, o `MoveService` já dispara `moved` na primeira colocação — **não duplicar**; com a Fase 1.3 o `moved` já insere o card. Documente essa assimetria com comentário no código (é a decisão mais fácil de alguém "consertar" errado depois).
- Listener `funnel_item_created` → mesmo alcance da 1.4 → front: `onFunnelItemCreated` → `kanban/applyRemoteCreate` (insere com filtro + dedupe, reusando o helper da 1.3).

### 2.2 — `funnel_item.deleted`
- `FUNNEL_ITEM_DELETED = 'funnel_item.deleted'`.
- Disparar em `FunnelItemsController#destroy`, **capturando `id`/`funnel_id`/`funnel_stage_id` antes do `destroy!`** (depois o objeto está congelado).
- Payload mínimo: `{ id, funnel_id, funnel_stage_id }`.
- Front: `applyRemoteDelete` → `commit(types.DELETE_FUNNEL_ITEM, id)` — guardado por `funnel_id === activeFunnelId`.

### 2.3 — Bulk sem tempestade (B7)
Em `Kanban::FunnelItemsBulkActions`, envolver o loop: suprimir o broadcast individual do `MoveService` (parâmetro `broadcast: false` no initializer, default `true` para não mexer nas chamadas existentes) e emitir **um** evento agregado ao final:
- `FUNNEL_ITEMS_BULK_MOVED = 'funnel_items.bulk_moved'`, payload `{ funnel_id, items: [payload completo por item] }` — com **teto** (ex.: acima de 50 itens, mandar `{ funnel_id, stage_ids: [...], refetch: true }` e o front refaz o fetch daquelas colunas em vez de receber um payload gigante).
- Front: `applyRemoteBulk` → itera reusando `applyRemoteMove`/`applyRemoteCreate`, ou dispara `fetchFunnelItems` das stages afetadas quando `refetch: true`.

**Arquivos:** `lib/events/types.rb`, `app/controllers/api/v1/accounts/funnel_items_controller.rb`, `app/controllers/concerns/kanban/funnel_item_task_cards.rb`, `app/controllers/concerns/kanban/funnel_items_bulk_actions.rb`, `app/services/funnel_items/move_service.rb`, `app/listeners/action_cable_listener.rb`, `actionCable.js`, `store/modules/kanban/actions.js`, specs.

**Aceite:**
- A cria cartão de tarefa → aparece em B sem F5.
- Nova conversa entra no funil por automação → aparece em B.
- A apaga um card → some em B (sem fantasma clicável).
- Bulk move de 50 cards → B converge, e o Sidekiq **não** recebe 50 jobs (verificar no painel do Sidekiq / log).

---

## Fase 3 — Reordenação dentro da coluna

**Por quê:** fecha B5. Menos crítico que 1 e 2, mas é o mesmo gesto de arrastar — o usuário não distingue "mudou de coluna" de "mudou de ordem", e a inconsistência de só um funcionar parece bug.

**O que fazer:**
- `FUNNEL_ITEMS_REORDERED = 'funnel_items.reordered'`.
- Disparar em `FunnelItems::ReorderService#perform`, **depois** da transação, com `{ funnel_id, funnel_stage_id, positions: [{ id, position }] }` (`position` já é `Integer` 1-based ali — sem BigDecimal, seguro).
- Front: `applyRemoteReorder` → `commit(types.SET_FUNNEL_ITEM_POSITIONS, { positions })` (mutação **já existe**, é a mesma usada pelo otimismo em `actions.js:646`).
- Ignorar ids que o receptor não tem (reorder de card desconhecido não justifica fetch).
- Self-echo: o `ReorderService` roda em request, então `performer` vem preenchido — reusar o mesmo guard.

**Arquivos:** `app/services/funnel_items/reorder_service.rb`, `lib/events/types.rb`, `action_cable_listener.rb`, `actionCable.js`, `actions.js`, spec novo `spec/services/funnel_items/reorder_service_broadcast_spec.rb` (espelhar o de move).

**Aceite:** A reordena cards dentro de uma coluna → a ordem em B acompanha, sem F5 e sem o card "pular" na tela de A.

---

## Fase 4 — Colunas em tempo real

**Por quê:** fecha B6. Renomear/criar/apagar coluna hoje só chega com F5 — e o caso "A apaga a coluna, B arrasta card para ela" produz um 404 sem explicação.

**Decisão de design (importante):** colunas mudam **raramente** e são poucas. Em vez de 4 eventos finos (`created`/`updated`/`deleted`/`reordered`), emitir **um evento grosso e idempotente**:

- `FUNNEL_STAGES_CHANGED = 'funnel_stages.changed'`, payload `{ funnel_id, stages: [<lista completa e ordenada de stages>] }`.
- Front: `applyRemoteStages` → `commit(types.SET_FUNNEL_STAGES, { funnelId, stages })`. Um só handler, sem ordem de chegada para se preocupar, sem estado parcial.
- Disparar em `FunnelStagesController#create`, `#update`, `#destroy` e em `funnels#reorder_stages`.

Cuidados:
- se a coluna **ativa/visível** de B sumiu, mover o scroll/seleção de B para uma coluna válida em vez de deixar tela vazia;
- se B tem card na coluna apagada, remover os cards órfãos **do store** — no banco não sobra nada (`FunnelStage has_many :funnel_items, dependent: :destroy`, `app/models/funnel_stage.rb:18`), mas o Vuex de B continua com eles até o F5;
- reusar o serializer de stage já existente (`app/views/api/v1/accounts/funnels/funnel_stages/`) para montar a lista, mantendo os mesmos campos (`name, position, color, automation_type, settings{wip_limit, sla_hours}`).

**Arquivos:** `app/controllers/api/v1/accounts/funnel_stages_controller.rb`, `app/controllers/api/v1/accounts/funnels_controller.rb` (`reorder_stages`), `lib/events/types.rb`, `action_cable_listener.rb`, `actionCable.js`, `actions.js`, spec de request.

**Aceite:** A cria / renomeia / recolore / reordena / apaga coluna → B acompanha sem F5. B não fica com coluna fantasma nem tela vazia.

---

## Fase 5 — Resync no reconnect + destaque visual

### 5.1 — Resync (fecha B8, o "F5 eterno")
Adicionar branch de kanban em `ReconnectService.handleRouteSpecificFetch` (`app/javascript/dashboard/helper/ReconnectService.js:125-137`):
```js
} else if (isAKanbanRoute(currentRoute)) {
  await this.fetchKanbanOnReconnect();
}
```
- `isAKanbanRoute`: nomes `kanban_index` e `kanban_funnel` (`routes/dashboard/kanban/routes.js:16,22`);
- `fetchKanbanOnReconnect`: refetch das stages + dos itens do funil ativo, respeitando o modo de visualização atual e os filtros ativos. **Reuse as actions existentes**, não escreva fetch novo — `bootstrapView` (`actions.js:933`) já roteia por modo de visualização e é o ponto de entrada certo; abaixo dele estão `fetchFunnelStages` (`:333`), `fetchFunnelItems` (`:504`) e `bootstrapListView` (`:857`);
- **debounce**: se o socket oscilar, não disparar N refetchs (o `ReconnectService` já tem noção de `getSecondsSinceDisconnect` — reusar).

Complemento barato e de alto valor: escutar `BUS_EVENTS.WEBSOCKET_DISCONNECT` / `WEBSOCKET_RECONNECT` (já emitidos em `actionCable.js:101,113-115`) e mostrar no header do board um selo **"Reconectando…"**, para o usuário saber que a tela pode estar defasada em vez de achar que travou.

### 5.2 — Destaque no card (fecha B9)
Quando um card chega/muda por evento remoto (não pelo próprio usuário):
- aplicar classe temporária no `KanbanCard.vue` — borda/glow animado por ~2s (`kanban-theme.css` já centraliza os tokens visuais do board; adicionar lá);
- micro-legenda "movido por {nome}" usando `data.performer.name` (vem de graça do `broadcast`, linha 342), sumindo junto com o destaque;
- quando `performer` for `nil` (move por automação/job — armadilha 2), usar "movido automaticamente";
- respeitar `prefers-reduced-motion`.

Sem presença/avatares no header e sem "fulano está arrastando" — **fora de escopo** (ver §Fora de escopo).

**Arquivos:** `helper/ReconnectService.js`, `routes/dashboard/kanban/routes.js` (se precisar exportar o helper de rota), `components-next/Kanban/KanbanCard.vue`, `kanban-theme.css`, `KanbanBoard.vue` (selo de reconexão), i18n `kanban.json` (**en + pt_BR**), spec de `ReconnectService`.

**Aceite:**
- Derrubar a rede por 30s no navegador de B (DevTools → Network → Offline), A move 3 cards, religar → B converge sozinho, **sem F5**;
- card que chegou de outra pessoa pisca e mostra quem moveu;
- com `prefers-reduced-motion` não pisca.

---

## Contrato de eventos (consolidado)

| Evento | Origem | Payload | Handler no front | Fase |
|--------|--------|---------|------------------|------|
| `funnel_item.moved` | `FunnelItems::MoveService` | card completo (§1.1) | `applyRemoteMove` (move **ou** insere) | 1 |
| `funnel_item.created` | `FunnelItemTaskCards` (tarefa) | card completo | `applyRemoteCreate` | 2 |
| `funnel_item.deleted` | `FunnelItemsController#destroy` | `{id, funnel_id, funnel_stage_id}` | `applyRemoteDelete` | 2 |
| `funnel_items.bulk_moved` | `FunnelItemsBulkActions` | `{funnel_id, items[]}` ou `{funnel_id, stage_ids[], refetch:true}` | `applyRemoteBulk` | 2 |
| `funnel_items.reordered` | `FunnelItems::ReorderService` | `{funnel_id, funnel_stage_id, positions[]}` | `applyRemoteReorder` | 3 |
| `funnel_stages.changed` | `FunnelStagesController`, `funnels#reorder_stages` | `{funnel_id, stages[]}` | `applyRemoteStages` | 4 |

**Invariantes que valem para todos:**
1. Nome do evento com `.` vira método do listener com `_` (`Events::Base#method_name` = `name.tr('.', '_')`) — `funnel_items.reordered` → `def funnel_items_reordered`.
2. Todo handler **começa** com `if (Number(data.funnel_id) !== Number(state.activeFunnelId)) return;`.
3. Todo handler é **idempotente** (aplicar duas vezes = aplicar uma).
4. Todo handler é **best-effort**: `try/catch` que nunca lança para fora do websocket (padrão já em `actions.js:840-842`).
5. Todo dispatch no backend é `rescue StandardError` + `Rails.logger.warn` — **um broadcast quebrado nunca pode quebrar a ação do usuário** (padrão já em `move_service.rb:70-72`).

---

## Testes

**Backend (RSpec)** — espelhar `spec/services/funnel_items/move_service_broadcast_spec.rb`, que já é o modelo certo (dispara / não dispara em no-op / não quebra a ação quando o broadcast falha):
- `spec/models/funnel_item_push_event_data_spec.rb` (novo, Fase 1.2)
- `spec/services/funnel_items/reorder_service_broadcast_spec.rb` (novo)
- `spec/listeners/action_cable_listener_spec.rb` — cobrir o alcance restrito da 1.4 (usuário sem acesso não recebe)
- requests: `funnel_items_controller` destroy/create-task, `funnel_stages_controller` CRUD, `funnels#reorder_stages`
- ajustar `spec/controllers/api/v1/accounts/funnel_items_bulk_update_spec.rb` para o evento agregado

**Frontend (Vitest)** — já existe suíte em `store/modules/specs/kanban/actions.spec.js`:
- `applyRemoteMove` com card **desconhecido** → insere
- `applyRemoteMove` com card conhecido → relocate (não duplica)
- filtro ativo → não insere
- dedupe por telefone → não duplica contato
- `applyRemoteDelete` / `applyRemoteReorder` / `applyRemoteStages`
- helper de dedupe isolado (`helpers/dedupe.js`) com os casos BR (12 dígitos com `55` ganhando o 9)
- `ReconnectService` → rota kanban dispara refetch

**Comandos:**
```bash
bundle exec rspec spec/services/funnel_items spec/models/funnel_item_push_event_data_spec.rb spec/listeners
pnpm test -- app/javascript/dashboard/store/modules/specs/kanban
bundle exec rubocop -a app/services/funnel_items app/listeners app/models/funnel_item.rb
pnpm eslint --fix app/javascript/dashboard/store/modules/kanban app/javascript/dashboard/helper
```

---

## Aceite final — roteiro com 2 navegadores

Use **dois navegadores diferentes** (ou um normal + um anônimo) com **dois usuários distintos**. Duas abas do mesmo usuário compartilham o mesmo `pubsub_token` e podem mascarar bug de alcance.

| # | Ação em A | Esperado em B (sem F5, < 2s) |
|---|-----------|------------------------------|
| 1 | Arrasta card entre colunas | Card muda de coluna |
| 2 | Arrasta card que B **nunca rolou até ver** | Card **aparece** na coluna de destino, completo |
| 3 | Reordena cards na mesma coluna | Ordem acompanha |
| 4 | Cria cartão de tarefa | Card aparece |
| 5 | Apaga um card | Card some (e não é clicável) |
| 6 | Bulk move de 20 cards | Todos convergem; Sidekiq não estoura |
| 7 | Renomeia e recolore uma coluna | Coluna atualiza |
| 8 | Apaga uma coluna que B está olhando | Coluna some, sem tela vazia/travada |
| 9 | B fica offline 30s, A move 3 cards, B volta | B converge sozinho |
| 10 | Qualquer move de A | Card pisca em B com "movido por A" |
| 11 | B com filtro que exclui o card, A move o card | Card **não** aparece em B |
| 12 | A e B arrastam o **mesmo** card ao mesmo tempo | Convergem no mesmo estado (last-write-wins por `moved_at`); ninguém fica com tela divergente |

Item 12 é o mais fácil de quebrar — teste de propósito.

---

## Rollout

1. **Flag `kanban_realtime`** em `config/features.yml` (`chatwoot_internal: true`, `enabled: false` inicialmente), envolvendo os **dispatches novos** no backend e os **handlers novos** no front. O `funnel_item.moved` que já roda hoje fica **fora da flag** (não regride o que já funciona) — exceto o payload engordado da 1.1, que pode ir junto sem risco (campo a mais no JSON é ignorado por front antigo).
2. Deploy em **staging** → roteiro de aceite completo.
3. Ligar a flag em **uma** conta piloto por 48h. Monitorar: fila `:critical` do Sidekiq (profundidade e latência) e o log por `broadcast failed`.
4. Se a fila sofrer, o parafuso a apertar é a **1.4** (alcance) e a **2.3** (agregação), nessa ordem — não desligar o recurso inteiro.
5. Rollout na frota seguindo o procedimento padrão (bundle + assets pré-buildados; `db:migrate:status` antes de qualquer restart; restart é do usuário).

**Sem migration** — nenhuma fase toca schema. Se alguém propuser tabela nova, é sinal de que saiu do escopo.

---

## Fora de escopo (não faça sem nova aprovação)

- Presença: avatares de quem está com o board aberto, "fulano está arrastando", cursores ao vivo. Exigiria canal de presença novo (espelhando `RoomChannel#presence`) e mais que dobra o escopo.
- Bloqueio/lock de card durante o arraste.
- Histórico/auditoria visual de movimentações no card.
- Tempo real das visões `ListView` / `CalendarView` / `DashboardView` — as fases acima atendem o **board**; se as outras visões lerem o mesmo store, ganham de graça, mas **não** são critério de aceite.
- Trocar ActionCable por outro transporte.

---

## Execução — o que foi entregue (2026-08-03, branch `nicolas`)

Fases 0 a 5 implementadas, commitadas, deployadas no staging e **validadas ao vivo**.

| Commit | Fase |
|--------|------|
| `923201df0` | 1 — payload completo + insert do card desconhecido + alcance restrito |
| `82ace33a3` | 2 — `funnel_item.created` / `.deleted` + bulk agregado |
| `b7cde7eb6` | 3 — `funnel_items.reordered` |
| `749fbe5d2` | 4 — `funnel_stages.changed` |
| `8b30ffea2` | 5 — resync no reconnect + destaque no card |

### Desvios do plano (e por quê)

1. **Sem a flag `kanban_realtime`.** `config/features.yml` já tem 65 entradas e `accounts.feature_flags` é bitmask `bigint` (63 bits úteis): a flag nasceria no bit 66 e daria `RangeError` ao ser habilitada. No lugar dela, `Kanban::Realtime` (`app/services/kanban/realtime.rb`) concentra o rescue best-effort **e** o kill switch `KANBAN_REALTIME_ENABLED=false`, que dá a mesma válvula do §Rollout sem gastar bit.
2. **1.4 usa a `FunnelPolicy`, não as inboxes.** O plano propunha membros das inboxes do funil; quem decide se alguém abre o funil é a `FunnelPolicy` (admin, ou membro do `funnel.team_id`; funil "Geral" = só admin). `inbox_ids` filtra conversas, não pessoas. Medido no staging: de 18 usuários da conta, o alcance caiu para os 2 que realmente conseguem abrir o funil.
3. **1.3 não filtra nem deduplica no store.** Os dois já existem, em camadas melhores: `viewFilters` é aplicado na **renderização** (`KanbanBoard.getFilteredItemsForStage`), e o dedupe por telefone (com 9º dígito BR) já está em `assignItemToStage` (`mutations.js`), espelhando o `deduplicate_by_contact_phone`. Filtrar no store deixaria o cache mentindo para contadores e busca, e o card não voltaria ao limpar o filtro. Por isso **não** foi criado o `helpers/dedupe.js`.
4. **Sem `spec/services/funnel_items/reorder_service_broadcast_spec.rb`?** Não — esse foi criado. O que **não** foi feito é ajustar `funnel_items_bulk_update_spec.rb`: ele cobre `bulk_update` (reatribuir/etiquetar/arquivar), que não passa pelo `MoveService`; o `bulk_move` ganhou cobertura nova em `funnel_items_realtime_spec.rb`.

### Validação ao vivo (staging, dois usuários)

Board aberto no navegador como **admin**; ações executadas server-side como **Realtime Test B** (`Current.user`), para o board receber os eventos como se um colega tivesse mexido:

| Item do roteiro | Resultado |
|---|---|
| 1 — card muda de coluna | ✅ 22→21 em "Novo", 14→15 em "Em atendimento", sem F5 |
| 2 — card que o receptor **nunca carregou** (etapa `resolved`, fora do store) | ✅ inserido completo em **2,8 s** (nome, telefone, status), com o badge |
| 4 — cartão de tarefa criado | ✅ aparece em 2,5 s (`isTask=true`) |
| 5 — card apagado | ✅ some do board, sem fantasma |
| 7 — coluna renomeada e recolorida | ✅ nome e cor mudam sozinhos |
| 8 — coluna restaurada | ✅ volta sozinha |
| 10 — "movido por {nome}" | ✅ `movido por Realtime Test B`, com o pulso no card |

Console do navegador: **0 erros**. Verificação server-side (`funnel_item.moved/created/deleted`, bulk com teto, reorder, `funnel_stages.changed`, kill switch, tipos JSON) toda verde, com rollback — nada ficou gravado.

**Pendente de QA do usuário:** itens 3 (reordenar arrastando), 6 (bulk de 20 pela UI), 9 (offline 30 s → reconverge — coberto por teste unitário do `ReconnectService`, não exercitado no navegador), 11 (filtro ativo) e 12 (dois arrastes simultâneos no mesmo card).

### Cenário de QA (staging) — funil #26 "QA Tempo Real"

Semeado por `task/qa_tempo_real_seed.rb` (limpa com `task/qa_tempo_real_clean.rb`).

Existe um **time/inbox/funil próprios** porque o roteiro exige dois usuários diferentes com o mesmo board aberto, e pela `FunnelPolicy` agente só enxerga funil do **seu time** — os dois usuários de teste não estavam em time nenhum, ou seja, não viam funil nenhum. Time `qa tempo real` = Realtime Test A (#15) + Realtime Test B (#16) + admin.

| Coluna | Cards no banco | Cards que o board carrega | Para que serve |
|---|---|---|---|
| Abertos | 46 (+1 tarefa) | 31 | 15 ficam FORA do store — é o item 2 do roteiro |
| Em Andamento | 12 (+2 tarefas) | todos | reordenar dentro da coluna (item 3) |
| Aguardando cliente | 8 | todos | destino neutro de arraste |
| Resolvidos | 10 | **0** | o board não carrega coluna `resolved`; arrastar daqui é o teste mais duro do "card desconhecido entra desenhado" |

Prioridade, responsável, etiqueta (`financeiro`/`duvida`/`reclamacao`/`agendamento`) e idade (4 min a 19 dias) variados, para ter o que filtrar (item 11) e para os trilhos de espera aparecerem.

Links de login para os três usuários: `./task/links-agentes-teste.sh rt-test-a@chatspx.test rt-test-b@chatspx.test dev@simplexsolucoes.com.br` (valem 5 min, uso único).

**Armadilhas encontradas ao montar o seed** (valem para qualquer seed de Kanban futuro):
- `Team` força o nome para **minúsculas** — `find_by(name: 'QA Tempo Real')` nunca acha e o script recria o time a cada rodada.
- Criar o time já cria um funil (`Team after_create → Kanban::CreateFunnelForTeamService`); não crie outro.
- A conversa precisa de `team_id` **igual ao do funil**, senão o `FunnelItemsQueryService` a filtra e o board nasce vazio. E conversa criada já `resolved` sem time bate na validação de encerramento por atribuição.
- Atribuir a conversa a um agente do time já cria o `funnel_item`; use `find_or_initialize_by`, não `create!` (unicidade conversation+funnel).
- A limpeza precisa de varredura de FK **recursiva** (`conversations → conversation_assignment_histories`, `teams → internal_channels → internal_channel_members`) e o `Inbox#destroy` explode no modelo `Campaign`, quebrado neste banco pelas migrations fantasma — daí o fallback para DELETE direto.

### Correção pós-QA (2026-08-03, `586acf86c`) — "atualiza uma vez e depois nunca mais"

Relatado pelo usuário no primeiro teste real. **Causa:** todo handler remoto começava descartando o evento quando `performer.id === currentUserId`. A intenção era evitar o eco da própria ação, mas isso vale por **usuário**, não por aba — então quem abrisse o board em **duas janelas** (ou desktop + notebook, ou testasse com o mesmo login nos dois navegadores) via a janela onde arrastou atualizar pelo otimismo local e a outra **nunca** acompanhar, mesmo com o evento chegando.

Medido no staging antes da correção: dois moves feitos como o próprio usuário logado, os dois eventos chegaram no `dispatch` e **nenhum** foi aplicado.

**Correção:** quem protege contra o eco é a **idempotência**, que já existia e não precisa saber quem fez. Quem arrastou já aplicou o movimento otimista, então o evento chega com a etapa que o card já tem e vira no-op — sem o segundo salto na tela. Mesma lógica nos outros handlers: criar é upsert, apagar o que já sumiu é no-op, o reorder grava as mesmas posições e a lista de colunas do servidor é a verdade. O `performer` continua no payload, agora só para o "movido por fulano" do destaque.

Validado ao vivo depois da correção: 3 movimentos seguidos como o **mesmo** usuário → board acompanhou os 3 (store e DOM); 2 movimentos como **outro** usuário → acompanhou com o selo "movido por Realtime Test B".

### Dois bugs de SQL achados no QA (2026-08-03) — não eram do tempo real

O usuário relatou "os dados não atualizam da maneira correta". Não era o websocket: eram duas ocorrências da **mesma armadilha de SQL com NULL**, pré-existentes e independentes deste plano.

**1. Coluna sem automação voltava vazia da API (`39ac72659`).** O board sempre manda `exclude_automation_type=resolved`, e o filtro era `where.not(funnel_stages: { automation_type: ... })` → SQL `automation_type != 'resolved'`. Como a coluna é nulável e `NULL != 'x'` vale NULL (não TRUE), **toda etapa sem automação sumia inteira da listagem** — "Em andamento", "Aguardando cliente", a maioria delas. Medido: etapa com 18 cards devolvia 18 sem o parâmetro e **0** com ele. Os cards continuavam chegando pelo websocket, então a coluna enchia ao vivo e esvaziava a cada recarga. Corrigido com `IS DISTINCT FROM` nos dois caminhos (cursor e legado); spec nova falha 4/4 sem a correção.

**2. Backfill morria com um cartão de tarefa no funil (`c1334114b`).** A subquery de "conversas que já estão no funil" incluía os cartões de tarefa, que têm `conversation_id` NULO — e `id NOT IN (1, 2, NULL)` nunca é verdadeiro. Bastava **um** cartão de tarefa para o backfill devolver zero candidatas para sempre e nenhuma conversa nova entrar no board. Medido no funil 26 (3 cartões de tarefa): 0 candidatas pelo jeito antigo, 3 ignorando os NULL.

> Vale varrer o resto do fork atrás do mesmo padrão: `where.not` em coluna nulável e `NOT IN` com subquery que pode conter NULL.

### Fechamento — revisão final (2026-08-03)

**Estado:** todas as 6 fases entregues, mais 3 correções que só apareceram no QA. Tudo commitado na branch `nicolas` e **LIVE no staging** (`c8dbe006d`). Produção/frota **não** promovidas.

| Commit | O quê |
|---|---|
| `923201df0` | F1 — payload completo, insert do card desconhecido, alcance pela FunnelPolicy |
| `82ace33a3` | F2 — `created`/`deleted` + bulk agregado |
| `b7cde7eb6` | F3 — `funnel_items.reordered` |
| `749fbe5d2` | F4 — `funnel_stages.changed` |
| `8b30ffea2` | F5 — resync no reconnect + destaque no card |
| `e695fd26e` | cenário de QA (seed + limpeza) |
| `586acf86c` | **fix** — board não acompanhava a outra janela do mesmo usuário |
| `39ac72659` | **fix** — coluna sem automação voltava vazia da API |
| `c1334114b` | **fix** — backfill morria com um cartão de tarefa |
| `c8dbe006d` | polimento da revisão (destaque só no card novo, comentário defasado, guarda de payload vazio) |

**Testes.** 132 exemplos RSpec das áreas tocadas + 110 do front, todos verdes. `spec/listeners` tem 10 falhas — **provadas pré-existentes**: rodei a suíte num worktree no commit base (`cf77fc4a0`) e deu exatamente as mesmas 10 (269 exemplos lá, 294 aqui, mesmas falhas). São de `hook_listener`, `automation_rule_listener`, `reporting_event_listener` e um `typing_on` com agent bot — nada do Kanban.

**Cobertura nova que trava regressão:**
- `funnel_item_push_event_data_spec` — payload × partial jbuilder e os tipos aceitos pelo Sidekiq
- `action_cable_listener_kanban_spec` — alcance por funil, teto do bulk, lista de colunas
- `funnel_items_realtime_spec` / `funnel_stages_realtime_spec` — os dispatches dos controllers e o kill switch
- `reorder_service_broadcast_spec`
- `funnel_items_exclude_automation_spec` — falha 4/4 sem a correção do `IS DISTINCT FROM`
- `funnel_items_backfill_service_spec` — falha 1/3 sem a correção do `NOT IN`
- 45 casos de front nos handlers remotos

**Conferido na revisão, com o resultado:**
- API × banco por coluna, depois de todas as correções: 40→31 (paginado), 16→16, 13→13, resolvidos→0. Bate.
- Tempo das chamadas do board: 127 ms (colunas) e 228–298 ms (cards, em paralelo). O que sobra de espera é o boot do SPA (~1,4 s), igual ao resto do sistema.
- Varredura por outras ocorrências de `where.not`/`NOT IN` em coluna nulável dentro do Kanban: as duas restantes (`assignee_id: nil` no relatório e o `NOT IN` do backfill já corrigido) estão corretas.

**Pendente:**
1. QA visual seu nos itens 3 (reordenar arrastando), 6 (bulk pela UI), 9 (offline 30 s), 11 (filtro ativo) e 12 (dois arrastes simultâneos no mesmo card).
2. Promoção para produção/frota — os dois bugs de NULL valem para **todos** os funis da frota, então essa promoção tem valor independente do tempo real.
3. Limpar o cenário de QA quando terminar: `RAILS_ENV=production bundle exec rails runner task/qa_tempo_real_clean.rb`.

### Nota para o monitoramento do rollout

Cada dispatch percorre **os dois** dispatchers (`Dispatcher#dispatch` chama sync **e** async), então todo evento do board enfileira também um `EventDispatcherJob` na `:critical` — que hoje é no-op (nenhum listener assíncrono trata evento de funil). Não é novo (o `funnel_item.moved` já fazia isso), mas conte 2 jobs por evento ao olhar a fila. A agregação da 2.3 é o que importa aqui: bulk de 50 cards saiu de ~100 jobs para 2.
