# Mapeamento — Runtime do Captain v2 (módulo Agentes IA)

> Área: captain-runtime · Branch: paulao · Data: 2026-06-10
> Tudo abaixo foi lido do código local (app/ + enterprise/), com referências arquivo:linha.

---

## 1. Visão geral

O Captain v2 é o runtime de agente IA do fork. O acoplamento à inbox é o join model `CaptainInbox` (`enterprise/app/models/captain_inbox.rb:17-22`, `inbox_id` único — **uma assistant por inbox**). A inbox ganha `captain_inbox`/`captain_assistant` via `Enterprise::Concerns::Inbox` (`enterprise/app/models/enterprise/concerns/inbox.rb:4-10`).

O pipeline é: **incoming → callbacks do Message → HookExecutionService (enterprise) → Router/BusinessHours/Debounce → ResponseBuilderJob → AgentRunnerService (gem `agents`) → process_response (handoff | IGNORAR | dedup | humanizer | envio)**.

### Gates de ativação

| Gate | Onde | Lógica |
|---|---|---|
| `captain_active?` | `enterprise/app/models/enterprise/inbox.rb:14-16` | `captain_assistant.present? && more_responses?` (cota `account.usage_limits[:captain][:responses][:current_available] > 0`, linhas 20-22) |
| `active_bot?` (OSS) | `app/models/inbox.rb:172-175` | `agent_bot_inbox&.active?` OU hook dialogflow ativo |
| `active_bot?` (Enterprise) | `enterprise/app/models/enterprise/inbox.rb:10-12` | `super \|\| captain_active?` — **conectar a Clara torna a inbox "bot inbox"**, com todos os efeitos colaterais (pending em conversa nova, pending no reopen) |
| `should_process_captain_response?` | `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:129-135` | `(pending? \|\| open?) && message.incoming? && inbox.captain_assistant.present? && !human_takeover_locked?` |
| `pending_status_enabled` (fork) | coluna boolean na inbox, default FALSE (`app/models/inbox.rb:22` schema). Validação `pending_status_allowed_by_inbox` (`app/models/conversation.rb:77` + `324-330`) **bloqueia QUALQUER transição para pending** se a inbox não habilitar. Conversa nova só nasce pending se `active_bot? && pending_status_enabled?` (`app/models/conversation.rb:332-338`; campanha: 340-343) |

---

## 2. Fluxo completo de um incoming (inbox com Captain conectado)

### Passo 0 — Persistência da mensagem
`Message#execute_after_create_commit_callbacks` (`app/models/message.rb:341-350`) roda em ordem:
1. `reopen_conversation` (443-452): se incoming e conversa `snoozed` → `open!`; se `resolved` → `reopen_resolved_conversation` (466-476): **inbox com `active_bot?` → `conversation.pending!`** (o famoso limbo), senão `open!`. ⚠️ Se `pending_status_enabled=false` na inbox, esse `pending!` levanta `RecordInvalid` dentro do after_commit.
2. `mark_pending_conversation_as_open_for_human_response` (454-460): no OSS o gate `captain_pending_conversation?` é stub `false` (462-464), **mas o overlay Enterprise sobrescreve**: `Enterprise::Message` (`enterprise/app/models/enterprise/message.rb:4-35`, prepend em `app/models/message.rb:515`) retorna `true` se conversa pending + `CaptainInbox.exists?(inbox_id:)` (26-30). Resposta **humana** (pública, não-bootstrap-de-template, 4-8) → `conversation.open!` + activity message "auto opened after agent reply" (37-45). Ou seja: com o overlay carregado, resposta humana TIRA a conversa do pending (o STATE.md de 02/06 registrava só o stub OSS).
3. `dispatch_create_events` (401-412): `MESSAGE_CREATED` no Wisper (alimenta automações, FunnelAutomationListener, etc.).
4. `send_reply` → SendReplyJob (canal).
5. `execute_message_template_hooks` (482-484) → `MessageTemplates::HookExecutionService` (OSS `app/services/message_templates/hook_execution_service.rb:1-62`, com prepend Enterprise na linha 62).

### Passo 1 — HookExecutionService (enterprise)
`Enterprise::MessageTemplates::HookExecutionService#trigger_templates` (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:4-10`):
- `super` (greeting/OOO/email-collect OSS — suprimidos quando `captain_handling_conversation?`, linhas 12-28 e 164-166).
- `return unless should_process_captain_response?` (129-135).
- `return perform_handoff unless inbox.captain_active?` (7) — **cota zerada** → handoff com mensagem hardcoded em INGLÊS "Transferring to another agent for further assistance." (142-154, só se pending).
- `process_captain_behavior(assistant)` (32-44):
  1. Mensagem **privada** → `trigger_copilot_if_applicable` (100-107): `Captain::Behavior::CopilotTriggerService` (`enterprise/app/services/captain/behavior/copilot_trigger_service.rb:9-24`) — nota privada contendo o hashtag `behavior.copilot_trigger.hashtag` (default `#copilot`) dispara `Captain::Copilot::ChatService`.
  2. `router_allows?` (46-48) → `Captain::Behavior::RouterService#should_respond?`; reprovou → `log_and_skip('router_skip')` (95-98, grava `Captain::AssistantLog`) e **fica como está** (se estava pending, permanece pending — invisível).
  3. **`ensure_conversation_open(assistant)` (59-71) — mudança recente (commit `f96ae7740`):** se a conversa está `pending` e a IA vai atender (passou no router), `conversation.open!` com `Current.executed_by = assistant` (atividade aparece como "Clara"). Best-effort (rescue + warn). Ruído (router_skip) não chega aqui e segue pending.
  4. `outside_hours_ignore?` (50-53): `BusinessHoursChecker.status == :outside` **e** `behavior.business_hours.outside_hours_action == 'ignore'` → `log_and_skip('business_hours_skip')`. (Nota: a conversa já foi aberta no passo 3 — fica visível, mas sem resposta da IA.)
  5. `schedule_or_debounce` (73-81): `mark_customer_message_read` (86-93, tique azul via `channel.send_typing_indicator(source_id, false)`, só WhatsApp Cloud, best-effort); `behavior.debounce_seconds > 0` → DebounceService, senão `schedule_captain_response` direto (109-118; com anexo espera 1s + 1s/anexo, teto 5s extra, 120-127).

### Passo 2 — Debounce
`Captain::Behavior::DebounceService#schedule` (`enterprise/app/services/captain/behavior/debounce_service.rb:14-27`): grava token UUID no Redis (`CAPTAIN_DEBOUNCE_TOKEN` por conversa+assistant, TTL = debounce + 30s de folga, linhas 8-12) e agenda `Captain::Conversation::DebouncedResponseJob` com `wait: debounce_seconds`. Cada nova mensagem do cliente sobrescreve o token → só o job da última mensagem casa. `DebouncedResponseJob` (`enterprise/app/jobs/captain/conversation/debounced_response_job.rb:4-21`): compara token, deleta a chave, loga `debounce_fire`, e roda `ResponseBuilderJob.perform_now`.

### Passo 3 — ResponseBuilderJob
`Captain::Conversation::ResponseBuilderJob` (`enterprise/app/jobs/captain/conversation/response_builder_job.rb`):
- `captain_can_respond?` (299-303): status **pending OU open** (leitura uncached) — o Captain segue respondendo depois do handoff/atribuição até um humano falar (quem corta é `skip_after_human_response` no router).
- `reset_followup_state` (87-94): resposta normal do cliente zera `followup_token/count/status` (cadência de cutucada recomeça).
- `Current.executed_by = assistant` (16) e roteia: `captain_integration_v2` ligada → `generate_response_with_v2` (43-48, AgentRunnerService); senão v1 `AssistantChatService` (36-41).
- Histórico (`collect_previous_messages`, 64-83): todas as msgs públicas incoming/outgoing; multimodal via `Captain::OpenAiMessageBuilderService` (121); injeção de contexto de reply quotado do WhatsApp (`with_reply_context`, 103-118 — resolve `in_reply_to`/`in_reply_to_external_id` e prefixa `[Respondendo a esta mensagem anterior: "..."]`); `agent_name` preservado; diretiva interna de follow-up entra como último turno user (80-82).
- `process_response` (50-62): re-checa `captain_can_respond?`; `response == 'conversation_handoff'` → `process_action('handoff')`; senão cria mensagens + `account.increment_response_usage` (cota).

### Passo 4 — Envio da resposta
- `no_reply?` (163-167): conteúdo vazio ou `[IGNORAR]`/`[sem resposta]`/`[no reply]` → não envia nada (o agente decide ficar calado).
- `skip_duplicate?` (169-177): `behavior.dedup.enabled` → `DedupService` (`enterprise/app/services/captain/behavior/dedup_service.rb:9-16`, `SET NX` no Redis com MD5 de `conversa:conteúdo`, TTL `dedup.ttl_seconds` default 120) → loga `dedup_skip`.
- `sanitize_for_whatsapp` (191-203): remove markdown (negrito, títulos, bullets), troca travessão por vírgula etc.
- Humanizer (`behavior.humanizer.enabled`): `HumanizerService#split` (`enterprise/app/services/captain/behavior/humanizer_service.rb:7-14`) quebra por parágrafo e por frase até `max_chars` (default 300). Antes de CADA pedaço: rajada de "digitando" (`trigger_typing_indicator`, 222-230, referencia o `source_id` da última incoming) + `sleep` proporcional ao tamanho (`humanizer_typing_delay`, 234-241: 45ms/char, piso 1.5s, teto 7s, configurável). Loga `humanizer_split`.
- `create_outgoing_message` (247-259): `sender: @assistant` (sender_type `Captain::Assistant`), `additional_attributes.agent_name` = cenário que respondeu.
- Erro (`handle_error`, 261-265): captura exceção e **se a conversa está pending → handoff** (mensagem de handoff + `bot_handoff!`).

---

## 3. behavior.router — decide responder ou pular

`Captain::Behavior::RouterService` (`enterprise/app/services/captain/behavior/router_service.rb`). Lê `assistant.behavior['router']` (6). `should_respond?` (9-19) reprova se:

| Checagem | Linha | Comportamento |
|---|---|---|
| mensagem activity | 10 | nunca responde a activity |
| sem conteúdo e sem anexo | 11 | skip |
| `only_contact_phones` (whitelist) | 12, 23-41 | Se a lista tem itens, só responde se o telefone do contato casa. Compara **variações de 9º dígito BR** (`phone_variations`, 47-63: com/sem DDI 55, com/sem o 9) contra `contact.phone_number` E o JID puro do WAHA (`custom_attributes.waha_whatsapp_jid`, 36-41). É o mecanismo de piloto controlado. |
| `skip_labels` | 65-70 | qualquer label da conversa na lista → calado |
| `skip_groups` | 72-95 | `additional_attributes.type == 'group'` OU identifier/JID/chat_id terminando `@g.us` (heurística WAHA) |
| `skip_agent_bot` | 97-99 | conversa com `agent_bot_id` presente (outro bot dono) → calado |
| `skip_after_human_response` | 105-117 | olha as últimas **5** outgoing públicas (ignorando NPS); se a mais recente não-NPS foi enviada por `User` → humano assumiu, Clara cala. Mensagens da própria assistant não contam (ela pode mandar várias seguidas). |

**Importante:** router_skip NÃO mexe no status da conversa. Se ela caiu em pending (reopen com bot), fica pending pra sempre — essa é a raiz do incidente do limbo. O `ensure_conversation_open` só roda pra quem PASSA no router.

## 4. Trava de atendimento humano

Duas camadas:
1. **Hard lock — `atendimento_humano`** (custom attribute da conversa): `human_takeover_locked?` (`hook_execution_service.rb:138-140`, aceita `true/'true'/1/'1'`) corta o Captain ANTES de qualquer processamento; o `FollowupJob` também respeita (`followup_job.rb:17`). É o checkbox do painel lateral.
2. **Soft lock — `skip_after_human_response`** (router): automático quando um humano responde; a Clara volta se o humano parar de responder e o cliente mandar nova mensagem? Não — continua skip enquanto a última outgoing for de User. Volta apenas se a assistant ou um template for a última outgoing.

## 5. Cenários (Scenario) e como o "router de cenário" escolhe

`Captain::Scenario` (`enterprise/app/models/captain/scenario.rb`): pertence à assistant, tem `instruction`, `tools` (jsonb), `enabled`. Cada cenário vira um **agente próprio** (include `Concerns::Agentable`, 25) com `handoff_key` no formato `scenario_{id}_{slug}_agent` (58-60, cap de 60 chars pro limite da OpenAI, 27-38). Tools do cenário são resolvidas a partir de referências `[@Tool](tool://tool_id)` na instruction (`resolve_tool_references`, 171-176; validação 143-155), buscando em `assistant.available_agent_tools` (built-ins de `config/agents/tools.yml` + `Captain::CustomTool` da conta — `assistant.rb:57-64`).

A escolha de cenário **não é código — é o LLM**: `AgentRunnerService#build_and_wire_agents` (`agent_runner_service.rb:167-175`) registra handoffs bidirecionais (assistant ⇄ cenários); o prompt do orquestrador (`enterprise/lib/captain/prompts/assistant.liquid:64-71`) lista os cenários e instrui usar `handoff_to_{key}`. O runner (`Agents::Runner`, gem `agents`) executa com `max_turns: 100` (`agent_runner_service.rb:31`).

## 6. AgentRunnerService e geração

`enterprise/app/services/captain/assistant/agent_runner_service.rb`:
- `generate_response` (29-41): monta payload (`run_payload`, 249-254: última msg user separada + histórico restante no contexto), roda, `process_agent_result` (96-110): se `result.output` vazio (acontece quando o último turno é handoff) usa fallback `last_assistant_message_text` (112-134) pra não perder a fala de despedida pré-handoff; anexa `agent_name` do contexto. Erro → `error_response` = `'conversation_handoff'` (136-141).
- Contexto/estado (143-161): slices de conversation (id, status, custom_attributes…), contact, campaign, contact_inbox — é o `state` que as tools usam (`find_conversation` em `BasePublicTool`, `enterprise/lib/captain/tools/base_public_tool.rb:26-31`).
- Instrumentação OTel/Langfuse (177-237) com flag de crédito (handoff não consome crédito).

### Modelo LLM e chaves
- `Concerns::Agentable#agent` (`enterprise/app/models/concerns/agentable.rb:4-13`): monta `Agents::Agent` com `model: agent_model`.
- `agent_model` (45-48): **`account.captain_assistant_model`** → fallback `LlmConstants::DEFAULT_MODEL` (`lib/llm_constants.rb:4` = `gpt-4.1`), traduzido por `Llm::Models.runtime_id_for` (`lib/llm/models.rb:38-43`, `claude-sonnet-4.5` → `claude-sonnet-4-5`).
- `captain_assistant_model` é gerado dinamicamente por `CaptainFeaturable` (`app/models/concerns/captain_featurable.rb:17-19`): lê `account.settings['captain_models']['assistant']` com validação contra `config/llm.yml` (`captain_models_with_defaults`, 32-42). Ou seja, o **modelo é per-conta, lido a cada request** (dropdown "Assistente" da tela LLM Settings).
- As **chaves são GLOBAIS da instalação**, lidas **no boot**: `config/initializers/ai_agents.rb:5-27` configura o gem `agents` com `InstallationConfig` `CAPTAIN_OPEN_AI_API_KEY` / `CAPTAIN_ANTHROPIC_API_KEY` / `CAPTAIN_OPEN_AI_MODEL` (default global). **Trocar chave exige restart do worker; trocar modelo não.** A chave per-conta da UI (hook `openai`) NÃO alimenta o runner v2 (gotcha conhecido "chave em 2 lugares").
- `time_awareness` (`agentable.rb:52-65`): injeta data/hora (tz `behavior.business_hours.timezone`, default `America/Cuiaba`) + status dentro/fora do horário no prompt — anti-alucinação de horário.

### Assistant model
`enterprise/app/models/captain/assistant.rb`: `config` jsonb (temperature, feature_faq, feature_memory, product_name, handoff_message, resolution_message, knowledge_mode) + `behavior` jsonb (migration `db/migrate/20260406120000_add_behavior_to_captain_assistants.rb`). `knowledge_mode` faq/chunks/hybrid (72-88). Tools fixas do orquestrador: `faq_lookup` + `handoff` (+ `search_knowledge` se chunk-RAG) (`agent_tools`, 118-129). ⚠️ Os `store_accessor :behavior, ... :router_config, :business_hours_config, :humanizer_config...` (42-43) **não batem com as chaves reais** que o runtime lê (`router`, `business_hours`, `humanizer`, `dedup`, `copilot_trigger`, `media_pipeline`) — acessores mortos/enganosos.

## 7. Handoff — o que acontece hoje

Três caminhos distintos (comportamentos DIFERENTES):

1. **HandoffTool (decisão do LLM)** — `enterprise/lib/captain/tools/handoff_tool.rb:5-64`: nota privada com o motivo (26-37) → `conversation.bot_handoff!` → **`assign_to_available_agent`** (52-64): se sem assignee, round-robin via `AutoAssignment::AgentAssignmentService` entre TODOS os `inbox_members` (sem filtro de time/nicho/role — TODO explícito nas linhas 74-84 prevendo `team_id`/priority/escalation). → OOO se aplicável.
2. **Quota zerada** — `perform_handoff` (`hook_execution_service.rb:142-154`): só se pending; mensagem hardcoded EM INGLÊS + `bot_handoff!`. **Não atribui ninguém.**
3. **`response == 'conversation_handoff'`** (erro do runner ou v1) — `ResponseBuilderJob#process_action` (128-137): mensagem de handoff (`assistant.config['handoff_message']` ou i18n `conversations.captain.handoff`, no locale da conta) + `bot_handoff!` + OOO. **Não atribui ninguém.**

`Conversation#bot_handoff!` (`app/models/conversation.rb:199-203`): seta `waiting_since`, **`open!`** e dispara o evento `CONVERSATION_BOT_HANDOFF`. Ou seja: handoff hoje = abre a conversa + (só no caminho da tool) atribui um membro online qualquer da inbox. Não mexe em time, não considera a custom role dos corretores.

Pós-handoff o Captain **continua elegível** (responde em open) até um User responder (skip_after_human_response) — desenho intencional pra não deixar cliente sem resposta (comentário em `hook_execution_service.rb:130-134`).

No funil Tozi, handoff vira "Qualificado" via `Spx::Tozi::FunnelAutomationListener#assignee_changed` (`app/listeners/spx/tozi/funnel_automation_listener.rb:42-52`: assignee User real + estágio pré-venda → move card + cancela cadência HSM).

## 8. Follow-up (cutucada decidida pelo agente)

- `Captain::Tools::ProgramarFollowupTool` (`enterprise/lib/captain/tools/programar_followup_tool.rb:13-31`): o agente escolhe minutos (clamp 2-2880) e motivo; grava `followup_token` (UUID) + `followup_motivo`/`followup_status` em custom_attributes; move card pra "Em Silêncio"; agenda `FollowupJob.set(wait:)`. Reprogramar substitui o token (invalida o job antigo).
- `Captain::Conversation::FollowupJob` (`enterprise/app/jobs/captain/conversation/followup_job.rb:11-42`): guards — token atual, `atendimento_humano`, resolved, cliente já respondeu (`lead_replied?`, 53-56), quiet hours 21h-8h America/Cuiaba (remarca pra manhã, 58-66). `MAX_FOLLOWUPS = 4`; estourou → `tozi_status_lead='esfriado'` + card "Frio" + `Spx::Tozi::ReactivationCadenceService` (cadência HSM fora da janela 24h). Senão incrementa `followup_count` e roda `ResponseBuilderJob.perform_now(conversation, assistant, directive:)` — a diretiva (46-51) é um turno user interno `[NOTA INTERNA...]` instruindo cutucada curta ou `[IGNORAR]`.
- `SalvarInfoLeadTool` (`enterprise/lib/captain/tools/salvar_info_lead_tool.rb:13-43`): grava `tozi_status_lead`/`sobre_cliente`; status qualificado/convertido → card Qualificado + cancela cadência; esfriado/perdido → card Frio + dispara cadência HSM.

## 9. Auto-resolve

- Cron: `TriggerScheduledItemsJob` a cada 5 min (`config/schedule.yml:13-16`) → `Account::ConversationsResolutionSchedulerJob` → overlay `Enterprise::Account::ConversationsResolutionSchedulerJob#resolve_captain_conversations` (`enterprise/app/jobs/enterprise/account/conversations_resolution_scheduler_job.rb:10-21`): itera **TODAS** as `CaptainInbox` da instância, pula e-mail e contas com `captain_auto_resolve_disabled?`, enfileira `Captain::InboxPendingConversationsResolutionJob`.
- `Captain::InboxPendingConversationsResolutionJob` (`enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb`): trava dupla (linha 8). Alvo = conversas **pending** com `last_activity_at < 1h` (56-60, cutoff 69-71). Dois modos:
  - **legacy** (time-based, 25-32): manda `config['resolution_message']` (ou i18n `auto_resolution_message`, no locale da conta) e `resolved!` — foi este o autor das mensagens "Resolvendo a conversa dado que está inativa..." do incidente.
  - **evaluated** (`captain_tasks` + modo evaluated, 21-23, 34-47): `Captain::ConversationCompletionService` avalia via LLM; completa → resolve com nota privada "Auto-resolved: ..."; incompleta → `bot_handoff!` com nota "Auto-handoff: ...".
- `captain_auto_resolve_mode` (`app/models/concerns/account_captain_auto_resolve.rb:14-20`): `settings['captain_auto_resolve_mode']` ∈ {evaluated, legacy, disabled}; fallback `disabled` se flag legada `captain_disable_auto_resolve`; senão evaluated/legacy conforme feature `captain_tasks`. Schema validado em `app/models/account.rb:44`. Em prod Tozi está `disabled`.
- Há também a tool `resolve_conversation` pro agente resolver (gateada por `captain_auto_resolve_disabled?` — `enterprise/lib/captain/tools/resolve_conversation_tool.rb:9`).

## 10. Outros componentes do runtime

- **BusinessHoursChecker** (`enterprise/app/services/captain/behavior/business_hours_checker.rb:7-12`): `:inside` se `behavior.business_hours.enabled` falso; senão compara `schedule` (lista `{day, ranges[{start,end}]}`) no `timezone`. Usado em 2 lugares: skip do hook (ação `ignore`) e `time_awareness` do prompt.
- **MediaPipelineService** (`enterprise/app/services/captain/behavior/media_pipeline_service.rb`): **código morto** — nenhum call site no runtime (grep: só a definição). A transcrição de áudio real é `Messages::AudioTranscriptionService` (`enterprise/app/services/messages/audio_transcription_service.rb:29-37`), gate corrigido no commit `1671b9017` pra aceitar `captain_integration` OU `captain_integration_v2`; usada pelo job de recebimento e pelo `Captain::OpenAiMessageBuilderService` (leitura inline do agente).
- **CaptainListener** (`enterprise/app/listeners/captain_listener.rb:4-12`): `conversation_resolved` → gera notas de memória do contato (`feature_memory`) e FAQs da conversa (`feature_faq`) — só se `captain_active?`.
- **Observabilidade**: `Captain::AssistantLog` (`enterprise/app/models/captain/assistant_log.rb:7-10`) com eventos `response, debounce_skip, debounce_fire, router_skip, business_hours_skip, handoff, media_process, humanizer_split, dedup_skip, error, copilot_trigger` — trilha auditável de toda decisão do runtime, ligada a conversation + message. OTel/Langfuse no runner (traces com assistant_id/conversation_id/credit_used).
- **Prompt**: Liquid em `enterprise/lib/captain/prompts/assistant.liquid` (orquestrador; lista cenários como handoffs, regra "só fatos das tools") e `scenario.liquid`; snippets de contexto conversation/contact/campaign. Schema de saída `Captain::ResponseSchema` (`enterprise/lib/captain/response_schema.rb`): `{response, reasoning}`.
- **Tools built-in** (`config/agents/tools.yml`): add_contact_note, add_private_note, update_priority, add_label_to_conversation, faq_lookup, search_knowledge, resolve_conversation, handoff, **buscar_imovel** (Vista), **enviar_fotos_imovel**, **salvar_info_lead**, **programar_followup**. Resolução por convenção `Captain::Tools::{Id}Tool` (`captain_tools_helpers.rb:24-27`). Custom tools HTTP per-conta via `Captain::CustomTool`.

---

## 11. Gaps e riscos

1. **Limbo pending persiste pra quem o router pula.** `reopen_resolved_conversation` manda pra `pending!` em inbox com bot (`app/models/message.rb:466-470`); o `ensure_conversation_open` só abre quem PASSA no router. Com whitelist (`only_contact_phones`) ativa, cliente real que volta numa conversa resolvida fica pending invisível — exatamente o incidente de 02/06. Mitigantes atuais: Enterprise::Message abre no reply humano; auto-resolve disabled. Mas o cliente segue sem resposta e ninguém vê.
2. **Handoff por quota/erro não atribui ninguém** (`hook_execution_service.rb:142-154`; `response_builder_job.rb:128-137`) e o de quota manda texto hardcoded em inglês. Só o HandoffTool atribui — e atribui **qualquer membro online da inbox**, ignorando times, nicho e a custom role restritiva dos corretores (a secretária pode nem ver a conversa atribuída). TODO de team_id existe mas não implementado (`handoff_tool.rb:74-84`).
3. **`ensure_conversation_open` abre sem atribuir** — conversas abertas órfãs (sem assignee) entram na fila geral; interação com a AutomationRule #53 (zera assignee em `conversation_opened`) pode desatribuir de novo.
4. **Chaves LLM globais da instalação, lidas no boot** (`ai_agents.rb:5-27`): sem isolamento por conta no v2; troca de chave exige restart de worker — operacionalmente frágil em SaaS multi-tenant.
5. **`pending_status_enabled=false` + inbox com bot**: `conversation.pending!` no after_commit levanta `RecordInvalid` e pode abortar callbacks seguintes da mensagem (hooks, send_reply) — combinação latente perigosa.
6. **`sleep` do humanizer dentro do job** (até 7s × nº de chunks) segura thread do Sidekiq; debounce também roda `perform_now` dentro de outro job. Sob volume, esgota concorrência do worker.
7. **store_accessor de behavior com nomes errados** (`assistant.rb:42-43`: `router_config` vs chave real `router` etc.) — API/console que usar os accessors grava em chave que o runtime ignora.
8. **MediaPipelineService morto** e flag `media_pipeline` no behavior sem efeito — documentação (AGENTS.md) sugere que funciona.
9. **Auto-resolve em modo legacy é cego** (resolve qualquer pending inativa >1h com mensagem genérica) e o scheduler varre TODAS as CaptainInbox da instância — o desligamento é por conta, não por inbox/assistant.
10. **`skip_after_human_response` olha só as últimas 5 outgoing** (`router_service.rb:108-113`) — janela pequena se houver rajada de NPS/templates.
11. **`max_turns: 100`** no runner (`agent_runner_service.rb:31`) — teto alto de custo/loop em caso de tool-loop.
12. **Captain responde em `open` indefinidamente** até humano falar — se um corretor for atribuído mas demorar, a IA continua conversando em nome dele (pode ser desejado, mas não há sinal visual claro de quem "possui" a conversa).

## 12. Pontos de plugue pra IA orquestradora

- **`behavior` JSONB por assistant** (PUT `/api/v1/accounts/:id/captain/assistants/:id`) — todo o runtime é dirigido por config code-first: router (whitelist/labels/grupos), debounce, business_hours (com `outside_hours_action`), humanizer, dedup, copilot_trigger.
- **Eventos Wisper**: `MESSAGE_CREATED` (com `performed_by`), `CONVERSATION_BOT_HANDOFF` (de `bot_handoff!`), `assignee_changed`, `conversation_resolved` — o `Spx::Tozi::FunnelAutomationListener` é o template de como plugar orquestração por evento sem tocar no core (rescue-wrapped, no-op multi-tenant).
- **Tools como atuadores**: qualquer `Captain::Tools::*Tool` em `config/agents/tools.yml` vira ação do agente (padrão: `BasePublicTool` + `find_conversation(state)`); `HandoffTool` é O ponto pra implementar triagem/atribuição inteligente (team_id, nicho, round-robin ponderado). `Captain::CustomTool` per-conta cobre HTTP externo (CRM, Vista, geocoding).
- **`custom_attributes` da conversa como contrato de estado**: `atendimento_humano` (trava), `followup_token/count/motivo/status`, `tozi_status_lead`, `sobre_cliente` — legíveis por automações, kanban e relatórios.
- **`Captain::AssistantLog`**: telemetria estruturada de cada decisão (router_skip, debounce_fire, handoff...) — base pra dashboards e pra IA auditar a si mesma.
- **`directive:` no ResponseBuilderJob** (`response_builder_job.rb:6,80-82`): canal genérico pra injetar instruções internas no agente (hoje usado pelo follow-up; serve pra qualquer orquestrador externo pedir "faça X nesta conversa").
- **Cenários = sub-agentes plugáveis** com tools próprias e handoff bidirecional — unidade natural pra especializar triagem/qualificação/agendamento.
- **`Captain::ConversationCompletionService`** (modo evaluated do auto-resolve): avaliador LLM de "conversa completa?" reutilizável pra decisões de fechamento/escalonamento.
- **Callbacks do runner** (`runner_callbacks_helper.rb`: on_agent_thinking/on_tool_start/on_tool_complete/on_agent_handoff) — ganchos em tempo real já suportados pelo AgentRunnerService (usados pelo Copilot).
- **`#copilot` em nota privada** (CopilotTriggerService): humano invoca a IA dentro da conversa — caminho pronto pra colaboração humano-IA na triagem.
