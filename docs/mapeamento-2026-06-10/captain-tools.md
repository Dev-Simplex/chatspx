# Mapeamento — Captain Tools (inventário completo de ferramentas da IA no SPX)

> Gerado em 2026-06-10, branch `paulao`. Baseado 100% em leitura do código local (app/ + enterprise/).
> Objetivo: subsidiar o desenho da IA como ORQUESTRADORA (triagem, atribuição, follow-up, campanhas/kanban/CRM).

---

## 0. Visão geral — três planos de ferramentas

Existem **três sistemas de tools** coexistindo, com bases de classe diferentes:

| Plano | Base | Quem executa | Onde registra | Contexto/permissão |
|---|---|---|---|---|
| **Copilot tools** (32) | `Captain::Tools::BaseTool < RubyLLM::Tool` (`enterprise/app/services/captain/tools/base_tool.rb:1`) | Copilot do painel (agente humano conversa com a IA) | Lista hardcoded `TOOL_CLASSES` em `enterprise/app/services/captain/copilot/chat_service.rb:63-95` | Recebe `(assistant, user:)`; `active?` checa permissão do usuário humano (`base_tool.rb:18-28` — custom role → permissions; senão admin/agent) |
| **Agent tools built-in** (12) | `Captain::Tools::BasePublicTool < Agents::Tool` (`enterprise/lib/captain/tools/base_public_tool.rb:3`, gem `agents`) | Agente IA autônomo (Clara) respondendo cliente via Captain v2 runner | `config/agents/tools.yml` (resolvido por convenção `Captain::Tools::{Id.classify}Tool` em `enterprise/app/models/concerns/captain_tools_helpers.rb:24-27`) | Recebe `(assistant)`; **sem checagem de permissão** — roda com poder total da conta (ver §6.5) |
| **Custom tools** (HTTP) | `Captain::Tools::HttpTool < Agents::Tool` (`enterprise/lib/captain/tools/http_tool.rb:3`) | Ambos (agente E copilot) | Tabela `captain_custom_tools` (model `enterprise/app/models/captain/custom_tool.rb`), CRUD via API | Classe gerada dinamicamente por registro do banco (`enterprise/app/models/concerns/toolable.rb:4-32`) |

Há ainda um **quarto copilot OSS paralelo sem tools**: `app/services/copilot/chat_service.rb` (chamada OpenAI direta, só contexto da conversa, max 320 tokens), usado por `app/controllers/api/v1/accounts/conversations/copilot_chats_controller.rb:14`. Não confundir com o Copilot Enterprise.

`Captain::ToolRegistryService` (`enterprise/app/services/captain/tool_registry_service.rb`) é **dead code** — nenhuma referência fora do próprio arquivo.

---

## 1. Copilot tools (32) — `enterprise/app/services/captain/tools/copilot/` + 1 em `tools/`

Instanciadas em `Captain::Copilot::ChatService#build_tools` (`chat_service.rb:98-109`): `TOOL_CLASSES.map { |klass| klass.new(@assistant, user: @user) }.select(&:active?)` + custom tools da conta. Anexadas ao chat RubyLLM via `with_tool` (`enterprise/app/helpers/captain/chat_helper.rb:34-39`), loop agêntico do RubyLLM resolve as chamadas.

Entry points: `Captain::Copilot::ResponseJob` (`enterprise/app/jobs/captain/copilot/response_job.rb:84-90`, painel Copilot com `user_id`) e `Captain::Behavior::CopilotTriggerService` (hashtag `#copilot` em nota privada — ver §5).

### Leitura (17)

| Tool | O que faz | Parâmetros | Permissão (`active?`) |
|---|---|---|---|
| `search_documentation` (`tools/search_documentation_service.rb`) | Busca FAQ/responses aprovadas (com tradução da query via LLM) | query | sempre ativa |
| `get_conversation` | Transcrição da conversa incl. notas privadas (`to_llm_text`) | conversation_id | conversation_manage \| unassigned \| participating |
| `get_conversation_full` | Meta completa: status, prioridade, assignee, team, labels, datas, contato, nº msgs | conversation_id | idem |
| `search_conversation` | Busca conversas por status/contato/prioridade/labels — **respeita PermissionFilterService** (corretor só vê o dele; `search_conversations_service.rb:707-713`) | status, contact_id, priority, labels | idem |
| `get_contact` | Perfil do contato (`to_llm_text`) | contact_id | contact_manage |
| `search_contacts` | Busca contatos por email/telefone/nome | email, phone_number, name | contact_manage |
| `get_contact_conversations` | Histórico de conversas de um contato (status, assignee, inbox) | contact_id, limit | contact_manage |
| `get_article` | Artigo do help center | article_id | knowledge_base_manage |
| `search_articles` | Busca artigos por título/conteúdo/categoria/status | query, category_id, status | knowledge_base_manage |
| `search_messages` | Full-text ILIKE em mensagens da conta | query, limit | conversation_manage |
| `get_account_stats` | Abertas, pendentes, agentes online, CSAT 7d | — | report_manage |
| `get_agent_workload` | Conversas abertas por agente + disponibilidade | — | report_manage |
| `get_agents` | Lista agentes (id, email, role, availability) | — | agent_manage \| report_manage |
| `get_team_info` | Times: membros + fila aberta | — | team_manage |
| `get_inbox_info` | Config da inbox, agentes, fila | inbox_id (opcional) | **administrator** |
| `get_labels` | Lista labels da conta | — | sempre ativa |
| `get_csat_data` | Notas e feedbacks CSAT recentes | days | report_manage |
| `search_linear_issues` | Busca issues no Linear (se hook habilitado) | term | hook linear existente |
| `get_conversation_analysis` (`get_conversation_analysis_service.rb:284-356`) | **Fork-specific**: relatório agregado do eval LLM-as-a-Judge externo (interesse, intenção, funil, objeções, falhas por agente, handoff timing) via `TOZI_EVAL_API_URL` (default `http://127.0.0.1:8910/report`) + token `TOZI_EVAL_API_TOKEN` (env ou InstallationConfig); gated por `TOZI_EVAL_ACCOUNT_ID` | — | report_manage + account == eval_account |

(19 linhas acima porque incluí as 2 sempre-ativas no bloco; total leitura = 19.)

### Escrita (13)

| Tool | O que faz | Parâmetros | Permissão |
|---|---|---|---|
| `assign_conversation` (`assign_conversation_service.rb:48-83`) | **Atribui conversa a agente E/OU time** (`assignee_id`, `team_id`, save!) | conversation_id, agent_id, team_id | conversation_manage |
| `change_status` (`change_status_service.rb`) | Muda status para **qualquer**: open, pending, resolved, snoozed | conversation_id, status | conversation_manage |
| `resolve_conversation` | Resolve via `conversation.resolved!` (dispara CSAT/side-effects) | conversation_id | conversation_manage |
| `snooze_conversation` | Snooze por N horas | conversation_id, hours | conversation_manage |
| `change_priority` | Prioridade none/low/medium/high/urgent | conversation_id, priority | conversation_manage |
| `add_label` / `remove_label` | Adiciona/remove label na conversa | conversation_id, label | conversation_manage |
| `send_message` (`send_message_service.rb:806-829`) | **Envia mensagem (ou nota privada) em QUALQUER conversa por id** via `Messages::MessageBuilder` | conversation_id, content, private | conversation_manage |
| `send_template` (`send_template_service.rb:831-868`) | **Envia HSM WhatsApp em qualquer conversa** — monta `additional_attributes.template_params {name, processed_params}`; exige `Channel::Whatsapp` | conversation_id, template_name, template_params (JSON array) | conversation_manage |
| `transfer_to_inbox` | Move conversa para outra inbox (`update!(inbox_id:)`) | conversation_id, inbox_id | **administrator** |
| `update_contact` | Atualiza nome/email/telefone/empresa do contato | contact_id, name, email, phone_number, company_name | contact_manage |
| `add_note_to_contact` | Nota no perfil do contato | contact_id, content | contact_manage |
| `set_custom_attributes` (`set_custom_attributes_service.rb:870-908`) | Merge de custom_attributes em conversa OU contato (JSON) | target_type, target_id, attributes | conversation_manage \| contact_manage |

**Não existe**: criar contato, criar conversa, mover card de funil/kanban, disparar campanha, gerenciar ScheduledMessages.

---

## 2. Agent tools built-in (12) — `enterprise/lib/captain/tools/` + registro em `config/agents/tools.yml`

Todas herdam `BasePublicTool` (`base_public_tool.rb`): recebem só `(assistant)`, `active?` sempre true, acham a conversa pelo **estado do runner** (`find_conversation(state)` lê `state[:conversation][:id]`, linhas 26-31) — ou seja, **operam SEMPRE na conversa corrente**, nunca em outra. O método `permissions` (linhas 14-18) é decorativo: **nenhum código o consulta** (verificado por grep em app/ + enterprise/).

### Genéricas upstream-style (7)

| Tool (id no tools.yml) | Arquivo | O que faz |
|---|---|---|
| `faq_lookup` | `faq_lookup_tool.rb` | Busca vetorial nas Q&A aprovadas do assistant (`assistant.responses.approved.search`) |
| `search_knowledge` | `enterprise/app/services/captain/tools/search_knowledge_tool.rb` | Chunk-RAG híbrido (vetorial + full-text RRF) em `Captain::DocumentChunk.hybrid_search` — fork-specific |
| `handoff` | `handoff_tool.rb` | Ver §2.1 — transfere pra humano |
| `resolve_conversation` | `resolve_conversation_tool.rb` | `conversation.resolved!` com contexto de atividade; **bloqueada se `captain_auto_resolve_disabled?`** (linha 8) |
| `add_private_note` | `add_private_note_tool.rb` | Cria mensagem outgoing `private: true` com sender = assistant |
| `add_contact_note` | `add_contact_note_tool.rb` | Nota no contato da conversa |
| `add_label_to_conversation` | `add_label_to_conversation_tool.rb` | Adiciona label (precisa existir `Label` na conta; normaliza lowercase) |
| `update_priority` | `update_priority_tool.rb` | Prioridade da conversa corrente |

(8 listadas — `update_priority` incluída.)

### Tozi-specific (4)

#### `buscar_imovel` (`buscar_imovel_tool.rb:1-100`)
- Consulta **Vista CRM** (`GET {base}/imoveis/listar`) com filtro JSON: Cidade=Sinop fixo, Status like %vend%/%alug%, Categoria, Bairro (like parcial), Endereco (like), Dormitorios, ValorVenda/ValorLocacao máx, **bbox lat/lng** (vindo do custom tool de geocoding).
- Env vars: `TOZI_VISTA_API_KEY` (gotcha: vault chama `VISTA_API_KEY`), `TOZI_VISTA_BASE_URL` (default `https://toz19328-rest.vistahost.com.br`).
- Retorna até 5 imóveis com URL do site montada por slug (`build_url` linhas 81-92: usa `ImoCodigo`, não `Codigo`).
- Params: status_tipo (obrigatório), categoria, bairro, endereco, valor_max, dormitorios, lat_min/max, lng_min/max.

#### `enviar_fotos_imovel` (`enviar_fotos_imovel_tool.rb:1-90`)
- Busca fotos no Vista (`/imoveis/detalhes`), **envia em lotes de 3** como attachments (download via `Down`, cria Message outgoing + Attachment image), 2s entre fotos (rajada entrega só a 1ª no bridge WhatsApp).
- Paginação persistida em `conversation.custom_attributes['fotos_offset_{codigo}']` — chamar de novo manda as próximas 3.
- Param: codigo (do resultado da busca).

#### `programar_followup` (`programar_followup_tool.rb:13-30`)
- O agente **decide e agenda a própria cutucada**: grava `followup_token` (SecureRandom), `followup_motivo`, `followup_status` em custom_attributes; move card do funil para **'em_silencio'** (`Spx::Tozi::FunnelPlacementService.move`, linha 25); agenda `Captain::Conversation::FollowupJob` com wait de 2 a 2880 min (linha 26). Reprogramar substitui (token novo invalida o job antigo).
- **FollowupJob** (`enterprise/app/jobs/captain/conversation/followup_job.rb`): guards — token atual, sem trava `atendimento_humano`, não-resolvida, cliente não respondeu (`lead_replied?`), fora de quiet hours 21h-8h America/Cuiaba (remarca pra manhã). `MAX_FOLLOWUPS = 4`; ao estourar: status_lead='esfriado', card → **'frio'**, dispara `Spx::Tozi::ReactivationCadenceService` (cadência HSM 1d/3d/7d fora da janela, `app/services/spx/tozi/reactivation_cadence_service.rb:20,48-58`). Senão, re-invoca `ResponseBuilderJob.perform_now(conversation, assistant, directive:)` com nota interna "[NOTA INTERNA...]" — **o próprio agente gera a cutucada no contexto** (directive em `followup_job.rb:46-51`).

#### `salvar_info_lead` (`salvar_info_lead_tool.rb:13-52`)
- Grava `tozi_status_lead` (novo/em_contato/qualificado/esfriado/perdido/convertido) e `sobre_cliente` em custom_attributes.
- Side-effects de funil (`move_funnel_by_status`, linhas 33-42): qualificado/convertido → cancela cadência pendente + card 'qualificado'; esfriado/perdido → card 'frio' + agenda ReactivationCadence.
- `precisa_followup: true` → label `followup-ativo`.

#### 2.1 `handoff` em detalhe (`handoff_tool.rb:5-73`) — a única "atribuição" do agente
1. Posta `reason` como nota privada (sender = assistant).
2. `conversation.bot_handoff!` → status open + eventos.
3. `assign_to_available_agent` (linhas 52-62): **se ainda sem assignee**, roda `AutoAssignment::AgentAssignmentService` com `allowed_agent_ids` = TODOS os membros da inbox — **round-robin entre agentes online, sem direcionamento**. Comentário no código: "A roleta por nicho (Vista/Loft) virá depois".
4. Suprime OOO pra conversas de campanha; senão manda template OutOfOffice se aplicável.
5. **TODO explícito no código (linhas 75-88):** aceitar `team_id`, `priority`, `escalation_level` — ou seja, o próprio autor já mapeou o gap de atribuição direcionada.

---

## 3. Custom tools — `Captain::CustomTool` (tabela `captain_custom_tools`)

**Model** (`enterprise/app/models/captain/custom_tool.rb`): `account_id`, `title`, `slug` (auto: `custom_{title-param}`, único por conta), `description`, `endpoint_url` (obrigatória), `http_method` GET/POST, `param_schema` JSONB (array de {name, type, description, required}), `request_template`/`response_template` (**Liquid** strict), `auth_type` none/bearer/basic/api_key + `auth_config` JSONB, `enabled`, **`copilot_only`** (default false).

**CRUD via API**: `enterprise/app/controllers/api/v1/accounts/captain/custom_tools_controller.rb` (`/api/v1/accounts/:id/captain/custom_tools`) — é assim que o Claude Code (filosofia code-first) registra tools.

**Materialização** (`Concerns::Toolable#tool`, `toolable.rb:4-32`): gera **classe anônima por chamada** herdando `HttpTool`, com `description` + `param` do schema, registrada como constante `Captain::Tools::{Slug.camelize}` (necessário porque RubyLLM deriva o nome da função do nome da classe). Refresh a cada chamada → mudanças de metadata refletem sem restart.

**Execução** (`HttpTool#perform`, `http_tool.rb:14-24`):
- URL e body renderizados com Liquid sobre os params (`build_request_url`/`build_request_body`, `toolable.rb:34-44`).
- **Headers de metadata automáticos** (`build_metadata_headers`, `toolable.rb:69-98`): `X-Chatwoot-Account-Id`, `X-Chatwoot-Assistant-Id`, `X-Chatwoot-Tool-Slug`, `X-Chatwoot-Conversation-Id`, `X-Chatwoot-Conversation-Display-Id`, `X-Chatwoot-Contact-Id/Email/Phone`, `X-Chatwoot-Contact-Inbox-Id/Verified` — **um webhook out-of-the-box com contexto da conversa** (hook de orquestração pronto).
- Guard-rails (`http_tool.rb:27-77`): **bloqueia hostname que resolve pra IP privado** (127/8, 10/8, 172.16/12, 192.168/16, link-local, IPv6 ULA), resposta máx 1MB, sem redirects, timeout 30s/10s.
- `response_template` Liquid formata o JSON de resposta pro LLM (`format_response`, `toolable.rb:100-105`).

**Em produção (Tozi, Account 6, segundo STATE.md):** custom tool #4 "Buscar localização (geocoding)" — Google Maps Geocoding com a chave EMBUTIDA na endpoint_url (registro de banco, não código); alimenta o bbox do `buscar_imovel`. Custom tool #3 "Buscar imóveis no Vista" está `enabled=false` (substituída pela built-in).

---

## 4. Como as tools chegam ao LLM

### 4.1 Fluxo do agente autônomo (Captain v2 — gem `agents`)
1. `Captain::Conversation::ResponseBuilderJob#perform` → se `captain_v2_enabled?`, `generate_response_with_v2` (`response_builder_job.rb:18-22,43-48`) → `Captain::Assistant::AgentRunnerService`.
2. `AgentRunnerService#build_and_wire_agents` (`agent_runner_service.rb:167-175`): `assistant.agent` + `assistant.scenarios.enabled.map(&:agent)`; **handoffs bidirecionais** registrados (router → cenário e cenário → router). `Agents::Runner.with_agents(...)`, `max_turns: 100` (linha 31).
3. `Concerns::Agentable#agent` (`agentable.rb:4-13`): monta `Agents::Agent.new(name:, instructions: λ, tools: agent_tools, model:, temperature:, response_schema: Captain::ResponseSchema)`. Modelo vem de `account.captain_assistant_model` (dropdown LLM Settings) com fallback `LlmConstants::DEFAULT_MODEL` (linhas 43-46).
4. **Tools do agente raiz** (`Captain::Assistant#agent_tools`, `assistant.rb:118-129`): fixas — `faq_lookup` + `handoff`, mais `search_knowledge` se `knowledge_mode` ∈ {chunks, hybrid}. O assistant raiz NÃO carrega as tools de ação.
5. **Tools por cenário** (`Captain::Scenario`): o prompt do cenário (instruction) referencia tools em markdown `[Nome](tool://tool_id)`; `before_save :resolve_tool_references` (`scenario.rb:171-176`) extrai os ids pro campo JSONB `tools`; validação rejeita ids inexistentes (`validate_instruction_tools`, `scenario.rb:143-155`). Em runtime, `agent_tools` (`scenario.rb:100-102`) → `resolved_tools` filtra contra `assistant.available_agent_tools` (`assistant.rb:57-64` = built-ins do tools.yml + custom tools `enabled.where(copilot_only: false)`) → `resolve_tool_instance` (`scenario.rb:117-126`): custom → `CustomTool#tool(assistant)`; built-in → `Captain::Tools::{Id.classify}Tool.new(assistant)`.
6. **Estado**: o runner injeta `context[:state]` com `conversation` (id, display_id, inbox_id, contact_id, status, priority, label_list, custom_attributes, additional_attributes), `contact`, `campaign`, `contact_inbox`, `channel_type`, `assistant_config` (`agent_runner_service.rb:9-21,143-161`). É daí que `BasePublicTool#find_conversation` resolve a conversa — **por isso agent tools não atuam cross-conversation**.
7. Fallback de handoff: quando o último turno é handoff, `result.output` volta vazio; `process_agent_result` recupera o texto da última mensagem do assistente (`agent_runner_service.rb:96-134`) — fix do fork (commit `02bcbac0f`).

### 4.2 Fluxo Copilot (RubyLLM)
`Captain::Copilot::ChatService` monta `@tools` no construtor (`chat_service.rb:21`), e `Captain::ChatHelper#build_chat` anexa cada uma com `chat.with_tool(tool)` (`chat_helper.rb:27-39`); o loop agêntico do RubyLLM executa as chamadas, com spans/eventos (`on_tool_call`/`on_tool_result`, `chat_helper.rb:52-58`). System prompt inclui sumário das tools (`tools_summary`, `chat_service.rb:121-123`).

### 4.3 Fluxo v1 (legado, sem flag `captain_integration_v2`)
`Captain::Llm::AssistantChatService#build_tools` = **só** `SearchDocumentationService` (`assistant_chat_service.rb:32-34`). Nenhuma tool de ação.

---

## 5. Gatilho `#copilot` em nota privada — hook existente mas semifuncional

`Captain::Behavior::CopilotTriggerService` (`enterprise/app/services/captain/behavior/copilot_trigger_service.rb`): se `behavior['copilot_trigger']['enabled']` e a mensagem é **nota privada** contendo a hashtag (default `#copilot`), dispara `Captain::Copilot::ChatService` na conversa. Chamado de `Enterprise::MessageTemplates::HookExecutionService#trigger_copilot_if_applicable` (`hook_execution_service.rb:100-107`), com log em `Captain::AssistantLog` (event_type `copilot_trigger`).

**Dois problemas hoje:**
1. O config não passa `user_id` → `@user = nil` → `active?` de quase todas as tools de escrita/leitura retorna false (`user_has_permission` exige user, `base_tool.rb:18-28`). Sobram só `search_documentation`, `get_labels` e as custom tools. Ou seja, o gatilho não consegue atribuir/enviar/resolver.
2. A resposta textual é **descartada**: sem `copilot_thread_id` o `persist_message` vira no-op (`chat_service.rb:138-146`), e o retorno de `service.trigger` é ignorado pelo caller. Side-effects de tools aconteceriam, mas as tools de ação estão inativas (item 1).

É o esqueleto perfeito de um "command channel" humano→IA dentro da conversa, mas precisa de: passar um user (ou bypass de permissão), e postar o resultado como nota privada.

---

## 6. Respostas diretas — o que a IA consegue HOJE via tool

| Capacidade | Agente autônomo (v2 runner) | Copilot (painel) |
|---|---|---|
| **Atribuir conversa a agente/time** | ⚠️ Só indireto: `handoff` → `bot_handoff!` + round-robin entre membros **online** da inbox (`handoff_tool.rb:52-62`). **Sem** agent_id/team_id (TODO no código, linhas 75-88) | ✅ `assign_conversation` com agent_id e/ou team_id (`assign_conversation_service.rb`) |
| **Etiquetar** | ✅ `add_label_to_conversation` (label precisa existir); `salvar_info_lead` põe `followup-ativo` | ✅ `add_label` / `remove_label` |
| **Resolver** | ✅ `resolve_conversation` (gated por `captain_auto_resolve_disabled?` — hoje DISABLED na conta 6!) | ✅ `resolve_conversation`, `change_status`, `snooze_conversation` |
| **Abrir / mudar status livre** | ⚠️ Só via `handoff` (bot_handoff! → open). Sem tool "open"/"pending" | ✅ `change_status` aceita open/pending/resolved/snoozed |
| **Mover card de funil/kanban** | ⚠️ Só como efeito colateral hardcoded: `programar_followup`→em_silencio; `salvar_info_lead`→qualificado/frio; FollowupJob(max)→frio. **Não existe** tool `mover_card(stage)` | ❌ Nenhuma tool de funil no copilot |
| **Mandar mensagem em OUTRA conversa** | ❌ Tools amarradas a `state[:conversation]` (base_public_tool.rb:26-31) | ✅ `send_message(conversation_id)` e `send_template` (HSM, exige Channel::Whatsapp) |
| **Mandar HSM (fora da janela 24h)** | ❌ direto (só a cadência determinística `ReactivationCadenceService` via ScheduledMessages) | ✅ `send_template` — formato `processed_params` JSON |
| **Criar contato** | ❌ | ❌ (só `update_contact`, `search_contacts`, `add_note_to_contact`, `set_custom_attributes`) |
| **Criar conversa** | ❌ | ❌ |
| **Transferir de inbox** | ❌ | ✅ `transfer_to_inbox` (exige administrator) |
| **Custom attributes** | ⚠️ Indireto (salvar_info_lead grava chaves fixas) | ✅ `set_custom_attributes` (conversa ou contato, JSON livre) |
| **Consultar carga/agentes/times** | ❌ | ✅ `get_agents`, `get_agent_workload`, `get_team_info`, `get_inbox_info`, `get_account_stats` |
| **CRM externo (Vista)** | ✅ `buscar_imovel`, `enviar_fotos_imovel` | ✅ via custom tools (HttpTool pluga nos dois) |

### 6.5 Quão perto a infra de copilot tools está de virar agent tools

**Perto — a ponte já existe e está provada.** As duas hierarquias são compatíveis com os dois runtimes:
- `HttpTool` herda de `Agents::Tool` e roda **nos dois fluxos** — o próprio código comenta: "HttpTool herda de Agents::Tool (RubyLLM-compatível), então pluga direto via with_tool" (`chat_service.rb:99-101`).
- A diferença prática entre `BaseTool` (copilot) e `BasePublicTool` (agent) é: (a) assinatura `execute(**params)` vs `perform(tool_context, **params)`; (b) alvo explícito por `conversation_id` vs alvo implícito pelo state; (c) `active?` com permissão de user vs sempre-ativo.

**Receita pra portar uma copilot tool pro agente** (ex.: dar `assign_conversation` à Clara):
1. Criar `enterprise/lib/captain/tools/{nome}_tool.rb` herdando `BasePublicTool`, com `perform(tool_context, ...)` — pode delegar a lógica da copilot service ou reimplementar (~20 linhas, padrão já estabelecido 4× pelas tools Tozi).
2. Registrar id/título/descrição em `config/agents/tools.yml` (resolução por convenção de nome).
3. Referenciar `[Nome](tool://id)` na instruction do cenário (ou adicionar em `Assistant#agent_tools` pra valer no agente raiz).
4. **Decisão de produto/segurança, não técnica:** agent tools não têm checagem de permissão (o `permissions` de BasePublicTool nunca é consultado) — o agente rodaria atribuição/envio com poder total da conta. Guardrails teriam que ser implementados na própria tool (ex.: validar que o agent_id pertence à inbox, time permitido por config do behavior).

O gap real pro papel de **orquestradora** não é o catálogo de tools — é (i) tool de atribuição direcionada no fluxo do agente, (ii) capacidade cross-conversation (hoje só copilot tem), (iii) tool de funil explícita, (iv) criação de contato/conversa.

---

## 7. Gaps e riscos

1. **Atribuição direcionada inexistente no agente**: `handoff` faz round-robin entre TODOS os membros online da inbox — numa inbox com corretores de role restritiva + secretária, o lead pode cair com qualquer um (inclusive repetir o problema "corretor que a secretária não vê"). TODO de team_id/priority/escalation já anotado no código (`handoff_tool.rb:75-88`).
2. **Agent tools presas à conversa corrente** (`state[:conversation][:id]`): a IA orquestradora não consegue, no fluxo do agente, agir sobre outras conversas (re-atribuir fila, mandar follow-up em outra thread). A infra que faz isso (copilot) só roda com user humano.
3. **`permissions` de BasePublicTool é dead code** — agent tools rodam sem nenhum gate; ao portar tools de escrita pro agente, os guardrails têm que ser construídos.
4. **`Captain::ToolRegistryService` é dead code** (zero referências).
5. **Acoplamento Tozi dentro de tools genéricas**: `programar_followup_tool.rb:25` e `salvar_info_lead_tool.rb:36-42` chamam `Spx::Tozi::FunnelPlacementService`/`ReactivationCadenceService` direto (no-op em contas sem o funil, mas é lógica de cliente em `enterprise/lib`). Generalização multi-cliente vai exigir extrair isso pra config/behavior.
6. **Gatilho `#copilot` semifuncional**: sem user → tools de ação inativas; resposta descartada (§5). Hoje não serve como canal de comando humano→IA.
7. **HttpTool bloqueia IPs privados** (`http_tool.rb:27-37`): custom tool não consegue chamar serviço interno (ex.: orquestrador na mesma VPC/localhost). A tool nativa `get_conversation_analysis` contorna usando HTTParty direto (127.0.0.1:8910) — qualquer integração interna nova precisa ser tool nativa, não custom tool.
8. **Credencial embutida**: geocoding (custom tool em prod) tem a chave Google na endpoint_url (registro de banco); `auth_config` JSONB guarda tokens em claro.
9. **`resolve_conversation` (agente) gated por `captain_auto_resolve_mode`**: com 'disabled' (estado atual da conta 6), o agente não consegue resolver conversa nem deliberadamente — o kill-switch do incidente de auto-resolve também desativou a tool (`resolve_conversation_tool.rb:8`).
10. **`send_template` (copilot) não valida janela 24h nem categoria** — manda o HSM e deixa a Meta rejeitar; sem feedback estruturado de falha pro LLM.
11. **`assign_conversation` (copilot) não valida** se o agente pertence à inbox/time nem se está online — atribuição cega por id.
12. **Catálogo do agente é estático por código** (tools.yml + classes): adicionar capability nova ao agente = deploy; só custom tools (HTTP) são dinâmicas.

---

## 8. Hooks concretos pra IA orquestradora

1. **`Captain::Tools::Copilot::AssignConversationService`** — lógica de atribuição agent/team pronta; portar pra `BasePublicTool` (+ param team_id no handoff) é o caminho mais curto pra triagem por IA.
2. **`AutoAssignment::AgentAssignmentService`** com `allowed_agent_ids` (usado em `handoff_tool.rb:58-61`) — aceita lista restrita: dá pra implementar "roleta por nicho" passando ids filtrados (já previsto em comentário no código).
3. **`Captain::CustomTool` + `HttpTool` headers X-Chatwoot-*** (`toolable.rb:69-98`) — webhook com contexto completo (account, assistant, conversation, contact) pra delegar decisões a um serviço orquestrador externo; criável via API (`custom_tools_controller.rb`) sem deploy. Limitação: endpoint precisa ser público (SSRF guard).
4. **`ProgramarFollowupTool` + `FollowupJob` + directive** — o mecanismo de "re-invocar o agente com instrução interna" (`ResponseBuilderJob.perform_now(conversation, assistant, directive:)`, `followup_job.rb:42`) é genérico: qualquer orquestrador pode acordar a IA numa conversa com uma diretiva contextual.
5. **`Spx::Tozi::FunnelPlacementService.move/current_type`** (`funnel_placement_service.rb:23-41`) — API de funil idempotente já consumida pelas tools; embrulhar numa agent tool `mover_card(stage)` é trivial.
6. **`SendTemplateService` (copilot)** — formato pronto de HSM via `template_params` no MessageBuilder; é a peça pra IA reengajar lead fora da janela 24h (portar pro agente ou pra um job orquestrado).
7. **`Captain::Behavior::CopilotTriggerService`** — canal de comando via nota privada `#copilot`; precisa de user/permissão + postback do resultado pra virar interface humano→IA dentro da conversa.
8. **`Captain::AssistantLog`** (event_types: handoff, media_process, humanizer_split, dedup_skip, error, copilot_trigger — `assistant_log.rb:9`) — trilha de auditoria onde a orquestração pode logar decisões.
9. **`get_conversation_analysis`** — padrão de integração com serviço de eval externo (token via env/InstallationConfig, gated por conta): template pra plugar outros serviços de inteligência no copilot.

---

## 9. Arquivos-chave

| Path | Papel |
|---|---|
| `enterprise/app/services/captain/copilot/chat_service.rb` | Registro (TOOL_CLASSES :63-95) e build (:98-109) das 32 copilot tools + custom |
| `enterprise/app/services/captain/tools/base_tool.rb` | Base copilot (RubyLLM::Tool) + permissão por user/custom role |
| `enterprise/app/services/captain/tools/copilot/*.rb` | 31 copilot tools (CRUD conversa/contato/labels/stats/mensagens/HSM) |
| `enterprise/app/services/captain/tools/search_documentation_service.rb` | 32ª copilot tool (RAG FAQ) |
| `enterprise/lib/captain/tools/base_public_tool.rb` | Base agent tools (Agents::Tool), alvo via state |
| `enterprise/lib/captain/tools/{handoff,resolve_conversation,add_*,update_priority,faq_lookup}_tool.rb` | Agent tools genéricas |
| `enterprise/lib/captain/tools/{buscar_imovel,enviar_fotos_imovel,programar_followup,salvar_info_lead}_tool.rb` | Agent tools Tozi (Vista CRM, fotos, follow-up, lead status + funil) |
| `enterprise/app/services/captain/tools/search_knowledge_tool.rb` | Chunk-RAG híbrido do agente |
| `enterprise/lib/captain/tools/http_tool.rb` | Executor HTTP das custom tools (SSRF guard, Liquid, auth) |
| `enterprise/app/models/captain/custom_tool.rb` + `enterprise/app/models/concerns/toolable.rb` | Model/materialização dinâmica das custom tools |
| `enterprise/app/controllers/api/v1/accounts/captain/custom_tools_controller.rb` | API de registro (code-first) |
| `config/agents/tools.yml` | Catálogo dos 12 agent tools built-in |
| `enterprise/app/models/concerns/captain_tools_helpers.rb` | Resolução id→classe + parse `tool://` |
| `enterprise/app/models/captain/assistant.rb` | `available_agent_tools` (:57-64), `agent_tools` raiz (:118-129), knowledge_mode |
| `enterprise/app/models/captain/scenario.rb` | Tools por cenário via instruction (:100-126, :171-176) |
| `enterprise/app/models/concerns/agentable.rb` | Construção do Agents::Agent (tools, model, time_awareness) |
| `enterprise/app/services/captain/assistant/agent_runner_service.rb` | Runner v2: wiring de agents/handoffs (:167-175), state (:143-161) |
| `enterprise/app/jobs/captain/conversation/response_builder_job.rb` | Entry point do agente (v1/v2 switch :18-22) |
| `enterprise/app/jobs/captain/conversation/followup_job.rb` | Execução da cutucada (guards, quiet hours, MAX=4, funil/cadência) |
| `enterprise/app/jobs/captain/copilot/response_job.rb` | Entry point do Copilot do painel |
| `enterprise/app/services/captain/behavior/copilot_trigger_service.rb` | Gatilho `#copilot` em nota privada (semifuncional) |
| `enterprise/app/helpers/captain/chat_helper.rb` | `with_tool` no RubyLLM (:34-39), loop agêntico copilot |
| `app/services/spx/tozi/funnel_placement_service.rb` | API do funil consumida pelas tools |
| `app/services/spx/tozi/reactivation_cadence_service.rb` | Cadência HSM disparada por tools/FollowupJob |
| `enterprise/app/services/captain/tool_registry_service.rb` | DEAD CODE |
| `app/services/copilot/chat_service.rb` | Copilot OSS paralelo SEM tools (não confundir) |
