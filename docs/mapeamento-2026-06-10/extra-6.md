# Extra 6 — Labels como eixo de triagem por nicho

> Mapeamento de arquitetura — repo chatspx (fork Chatwoot, branch `paulao`).
> Pergunta: o ciclo **etiquetar → CONVERSATION_UPDATED → automation rule (condição/ação de label)** funciona para rotear lead classificado (Clara etiqueta `nicho:locacao` → automação atribui time/corretor → SLA aplicado)? A tool de etiquetar da Clara escreve label de conversa ou contato e valida contra labels existentes? Labels aparecem nos webhooks e no kanban? Há risco de loop automação-re-dispara-automação via label, e `Current.executed_by` marca a origem?

**Veredito curto: o ciclo FUNCIONA fim-a-fim no backend** (etiqueta → evento → condição de label → atribuir time/corretor → aplicar SLA), com anti-loop por `Current.executed_by`. A tool da Clara etiqueta a **conversa** e **valida** contra os Labels do account. Labels **aparecem nos webhooks** (payload + changed_attributes). No **kanban**, labels **não são exibidas no card** e o **filtro por label está quebrado** (compara id numérico contra títulos string). Não há loop infinito, mas há dois efeitos colaterais relevantes: (a) encadeamento regra→regra é suprimido globalmente; (b) regras com condição de label **re-executam** em qualquer `conversation_updated` futuro enquanto a label existir.

---

## 1. A mecânica de labels no modelo

### 1.1 Dois conceitos distintos: `Label` (catálogo) vs tags (acts-as-taggable-on)

- `Label` (`app/models/label.rb:19-56`) é o **catálogo do account**: `title` (forçado lowercase, `before_validation` em label.rb:33-35), `color`, `show_on_sidebar`, único por account (label.rb:25-28). `Label#conversations` resolve via `account.conversations.tagged_with(title)` (label.rb:37-39). Rename de Label propaga via `Labels::UpdateJob` (label.rb:51-55).
- A etiqueta **aplicada** numa conversa/contato é uma *tag* do gem `acts-as-taggable-on` **12.0.0** (`Gemfile.lock:108`), via concern `Labelable` (`app/models/concerns/labelable.rb:1-19`):
  - `acts_as_taggable_on :labels` (labelable.rb:5)
  - `update_labels(labels)` — **substitui** a lista inteira: `update!(label_list: labels)` (labelable.rb:8-10)
  - `add_labels(new_labels)` — **aditivo**: `update!(label_list: labels + new_labels)` (labelable.rb:12-18)
- Incluído em **Conversation** (`app/models/conversation.rb:55`) e **Contact** (`app/models/contact.rb:47`) — labels de conversa e de contato são eixos separados.
- ⚠️ Consequência: dá pra criar uma **tag que não existe como `Label` do account** (o taggable cria o `Tag` row sozinho). Essa tag fica em `label_list`/webhooks mas é **invisível** nos dropdowns de filtro, sidebar e relatórios (que listam a partir de `Label`).

### 1.2 Dirty tracking e o evento

- `cached_label_list` é coluna física de conversations (conversation.rb:9) com helper `cached_label_list_array` (conversation.rb:224-226).
- Mudança de label entra em `previous_changes['label_list']` (dirty tracking do acts-as-taggable-on), o que alimenta:
  - `after_update_commit :execute_after_update_commit_callbacks` (conversation.rb:156) → `notify_conversation_updation` (conversation.rb:275-281, 349-357);
  - `list_of_keys` inclui `label_list` (**conversation.rb:360-361**) → `allowed_keys?` (conversation.rb:364-369) → **dispatch de `CONVERSATION_UPDATED`** com `changed_attributes: previous_changes` e `performed_by: Current.executed_by` (conversation.rb:392-396);
  - Activity message: `handle_label_change` checa `saved_change_to_label_list?` (`app/models/concerns/activity_message_handler.rb:37-41`) → `create_label_change` diffa added/removed (conversation.rb:404-412) → `create_label_change_activity` (`app/models/concerns/label_activity_message_handler.rb:14-19`).

### 1.3 Dispatcher

- `Dispatcher#dispatch` publica **sync e async** (`app/dispatchers/dispatcher.rb:15-18`).
- Sync: só `ActionCableListener` e `AgentBotListener` (`app/dispatchers/sync_dispatcher.rb:7-9`) — labels chegam ao frontend em tempo real via push_event_data.
- Async: `EventDispatcherJob` (fila `critical`, `app/jobs/event_dispatcher_job.rb`) → publica para `AutomationRuleListener`, `Spx::Tozi::FunnelAutomationListener`, `WebhookListener`, etc. (`app/dispatchers/async_dispatcher.rb:11-25`). `performed_by` (model AR) sobrevive à serialização via GlobalID.

---

## 2. Automation rules com label: condição, ação, SLA

### 2.1 Listener

`AutomationRuleListener` (`app/listeners/automation_rule_listener.rb`):
- Trata `conversation_updated/created/opened/resolved` (linhas 2-16) e `message_created` (18-35).
- `process_conversation_event` (39-57): **early-return se `performed_by` é `AutomationRule`** (linha 40 + `performed_by_automation?` 73-75) — anti-loop; busca regras ativas por evento com **cache de 2 min** (65-71); pra cada regra, `ConditionsFilterService` decide e `ActionService` executa.
- `message_created` ignora msgs de automação por 2 vias: `performed_by` e `content_attributes['automation_rule_id']` (82-86).

### 2.2 Condição de label

- Whitelist de condições inclui `labels` (`app/models/automation_rule.rb:38-40`); whitelist de ações (42-46): `add_label`, `remove_label`, `assign_team`, `assign_agent`, `change_status`, `send_message`, `send_webhook_event`, `change_priority`, `add_private_note`, etc.
- Overlay Enterprise adiciona condição `sla_policy_id` e **ação `add_sla`** (`enterprise/app/models/enterprise/automation_rule.rb:1-9`).
- `AutomationRules::ConditionsFilterService` (`app/services/automation_rules/conditions_filter_service.rb`):
  - `base_relation` (185-203) monta query da PRÓPRIA conversa com `LEFT OUTER JOIN taggings/tags` quando há condição de label (192-199).
  - `build_label_query_string` (160-181): `equal_to` → `tags.name = :value`; `not_equal_to`; `is_present` → `tags.id IS NOT NULL`; `is_not_present`.
  - ⚠️ **`equal_to`/`not_equal_to` usam só `values.first`** (linhas 166 e 172) — múltiplos valores numa condição são silenciosamente ignorados além do primeiro. Pra "nicho:locacao OU nicho:venda" são necessárias 2 condições com `query_operator: OR`.
  - ⚠️ A condição testa o **estado atual do banco** (join de tags), não o delta do evento. O filtro `attribute_changed` NÃO funciona para labels: a chave permitida é `labels` mas `changed_attributes` traz `label_list` → `@changed_attributes['labels']` é nil → `NoMethodError` em `filter_based_on_attribute_change` (89-99) → rescue do `perform` (39-43) → regra avaliada como false.
- **Spec do fork que prova o ciclo completo**: `spec/listeners/automation_rule_listener_labels_spec.rb` — label adicionada dispara regra `conversation_updated` com condição `labels equal_to` (linhas 44-64), `is_present` (106-122), `remove_label` action (187-202) e **anti-loop** com `performed_by: automation_rule` (227-242).

### 2.3 Ações de roteamento e SLA

`ActionService` base (`app/services/action_service.rb`):
- `add_label` → `@conversation.reload.add_labels(labels)` (37-41) — **sem validação** contra `Label` do account (a UI restringe, mas a API não);
- `remove_label` → `update(label_list: label_list - labels)` (55-60);
- `assign_agent` valida membro do inbox + confirmado (43-53, 95-100);
- `assign_team` valida time do account (62-73);
- `send_webhook_event` → `WebhookJob` com `conversation.webhook_data` + `event: automation_event.<event_name>` (38-41 do `automation_rules/action_service.rb`) — **hook de saída para orquestrador externo**;
- Enterprise injeta `add_sla` via `ActionService.include_mod_with('ActionService')` (action_service.rb:113): seta `sla_policy_id` se a conversa ainda não tem SLA (`enterprise/app/services/enterprise/action_service.rb:2-11`).
- **Avaliação do SLA** roda por cron: `config/schedule.yml:15` (`TriggerScheduledItemsJob`) → `Enterprise::TriggerScheduledItemsJob` (`enterprise/app/jobs/enterprise/trigger_scheduled_items_job.rb`) → `Sla::TriggerSlasForAccountsJob` → `Sla::ProcessAccountAppliedSlasJob`/`ProcessAppliedSlaJob` + `Sla::EvaluateAppliedSlaService` (`enterprise/app/jobs/sla/*.rb`, `enterprise/app/services/sla/evaluate_applied_sla_service.rb`). Mudança de SLA gera activity (`activity_message_handler.rb:43-48`).

### 2.4 O fluxo-alvo (Clara etiqueta → automação roteia) — confirmado

1. Clara (Captain v2) roda dentro de `Captain::Conversation::ResponseBuilderJob`, que seta `Current.executed_by = @assistant` (`enterprise/app/jobs/captain/conversation/response_builder_job.rb:16`, reset no ensure linha 29).
2. Tool etiqueta a conversa → `update!` → `CONVERSATION_UPDATED` com `performed_by = Captain::Assistant` (conversation.rb:392-396).
3. `AutomationRuleListener` **processa** (o skip é só `instance_of?(AutomationRule)`, automation_rule_listener.rb:74) → regra `conversation_updated` com condição `labels equal_to nicho:locacao` casa → `assign_team`/`assign_agent`/`add_sla` executam.
4. `assign_team` dispara `CONVERSATION_UPDATED` (team_id em `list_of_keys`) e `move_to_team_funnel` (conversation.rb:158, 450-455 → `Kanban::MoveConversationToTeamFunnelService`) — o card muda de funil/coluna por time. `assignee` dispara `ASSIGNEE_CHANGED` (`app/models/concerns/assignment_handler.rb:57`) → notificações de atribuição.
5. ⚠️ Interplay Tozi: `Spx::Tozi::FunnelAutomationListener#assignee_changed` (`app/listeners/spx/tozi/funnel_automation_listener.rb:42-52`) move o card pra **"qualificado"** quando um humano é atribuído (e estava em estágio de pré-venda). Triagem automática que atribui corretor diretamente pula o lead pra "Qualificado" no funil de pré-venda — talvez não seja o desejado pra triagem por nicho (atribuir só o **time** não tem esse efeito; atribuir **corretor** tem).

---

## 3. A tool de etiquetar da Clara

### 3.1 Tool de agente (a que a Clara usa em conversa)

`Captain::Tools::AddLabelToConversationTool` (`enterprise/lib/captain/tools/add_label_to_conversation_tool.rb:1-34`):
- Escreve label de **CONVERSA** (não contato): `find_conversation(tool_context.state)` (linha 6; `base_public_tool.rb:26-31` resolve por `state[:conversation][:id]` com escopo do account).
- Normaliza `strip + downcase` (linha 9) — coerente com `Label#before_validation` lowercase.
- **Valida contra labels existentes**: `find_label` → `account_scoped(Label).find_by(title: label_name)` (24-26); se não existe → retorna `'Label not found'` pro LLM (linha 13) e **não cria** tag órfã.
- Aplica via `add_labels` (aditivo, 28-33), com rescue + re-raise logado.
- Registrada em `config/agents/tools.yml:23-26` (`add_label_to_conversation`); resolução `id.classify` → classe (`enterprise/app/models/concerns/captain_tools_helpers.rb:24-27`); habilitada por **Scenario** (coluna `tools` + referências `tool://` na instruction — `enterprise/app/models/captain/scenario.rb:100-127`; `Captain::Assistant#agent_tools` default só traz faq_lookup/handoff/search_knowledge — `enterprise/app/models/captain/assistant.rb:118-129`).
- **Não existe tool de label de contato** (Contact é Labelable mas nenhuma tool escreve nele).

### 3.2 Variante Copilot (painel do atendente) — sem validação

`Captain::Tools::Copilot::AddLabelService` (`enterprise/app/services/captain/tools/copilot/add_label_service.rb:10-18`): `conversation.label_list.add(label); conversation.save!` — **não valida** contra `Label` do account, **não normaliza** caixa → pode criar tag órfã (existe no `label_list`/webhook, invisível nos filtros da UI). Há também `get_labels_service.rb` e `remove_label_service.rb` na mesma pasta.

### 3.3 Outras escritas de label por código SPX

- `Captain::Tools::SalvarInfoLeadTool#mark_followup` adiciona `'followup-ativo'` direto (`enterprise/lib/captain/tools/salvar_info_lead_tool.rb:45-49`) — **sem validar**; se o Label `followup-ativo` não existir no account, vira tag órfã.
- O **router da Clara usa label como kill-switch**: `Captain::Behavior::RouterService#skip_labels?` (`enterprise/app/services/captain/behavior/router_service.rb:13, 65-70`) — se `behavior.router.skip_labels` intersecta `conversation.label_list`, a IA silencia. Ou seja: label já é, hoje, o mecanismo "humano assumiu / não-IA" por conversa.

---

## 4. Labels em webhooks e kanban

### 4.1 Webhooks — SIM, aparecem

- Payload de conversa (`conversation.webhook_data` → `Conversations::EventDataPresenter#push_data`) inclui **`labels: label_list`** (`app/presenters/conversations/event_data_presenter.rb:11`; ponte em `app/models/concerns/push_data_helper.rb:12-14`).
- `WebhookListener#conversation_updated` (`app/listeners/webhook_listener.rb:10-16`) entrega payload + `changed_attributes` formatado `{ label_list: { previous_value: [...], current_value: [...] } }` (`app/listeners/base_listener.rb:32-43`), para webhooks de account inscritos no evento (131-137) **e** pro webhook da inbox `Channel::Api`/WAHA (140-146).
- ⚠️ O webhook **não carrega `performed_by`** — um consumidor externo não distingue se a label veio de humano, automação ou IA (internamente o evento tem; o `WebhookListener` não serializa).
- A atualização ao vivo no painel acontece pelo `ActionCableListener` (sync dispatcher) com o mesmo `push_data` (labels incluídas).

### 4.2 Kanban — labels NÃO aparecem no card e o filtro está quebrado

- O payload do funnel item **não traz labels** (`app/views/api/v1/models/_funnel_item.json.jbuilder:1-37` — só conversation básica + contato + last_message).
- `KanbanCard.vue` não tem **nenhuma** referência a label (grep vazio) — o card não renderiza chips de label.
- Existe **filtro por label** no toolbar (`KanbanIndex.vue:74-79, 158-166, 201-210` — opções vêm de `labels/getLabels` com `value = String(label.id)`), aplicado em `KanbanBoard.vue#matchesLabelFilter` (185-191) e `ListView.vue#matchesLabelFilter` (312-320): `labelSet.has(Number(label.id))`.
- 🐛 **Bug de tipo**: a fonte (`conversationLabels/getConversationLabels`, `app/javascript/dashboard/store/modules/conversationLabels.js:17-19`) guarda **arrays de STRINGS (títulos)** — populado por `GET /conversations/:id/labels` (`LabelConcern#index` → `model.label_list`, `app/controllers/concerns/label_concern.rb`; `json.payload @labels` em `app/views/api/v1/accounts/conversations/labels/index.json.jbuilder`) e pela lista de conversas (`json.labels conversation.cached_label_list_array`, `app/views/api/v1/conversations/partials/_conversation.json.jbuilder:105` → `setBulkConversationLabels`, `store/modules/conversations/helpers/actionHelpers.js:83-86`). `Number("nicho:locacao".id)` = `Number(undefined)` = NaN → **filtro ativo esconde todos os cards**.
- 🐛 **Bug de carga**: o kanban nunca despacha `conversationLabels/get` pros seus items (só `ConversationBox.vue:97` ao abrir a conversa, ou a lista de conversas) → cards de conversas nunca abertas têm `[]` no store de qualquer forma.
- Em contraste, a **lista de conversas** mostra labels corretamente: `CardLabels.vue` casa **títulos** (`components/widgets/conversation/conversationCardComponents/CardLabels.vue:17` e `components-next/Conversation/ConversationCard/CardLabels.vue:29`).
- O funil Tozi não usa labels nas transições — é `message_created`/`assignee_changed` (`app/listeners/spx/tozi/funnel_automation_listener.rb:24-52`).

---

## 5. Loop e `Current.executed_by`

### 5.1 Como a origem é marcada

- `Current.executed_by` é thread-local (`lib/current.rb:5`, reset em :8-14). Setado por:
  - **Automação**: `AutomationRules::ActionService#initialize` → `Current.executed_by = rule` (`app/services/automation_rules/action_service.rb:6`), `Current.reset` no ensure (19-20);
  - **Captain/Clara**: `ResponseBuilderJob` → `= @assistant` (`enterprise/app/jobs/captain/conversation/response_builder_job.rb:16`, reset :29); `Captain::InboxPendingConversationsResolutionJob` (:26,:35); `Enterprise::MessageTemplates::HookExecutionService` (:62-63);
  - **Auto-assignment**: `= inbox.assignment_policy || inbox` (`app/services/auto_assignment/assignment_service.rb:75-85`).
- Todo dispatch de conversa/mensagem carrega `performed_by: Current.executed_by` (conversation.rb:392-396; message.rb:402, 405, 432).
- Os activity messages usam isso pra autoria: `activity_message_owner` (`app/models/concerns/assignee_activity_message_handler.rb:22-34`) — AutomationRule → "sistema de automação"; Captain::Assistant tem tratamento dedicado **só pra status** (`enterprise/app/models/enterprise/activity_message_handler.rb:2-10` — "resolvida pela Clara…"); ⚠️ pra **label**, Captain::Assistant cai no `else` genérico → a atividade de etiquetagem da Clara sai com o nome genérico de automação, não "Clara".

### 5.2 Anti-loop — funciona, com efeitos colaterais

- **Sem loop infinito**: evento `conversation_*` com `performed_by` `AutomationRule` é descartado pelo listener (`automation_rule_listener.rb:40, 73-75`); `message_created` de automação idem (82-86, msgs estampadas com `content_attributes.automation_rule_id` em `automation_rules/action_service.rb:46, 53`). Spec: `automation_rule_listener_labels_spec.rb:206-243`.
- **Efeito colateral 1 — encadeamento suprimido**: o skip é por *classe*, não por regra. Se a regra A adiciona `label X`, a regra B (condição em `label X`) **não roda nesse evento** — só num próximo `conversation_updated` de outra origem. Cascatas regra→regra via label não são confiáveis.
- **Efeito colateral 2 — re-execução**: como a condição de label testa o **estado atual** (join tags), qualquer `conversation_updated` futuro (mudança de `waiting_since`, `priority`, `custom_attributes`, `team_id`… — `list_of_keys`, conversation.rb:360-361) com a label ainda presente **re-dispara a regra**. Ações idempotentes (assign_team pro mesmo time → `update!` sem mudança → sem evento novo) são inócuas; **`send_message`/`send_webhook_event`/`add_private_note` repetem**. Mitigação de desenho: condição composta (ex.: `labels equal_to nicho:locacao` **AND** `team_id is_not_present`), ou a própria regra remover/trocar a label-gatilho por uma label "-processado".
- **Clara → automação NÃO é suprimido** (desejável pra triagem): `performed_by = Captain::Assistant` ≠ AutomationRule → regras rodam. Idem auto-assignment (AssignmentPolicy/Inbox).
- `Enterprise::Message#mark_pending_conversation_as_open_for_human_response` zera `Current.executed_by` temporariamente ao reabrir pending (`enterprise/app/models/enterprise/message.rb:10-23`) — hoje neutralizado pelo stub `captain_pending_conversation?` (contexto do incidente de 02/06).

---

## 6. Hooks pra IA orquestradora (labels como barramento de triagem)

1. **Tool pronta**: `add_label_to_conversation` (tools.yml:23) habilitável por Scenario — Clara classifica nicho e etiqueta com validação.
2. **Barramento nativo**: `CONVERSATION_UPDATED` + automation rules (`labels` condition → `assign_team`/`assign_agent`/`add_sla`/`change_priority`) = triagem declarativa sem código novo; `performed_by` garante que a etiquetagem da IA dispara as regras e que as regras não se re-disparam.
3. **Kill-switch por label**: `router.skip_labels` (router_service.rb:65-70) — uma label `atendimento-humano` silencia a Clara naquela conversa; combinável com a própria automação (regra tira/põe a label).
4. **Callback externo**: ação `send_webhook_event` (automation_rules/action_service.rb:38-41) manda `webhook_data` (com labels) pra URL arbitrária — ponte para orquestrador fora do SPX.
5. **Webhooks de account/inbox** com `labels` + `changed_attributes.label_list` (event_data_presenter.rb:11; webhook_listener.rb:10-16) — observabilidade externa de classificação.
6. **Handoff por nicho**: `HandoffTool` tem TODO explícito de team routing ("roleta por nicho Vista/Loft virá depois", `enterprise/lib/captain/tools/handoff_tool.rb:41-44, 74-80`) — alternativa: handoff genérico + label de nicho + automação `assign_team` cobre o mesmo caso sem tocar na tool.
7. **Copilot**: `add_label`/`remove_label`/`get_labels` (`enterprise/app/services/captain/tools/copilot/`) pra operação assistida do atendente.
8. **SLA**: `add_sla` enterprise via automação + cron de avaliação (`schedule.yml:15` → `Sla::*`) fecha o "SLA aplicado" da pergunta.

## 7. Gaps e riscos

- **Kanban**: filtro de label compara `Number(label.id)` com store de **títulos string** (KanbanBoard.vue:190; ListView.vue:318 vs conversationLabels.js:17-19 + _conversation.json.jbuilder:105) → filtro ativo esconde tudo; labels nem são buscadas pros cards; card não renderiza labels. Pra labels serem eixo visível de triagem no kanban, precisa: incluir labels no payload do funnel_item (ou bulk-set no store) + corrigir o match por título + renderizar chips no `KanbanCard.vue`.
- **`equal_to` de label usa só `values.first`** (conditions_filter_service.rb:166,172) — multi-valor silenciosamente ignorado.
- **`attribute_changed` não funciona pra labels** (mismatch `labels` vs `label_list` + NoMethodError rescued → false) — não dá pra reagir só ao *delta* de label; regra reage ao estado.
- **Re-execução de regras de label** em updates subsequentes (ações não-idempotentes duplicam mensagens/webhooks).
- **Encadeamento regra→regra suprimido** pelo anti-loop global (performed_by é qualquer AutomationRule).
- **Tags órfãs**: Copilot `AddLabelService` e `SalvarInfoLeadTool` (`followup-ativo`) criam tags sem validar contra `Label` do account → invisíveis em filtros/sidebar/relatórios. A taxonomia `nicho:*` precisa ser criada como `Label` do account ANTES (a tool da Clara recusa label inexistente — bom guard, mas exige provisionamento).
- **Webhook sem origem**: payload não carrega `performed_by` — orquestrador externo não sabe quem etiquetou.
- **Activity da Clara em label** sai com nome genérico de automação (assignee_activity_message_handler.rb:29-30), não "Clara" — auditoria visual fica imprecisa.
- **Interplay funil Tozi**: automação que atribui **corretor** dispara `assignee_changed` → card vai pra "Qualificado" (funnel_automation_listener.rb:42-52). Triagem por label deveria preferir `assign_team` (sem esse efeito) se o lead ainda não é qualificado.
- **Cache de 2 min** das regras ativas (automation_rule_listener.rb:65-71): regra recém-criada/desativada demora até 2 min pra valer.
- **Labels minúsculas**: `Label` força lowercase; quem comparar/criar com maiúscula (copilot, scripts) gera divergência de caixa entre tag e catálogo.

## 8. Questões em aberto

- A `AutomationRule #53 'iniciar zerado'` (prod, `conversation_opened`, zera assignee/team) não está no código — como vai conviver com regras de triagem por label? Se a Clara etiquetar e a automação atribuir, um reopen posterior re-zera a atribuição (a regra #53 roda no `conversation_opened`, que NÃO é suprimido quando o reopen vem de contato/humano).
- A taxonomia `nicho:*` será label de **conversa** (efêmera por atendimento) ou de **contato** (perfil duradouro)? Hoje só existe tool pra conversa; contato exigiria tool nova (Contact já é Labelable).
- Account 6 (prod) tem feature/plano com SLA habilitado pro `add_sla` enterprise valer?
- Vale corrigir o filtro de label do kanban (id→título) junto do mapeamento, ou labels no kanban ficam fora do escopo do orquestrador (funil já tem eixo próprio por stage)?
