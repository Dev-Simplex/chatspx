# Kanban: desativar o pipeline "Geral" para agentes

> **Prompt de implementação** — branch `nicolas`, sem feature flag, **sem migration**.
> Correção pequena e de baixo risco: **esconder o funil "Geral" (default da conta) dos
> AGENTES**, mantendo-o para ADMINS. A mudança essencial é de **~2 linhas** numa policy;
> quase tudo o resto é teste e verificação defensiva. Antes de codar, leia
> `app/policies/funnel_policy.rb` e a §Armadilhas (há um risco real de "cards órfãos"
> que a decisão de produto já resolve).

---

## 1. Objetivo

Hoje **todo mundo** (agente e admin) vê o funil **"Geral"** no Kanban — o funil default da
conta (`Funnel` com `team_id: nil`, nome `I18n.t('kanban.stages.general')` = **"Geral"**).
Esse funil agrega **todas** as conversas da conta (é a visão "tudo"). Queremos que o
**agente não veja mais o Geral** — só os funis dos **seus times** — enquanto o **admin
continua vendo** o Geral normalmente.

### Decisões de produto já travadas (confirmadas com o usuário)

| Tema | Decisão |
|------|---------|
| **Quem vê o Geral** | **Admin sim, agente não.** O agente passa a ver só os funis dos seus times. Isso **também resolve o risco de "cards órfãos"** (ver §Armadilha 1): conversas **sem time** vivem só no Geral e continuam visíveis ao admin. |
| **Mecanismo** | **Regra fixa por papel — SEM toggle, SEM configuração, SEM migration.** Agentes nunca veem o Geral; admins sempre veem. (Um toggle por conta em `Account#settings` foi considerado e **descartado** pelo usuário: preferiu regra fixa.) |
| **Não deletar o Geral** | O funil **permanece no banco**. É recriado automaticamente e é usado pela colocação/relatórios/automações. "Desativar" = **esconder da leitura por agente**, não apagar. |
| **Colocação intacta** | A colocação de conversas no Geral **continua acontecendo** (senão o admin perde os cards sem time). Só a **visibilidade por agente** muda. |

---

## ⚠️ Armadilhas que quebram a feature (ler antes de codar)

Verificadas no código real via mapeamento do sistema.

1. **NÃO deletar o Geral e NÃO parar a colocação.** Toda conversa é colocada no Geral:
   `Kanban::FunnelLookupService` (`app/services/kanban/funnel_lookup_service.rb:16-21`)
   **sempre anexa** o funil default (`team_id: nil`), e `Conversation` cria um
   `FunnelItem` por funil retornado (`app/models/conversation.rb:172-176` +
   `add_to_appropriate_funnel` ~449-463). Consequência:
   - Conversa **COM time** → 2 itens: funil do time **e** Geral.
   - Conversa **SEM time** → **só** no Geral.
   Se você parasse a colocação/deletasse o Geral, as conversas sem time **sumiriam do
   quadro para todos**. A decisão travada (admin continua vendo o Geral) mantém essas
   conversas visíveis ao admin — por isso **não mexa na colocação**. Além disso,
   `Kanban::EnsureDefaultFunnelsService` (`app/controllers/api/v1/accounts/funnels_controller.rb:9`)
   **recria** o Geral em todo `funnels#index` → deletar é inútil.

2. **A mudança é SÓ na fronteira de leitura da UI/API (o policy scope).** **NÃO** gatear
   relatórios, snapshots ou automações — eles leem o banco **direto** (não pelo
   `funnels#index`) e **precisam** continuar enxergando o Geral:
   `Kanban::DailySnapshotJob` (`Funnel.find_each`), `Reports::PdfDataResolver#funnel_data`,
   `Kanban::FunnelReportService`, `Kanban::AutomationEngineService`,
   `funnels_controller#stats/baseline`. Se você aplicar o filtro do agente nesses lugares,
   quebra relatório/automação.

3. **Fonte única: o `FunnelPolicy::Scope`.** **Todos** os controllers de funil carregam via
   `policy_scope(Funnel)` — confirmado: `funnels_controller` (index :10, funnel :97),
   `funnel_items_controller:99`, `funnel_stages_controller:49`,
   `funnels/automations_controller:41`, `funnels/custom_fields_controller:41`,
   `funnels/funnel_item_notes_controller:32`. Logo, **gatear o Scope cascateia para todos
   automaticamente** — o agente não consegue nem listar, nem abrir itens/stages/stats do
   Geral. Não é preciso mexer em cada controller. **Não reimplemente a regra em vários
   lugares** — só no policy.

4. **Mudança de comportamento p/ agente sem time.** Hoje um agente sem nenhum time vê **só**
   o Geral. Depois desta mudança ele vê **zero funis**. Isso é o comportamento desejado
   (agente não vê "tudo"), mas o **front precisa exibir empty-state gracioso** (não crashar)
   — ver §5.

5. **Front auto-seleciona o funil `[0]`, que hoje é o Geral.** O getter `getFunnels`
   (`store/modules/kanban/getters.js:18`) força o funil default (`team_id == null`) para o
   índice 0, e `KanbanIndex.vue` (`initializeFunnelContext`, ~393) abre em
   `availableFunnels[0]`. Como o **backend já não retorna o Geral para o agente**, `[0]`
   vira o primeiro funil de time — **sem mudança no front** para o caminho feliz. Só cuidar
   do empty-state e do deep-link (agente com `?funnelId=` do Geral: não está na lista →
   fallback p/ `[0]`; backend responde 404 nos itens). **Não precisa filtrar no front** (o
   backend é a fonte única).

6. **Especificações não existem ainda** — `spec/policies/funnel_policy_spec.rb` e
   `spec/controllers/api/v1/accounts/funnels_controller_spec.rb` **não existem** → criar do
   zero (não há "teste vermelho" a corrigir, diferente do caso das respostas prontas).

7. **`funnel_views_controller` NÃO usa `policy_scope(Funnel)`** (é a exceção à Armadilha 3).
   Ele lista/cria `funnel_views` filtrando por `params[:funnel_id]` sem validar se o funil é
   visível ao usuário (`app/controllers/api/v1/accounts/funnel_views_controller.rb:9-12,17-19` →
   `Current.account.funnel_views.visible_to(Current.user)` + `.where(funnel_id: ...)`; a
   `check_authorization` usa `FunnelViewPolicy`, **não** `FunnelPolicy`). Um agente poderia
   **ler/criar uma "view" salva apontando para o Geral**. **Severidade BAIXA** (uma
   funnel_view é só config de filtro/board — os **cards em si continuam protegidos** pelo
   `funnel_items` policy-scoped), mas para fechar de verdade: no `index`/`create` do
   `funnel_views_controller`, **validar** que `params[:funnel_id]`/`funnel_view_params[:funnel_id]`
   pertence a `policy_scope(Funnel)` (senão `RecordNotFound`/`forbidden`). Incluir 1 teste.

8. **Realtime: `FUNNEL_ITEM_MOVED` é transmitido para `account.users` (TODOS, incl. agentes).**
   `app/listeners/action_cable_listener.rb:138-145` faz `tokens = account.users.pluck(:pubsub_token)`
   e transmite o move de **qualquer** funil — inclusive o Geral — para o browser de **todo**
   agente. **Severidade BAIXA** (o payload é `funnel_item.push_event_data`; os cards são
   buscados via índice policy-scoped, então o agente não deveria renderizar um card do Geral).
   **Verificar no front** que o handler de `FUNNEL_ITEM_MOVED` **ignora eventos de funis fora
   da lista/do funil ativo** (provavelmente já filtra por `funnel_id`), para que um move do
   Geral **não injete** um card no board do agente. Se não filtrar, adicionar o guard no front
   (comparar `funnel_id` do evento com os funis visíveis / `activeFunnelId`). Opcional/robustez:
   restringir os destinatários do broadcast, mas o guard no front é suficiente e mais simples.

9. **Agente pode criar funil `team_id: nil` (que depois não consegue ver).** `create?`/`update?`
   liberam agente e `funnel_params` permite `:team_id` (`funnels_controller.rb:100-102`). Após a
   mudança, um agente que criar um funil sem time cria um funil **invisível para ele** (só admin
   vê `team_id: nil`). Não é falha de segurança, mas é confuso. **Opcional (recomendado):**
   **impedir não-admin de criar/editar funil com `team_id` nulo** — fazer o guard **no
   controller** checando `funnel_params[:team_id]` (no create, a policy autoriza um `Funnel.new`
   em branco, **sem** os params — ver §3.1(c)). Incluir 1 teste se implementar.

---

## 2. Como funciona hoje (mapa do código)

### Backend
- **Funil "Geral"** = `Funnel` com `team_id: nil`, `name: I18n.t('kanban.stages.general')`
  (`config/locales/pt_BR.yml` → `kanban.stages.general: 'Geral'`), `position: 0`.
  Criado por `Kanban::CreateDefaultFunnelService` (`app/services/kanban/create_default_funnel_service.rb`),
  garantido por `Kanban::EnsureDefaultFunnelsService` (chamado em `funnels#index`).
- **Policy** `app/policies/funnel_policy.rb` — **o único ponto a mudar**:
  - `Scope#resolve` (62-98): monta `team_id IN (times do usuário)` **OR** `team_id IS NULL`.
    A linha **76** adiciona o `team_id IS NULL` (Geral) **para agente E admin**:
    ```ruby
    conditions << arel_table[:team_id].eq(nil) if @account_user.agent? || @account_user.administrator?
    ```
  - `show?` (8-19): para `team_id` nulo (Geral), retorna `agent? || administrator?` (linhas 16-18).
  - `index?`/`create?` liberam agente (mantêm — o agente ainda lista os funis do time e pode
    criar funis próprios; **não mexer**).
- **Controllers** — todos via `policy_scope(Funnel)` (ver Armadilha 3). Nenhum outro ponto a tocar.
- **Colocação** — `Conversation` callbacks → `FunnelLookupService` → `FunnelItem` por funil
  (não mexer).
- **Relatórios/automações** — leem o banco direto (não mexer).

### Frontend
- **Store** `store/modules/kanban/`: `actions.js:174 fetchFunnels` → `mutations.js:267 SET_FUNNELS`
  (camelCase por id) → `getters.js:18 getFunnels` (`Object.values`, ordena Geral em `[0]` por
  `teamId == null`). Geral identificável por `team_id == null` / `teamId == null`.
- **Página** `routes/dashboard/kanban/pages/KanbanIndex.vue`: `funnelOptions` (~203/209),
  `initializeFunnelContext` (~393, abre em `[0]`), empty-state (~1012/1037), route watcher (~612).
  **Consome o índice do backend** → com o Geral já filtrado, o front se ajusta sozinho.
- **Papel** `composables/useAdmin.js` (`getCurrentRole === 'administrator'`).

---

## 3. A solução

### 3.1 Backend — `app/policies/funnel_policy.rb` (o essencial)

**(a) `Scope#resolve`, linha 76** — Geral só entra no escopo para **admin**:
```ruby
# antes:
conditions << arel_table[:team_id].eq(nil) if @account_user.agent? || @account_user.administrator?
# depois:
conditions << arel_table[:team_id].eq(nil) if @account_user.administrator?
```

**(b) `show?`, linhas 16-18** — acesso direto ao Geral (show/stats/form/etc.) só para **admin**:
```ruby
    if record.team_id.present?
      return false if @account_user.user.blank?

      user_team_ids.include?(record.team_id)
    else
      @account_user.administrator?   # funil "Geral" (default) → só admin
    end
```

> Só isso para o núcleo. Como `funnel_items`, `funnel_stages`, `stats`, `automations`,
> `custom_fields` e `notes` carregam o funil via `policy_scope(Funnel).find(...)`, o agente
> recebe **RecordNotFound (404)** ao tentar qualquer operação no Geral — sem precisar tocar
> nesses controllers. `index?`/`create?` continuam liberando o agente (ele ainda vê os funis
> do time e cria os próprios). **Não** alterar colocação, relatórios, automações ou o
> `EnsureDefaultFunnelsService`.

**(c) Guards opcionais (recomendados p/ fechar as brechas de superfície — Armadilhas 7 e 9):**
- `funnel_views_controller` (index/create): validar `params[:funnel_id]` contra
  `policy_scope(Funnel)` antes de listar/criar a view (senão agente vê/cria view do Geral).
- Impedir **não-admin** de criar/editar funil com `team_id` nulo. **Atenção:** no `create`, o
  `check_authorization` autoriza um `Funnel.new(account:)` **em branco** (os params ainda não
  estão no record — `funnels_controller.rb:104-106`), então **um teste `record.team_id` na
  policy bloquearia TODO create de agente**. Faça o guard **no controller** (mais seguro), ex.:
  ```ruby
  # funnels_controller.rb, no create/update (antes do create!/update!)
  if funnel_params[:team_id].blank? && !Current.account_user.administrator?
    return head :forbidden
  end
  ```
  (ou autorize um funil construído a partir dos params). São **BAIXA severidade** — se o tempo
  apertar, dá para deixar documentado e fazer só o núcleo (a)/(b), mas o ideal é fechar.

### 3.2 Frontend — verificação defensiva (sem UI nova)

Como o backend já filtra, **não há regra de negócio a duplicar no front**. Apenas garantir
robustez (idealmente com um teste ou QA manual):

- **Agente com funis de time:** o Kanban abre no **primeiro funil de time** (não no Geral).
  Deve funcionar automaticamente (o Geral não vem mais no índice).
- **Agente sem nenhum time:** índice retorna **zero funis** → o quadro deve mostrar
  **empty-state gracioso** (checar os guards em `KanbanIndex.vue` ~1012/1037; ajustar só se
  crashar/ficar em branco sem mensagem).
- **Deep-link** (`/kanban/<id-do-Geral>` por um agente): o `id` não está na lista →
  `initializeFunnelContext` cai no fallback `availableFunnels[0]` (ou empty-state se vazio);
  o backend responde 404 nos itens. Garantir que **não gera erro no console** nem tela quebrada.
- **Realtime (Armadilha 8):** localizar o handler de `FUNNEL_ITEM_MOVED` no front (store/module
  do kanban ou onde os eventos ActionCable são tratados) e **confirmar que ele ignora eventos
  cujo `funnel_id` não é o funil ativo / não está na lista de funis do usuário**. Se já filtra
  (provável), nada a fazer — só documentar no PR. Se não, adicionar o guard (comparar
  `event.funnel_id` com `getActiveFunnelId`/`getFunnels`). Objetivo: um move de card no Geral
  **não** pode injetar um card no board de um agente.
- **NÃO** filtrar o Geral no `getFunnels`/`funnelOptions` (fonte única é o policy). O sort
  que joga o default para `[0]` é inofensivo (o Geral nem chega ao agente).

---

## 4. Testes

### Policy `spec/policies/funnel_policy_spec.rb` (CRIAR)
- **Scope:**
  - **admin** → vê os funis dos times **+** o Geral (`team_id: nil`).
  - **agente** membro do time X → vê **só** o funil do time X; **não** vê o Geral nem funis
    de times que não participa.
  - **agente sem time** → escopo **vazio** (`scope.none`).
- **show?:**
  - admin → `true` no Geral; agente → **`false`** no Geral.
  - agente membro do time → `true` no funil do time; agente não-membro → `false`.
- **stats?/form?** derivam de `show?` — cobrir de leve (agente no Geral → false).

### Request `spec/controllers/api/v1/accounts/funnels_controller_spec.rb` (CRIAR)
- `GET index` como **admin** → payload inclui o funil `team_id: nil` (Geral).
- `GET index` como **agente** → payload **não** inclui o Geral (só funis dos seus times).
- `GET show`/`GET stats` do Geral como **agente** → **404** (policy_scope não resolve).
- `GET funnel_items` (`funnels/:funnel_id/items`) do Geral como **agente** → **404**.
- Como **admin**, acessar o Geral (show/items) → **200**.
- **Regressão de colocação:** criar uma conversa **sem time** → existe `FunnelItem` no Geral
  → **admin** enxerga esse item no Geral; **agente** não tem como vê-lo (esperado).
- **funnel_views (Armadilha 7):** se implementar o guard — agente `GET`/`POST` funnel_view com
  `funnel_id` do Geral → **404/forbidden**; admin → 200. (Se não implementar, documentar como
  aceito e omitir o teste.)
- **create/update por agente (Armadilha 9):** se implementar o guard — agente cria funil **com
  time** → 200 e **vê** o funil; agente tenta criar/editar funil `team_id: nil` → **forbidden**;
  admin cria `team_id: nil` → 200.

### Factory `spec/factories/funnels.rb` (CONFERIR/ESTENDER)
- Garantir um funil default (`team_id: nil`) e um de time para os specs (traits se preciso).

---

## 5. Ordem de execução sugerida (fases pequenas, verde a cada passo)

- **F1 — Policy:** alterar `Scope#resolve` (linha 76) e `show?` (16-18) + criar
  `spec/policies/funnel_policy_spec.rb`. Rodar `rspec spec/policies/funnel_policy_spec.rb` + `rubocop`.
- **F2 — Request spec:** criar `funnels_controller_spec.rb` cobrindo index/show/stats/items por
  papel + regressão de colocação. Rodar specs de controller.
- **F3 — Front (defensivo):** verificar empty-state (agente sem time) e deep-link ao Geral;
  ajustar guard só se necessário. `eslint`. QA manual.
- **F4 — Validação staging** (nicolas.chatspx.app): `assets:precompile` +
  `sudo /bin/systemctl restart chatwoot.target`. Testar:
  - **admin** → vê o Geral no Kanban;
  - **agente** (em 1+ time) → **não** vê o Geral, abre num funil de time;
  - conversa **sem time** → aparece para o **admin** no Geral;
  - **agente sem time** → empty-state gracioso.
  Nunca testar em produção/frota.

Commit ao fim de **cada** fase. Sem feature flag e sem migration → vai a todos no deploy.

---

## 6. Checklist de "pronto"

- [ ] Agente **não** vê mais o funil Geral (lista + dropdown + auto-seleção).
- [ ] Admin continua vendo o Geral normalmente.
- [ ] Agente não acessa itens/stages/stats do Geral via API (**404**).
- [ ] Conversas **sem time** continuam visíveis ao **admin** no Geral (não órfãs).
- [ ] Colocação, relatórios, snapshots e automações **intactos** (leem o banco direto).
- [ ] Agente **sem time** vê empty-state gracioso (sem crash) — idealmente com mensagem clara
      ("você ainda não participa de nenhum funil/time; peça a um admin").
- [ ] Deep-link ao Geral por agente: fallback sem erro no console.
- [ ] Realtime: move de card no Geral **não** injeta card no board do agente (handler filtra por funil).
- [ ] (Opcional) `funnel_views` não vaza o Geral para agente (guard de `funnel_id`).
- [ ] (Opcional) Agente não cria/edita funil `team_id: nil`; agente cria funil **com time** normalmente.
- [ ] `funnel_policy_spec` + `funnels_controller_spec` verdes; `rubocop`/`eslint` limpos.
- [ ] Validado no staging com **admin** e **agente**.

---

### Referências rápidas de arquivos
```
Backend (MUDAR)
  app/policies/funnel_policy.rb            # Scope#resolve:76 + show?:16-18  ← ÚNICO ponto de código
Backend (guards opcionais — brechas de superfície)
  app/controllers/api/v1/accounts/funnel_views_controller.rb:9-19  # NÃO usa policy_scope(Funnel) (Armadilha 7)
  app/listeners/action_cable_listener.rb:138-145                   # FUNNEL_ITEM_MOVED p/ account.users (Armadilha 8)
  app/controllers/api/v1/accounts/funnels_controller.rb:100-102    # funnel_params permite :team_id (Armadilha 9)
Backend (NÃO mexer — contexto)
  app/services/kanban/funnel_lookup_service.rb        # colocação sempre anexa o Geral
  app/services/kanban/ensure_default_funnels_service.rb / create_default_funnel_service.rb  # recriam o Geral
  app/models/conversation.rb:172-176 (+ add_to_appropriate_funnel ~449-463)  # cria FunnelItem por funil
  app/controllers/api/v1/accounts/funnels_controller.rb (index:10, funnel:97)  # policy_scope
  app/controllers/api/v1/accounts/funnel_items_controller.rb:99                # policy_scope
  app/controllers/api/v1/accounts/funnel_stages_controller.rb:49               # policy_scope
  app/models/funnel_item.rb (push_event_data ~56-70)  # payload do broadcast realtime
  app/jobs/kanban/daily_snapshot_job.rb ; app/services/reports/pdf_data_resolver.rb  # leem DB direto
Frontend (verificar)
  app/javascript/dashboard/store/modules/kanban/{actions.js:174,mutations.js:267,getters.js:18}
  app/javascript/dashboard/routes/dashboard/kanban/pages/KanbanIndex.vue  # ~203/393/1012/1037/612
  app/javascript/dashboard/composables/useAdmin.js
Specs (CRIAR)
  spec/policies/funnel_policy_spec.rb
  spec/controllers/api/v1/accounts/funnels_controller_spec.rb
  spec/factories/funnels.rb   # conferir/estender
i18n
  config/locales/pt_BR.yml / en.yml → kanban.stages.general ('Geral')
```
