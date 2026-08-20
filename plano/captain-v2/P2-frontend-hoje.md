# P2 — O copiloto do agente hoje: superfície, fronteira com os Agentes de IA, e o que a reescrita pode tocar

**Data:** 28/07/2026 · **Base:** VM 192.168.8.232 (homologação), branch `homologacao`, HEAD `ee87f5e799`
**Escopo:** pesquisa. Nenhuma linha de código alterada, nenhum commit, nenhum deploy.

**Alvo (corrigido pelo Walisson):** o **chat de copiloto que o agente humano usa dentro da conversa**.
**Zona proibida:** os **Agentes de IA** que atendem o cliente (assistentes, cenários, base de conhecimento,
avaliação, handoff, auto-resolve). Não proponho mudança neles.

Convenção de classificação usada no documento inteiro:

- **[COPILOTO]** — alvo da reescrita, mexer à vontade
- **[AGENTES-IA]** — não tocar
- **[COMPARTILHADO]** — os dois lados usam; cada item aqui é um risco de a reescrita do copiloto
  quebrar o atendimento ao cliente, que está em produção

**[FATO]** = verificado neste repo/banco/tela. **[HIPÓTESE]** = inferência minha, não verificada.

---

## 0. Resposta direta às 4 perguntas do coordenador

**1. O copiloto usa o assistente para quê, exatamente?**
Para **quatro** coisas, não uma: **(a) persona/prompt** — `assistant.config['product_name']` e
`assistant.config` alimentam o system prompt (`captain/copilot/chat_service.rb:111-120`);
**(b) RAG** — a tool `search_documentation` consulta `assistant.responses.approved.search(...)`, ou seja,
as FAQs aprovadas **daquele assistente** (`search_documentation_service.rb:16`);
**(c) tools** — 32 tools nativas recebem o assistente no construtor **+** todas as custom tools da conta
(`chat_service.rb:98-109`); **(d) temperatura** — `assistant.config['temperature']`
(`chat_helper.rb:98-100`).
**Não usa** para escolher o modelo: existe `captain_models['copilot']` separado de
`captain_models['assistant']` (`app/models/account.rb:53-64`), e na conta 3 os dois estão de fato
diferentes (`copilot=gpt-4.1`, `assistant=claude-sonnet-4.5`). [FATO]

**2. Dá para trocar interface e motor mantendo o vínculo intacto? Onde doeria?**
**Sim.** O vínculo é `copilot_threads.assistant_id`, usado só como *ponteiro de configuração* — o
copiloto **lê** do assistente e nunca **escreve** nele. Trocar UI e motor de chat preservando
`assistant_id` é viável.
Doeria em três pontos: **(a)** `assistant.responses` é a fonte do RAG — aposentar Respostas Prontas
migrando o acervo para `captain_assistant_responses` **escreve na tabela dos Agentes de IA** (§4.1);
**(b)** as tools são compartilhadas e várias **escrevem em conversa real** (§3.4) — é aqui que mora o
risco de o copiloto "falar com o cliente"; **(c)** `increment_response_usage` (`chat_service.rb:31`)
soma o uso do copiloto no mesmo contador de plano do agente de atendimento — mais uso de copiloto
consome cota do atendimento (§3.3).

**3. O copiloto escreve em tabela dos Agentes de IA?**
**Hoje, quase não.** Verificado um a um: **não** grava em `captain_assistant_logs` (só
`response_builder_job.rb:485`, `debounced_response_job.rb:18`, `hook_execution_service.rb:102,110` e
`enterprise/concerns/conversation.rb:118` criam — todos do lado atendimento); **não** grava em
`captain_tool_calls` (o `TraceRecorder` é prependado em `BasePublicTool`,
`enterprise/lib/captain/tools/base_public_tool.rb:11`, e as tools do copiloto herdam de
`Captain::Tools::BaseTool`, outra árvore); **não** grava em `captain_documents`. **Escreve sim** em
`accounts` (contador de uso, `chat_service.rb:31`) e, via tools, em `conversations`, `messages`,
`contacts` e `labels` — que não são tabelas de agente, mas são **produção viva**. [FATO — §3.3/§3.4]

**4. Há dois caminhos de copiloto?**
**Há três.** [FATO — §2]
- **C1 — Captain Copilot** (`copilot_threads`/`copilot_messages`, rotas `routes.rb:77-78`): **VIVO**, é
  o que o agente vê. Usa `Captain::Assistant`, 32 tools, RAG.
- **C2 — Copilot OpenAI direto** (`copilot_chat`, `routes.rb:242` + `app/services/copilot/chat_service.rb`):
  **BACKEND VIVO, FRONT MORTO**. O único componente que o chamava
  (`components/widgets/conversation/CopilotPanel.vue`) foi desplugado do `ConversationBox.vue:4-6`
  ("Manter os dois causava 2 painéis sobrepostos"). Endpoint continua exposto. **Zero fronteira com
  os Agentes de IA** — não conhece `Captain::Assistant`, usa `account.settings['openai_api_key']` e
  `gpt-4o-mini` hardcoded.
- **C3 — Ghost suggestion** (`routes.rb:241` + `ghost_suggestion_service.rb`): **VIVO e invisível como
  "copiloto"** — é o texto fantasma no composer, aceito com **Tab** (`ReplyBox.vue:2943-2956`). Mesma
  stack de C2 (OpenAI direto, sem Captain). **Zero fronteira.**

---

## 1. Resumo executivo

O copiloto do agente hoje é **três implementações de backend** e **três de frontend**, construídas em
momentos diferentes, sem um dono único. [FATO]

| # | Camada | Backend | Frontend | Estado |
|---|---|---|---|---|
| C1 | **Captain Copilot** | `captain/copilot/chat_service.rb` + `response_job.rb` (job + WebSocket) | `components/copilot/CopilotContainer.vue` + `components-next/copilot/` | **VIVO** — é o painel que o agente abre |
| C2 | **Copilot OpenAI direto** | `app/services/copilot/chat_service.rb` (síncrono) | `widgets/conversation/CopilotPanel.vue` | **backend vivo, front desplugado** |
| C3 | **Ghost suggestion** | `app/services/copilot/ghost_suggestion_service.rb` | `ReplyBox.vue` (texto fantasma + Tab) | **VIVO** |
| C4 | **Ações inline ✨ no composer** | `captain/tasks_controller.rb` (síncrono) | `WootWriter/CopilotMenuBar.vue` + `useCopilotReply.js` | **VIVO — o caminho mais usado** |
| C5 | **AI Assistant V2** (painel novo) | reusa C4 | `components-next/ai-assistant/` | **montado, desligado por flag, i18n 100% quebrado** |

Cinco achados que mudam o plano:

1. **A fronteira tem nome e é fina.** `copilot_threads.assistant_id` → `Captain::Assistant`
   (`enterprise/app/models/copilot_thread.rb:22`). O copiloto **consome** o assistente (prompt, FAQ, tools,
   temperatura) e **não escreve** nele. Trocar UI e motor mantendo esse ponteiro é possível. §3
2. **RISCO CRÍTICO — o copiloto pode falar com o cliente hoje.** A tool
   `Captain::Tools::Copilot::SendMessageService` envia mensagem *outgoing* direto na conversa, sem
   aprovação humana, e fica ativa para **qualquer agente ou admin** sem custom role
   (`base_tool.rb:24`). Isso contradiz frontalmente a decisão "o copiloto sugere, o humano aprova". §3.4
3. **O V2 está a 30 minutos de ser avaliável.** As 83 chamadas pedem `CONVERSATION.AI_ASSISTANT_PANEL.*`
   mas as strings foram gravadas na **raiz** do `conversation.json`. Ligando a flag, o painel abre
   exibindo as chaves cruas — confirmado em tela. §7.2
4. **Modelo do copiloto já é configurável em separado** (`captain_models['copilot']`). Um dos poucos
   lugares onde a separação já existe e funciona — dá para trocar o motor do copiloto sem tocar no do
   atendimento. §3.5
5. **Aposentar as Respostas Prontas é barato aqui, mas a migração cruza a fronteira.** São 9 registros
   em 2 contas; o destino natural (`captain_assistant_responses`, hoje com 77) é **tabela dos Agentes
   de IA**. §6

---

## 2. Os três copilotos — mapa e evidência

### C1 — Captain Copilot [COPILOTO, com dependências COMPARTILHADAS]

```
POST /api/v1/accounts/:id/captain/copilot_threads              routes.rb:77
POST .../copilot_threads/:id/copilot_messages                  routes.rb:78
   → copilot_messages_controller.rb:16-22  (grava e ENFILEIRA — não responde)
   → CopilotMessage#enqueue_response_job   copilot_message.rb:40-49
   → Captain::Copilot::ResponseJob         (queue :high, Timeout 30s)  response_job.rb:5,78
   → Captain::Copilot::ChatService         chat_service.rb  ← usa Captain::Assistant
   → resposta persistida em copilot_messages, broadcast COPILOT_MESSAGE_CREATED
   → front recebe por ActionCable          helper/actionCable.js:43,280
```

Sem streaming. O front ainda faz **polling de 2s com timeout de 30s** como fallback
(`CopilotContainer.vue:38-39, 222-240`). Tipos de mensagem: `user`, `assistant`, `assistant_thinking`
(`copilot_message.rb:22`); o front também renderiza `tool_call` (`CopilotPanel.vue:207-213`).
Uso real em homologação: **5 threads, 12 mensagens, última em 04/05/2026**. [FATO — SELECT]

### C2 — Copilot OpenAI direto [COPILOTO puro — sem fronteira]

```
POST/GET/DELETE /conversations/:id/copilot_chat                routes.rb:242
   → copilot_chats_controller.rb
   → Copilot::LanguageDetectorService  (detecta idioma, cache 1h)
   → Copilot::ChatService              (OpenAI direto, síncrono)
   → histórico em conversation.additional_attributes['copilot_history'], limite 50
```

`app/services/copilot/chat_service.rb`: prompt em português escrito à mão (linhas 50-60), contexto =
últimas 20 mensagens públicas + contato + status + prioridade (linhas 62-76), `MAX_HISTORY=8`,
`MAX_TOKENS=320`, `temperature 0.4`. Chave: `account.settings['openai_api_key']` ou `ENV['OPENAI_API_KEY']`
(`openai_settings.rb:16-20`). Modelo: `gpt-4o-mini` (`openai_settings.rb:2`).
**Não conhece `Captain::Assistant`, não tem tools, não tem RAG.** [FATO]

**Front morto:** `components/widgets/conversation/CopilotPanel.vue` chama `ConversationAPI.copilotChat`
(linha 70) e **não é importado por ninguém**. O `ConversationBox.vue:4-6` documenta a remoção.
⚠️ O endpoint continua **exposto e funcional** — dívida de segurança/custo silenciosa. [FATO]

### C3 — Ghost suggestion [COPILOTO puro — sem fronteira]

```
POST /conversations/:id/ghost_suggestion                       routes.rb:241
   → Copilot::GhostSuggestionService  (OpenAI direto, cache 5min por mensagem)
   → front: ReplyBox.vue:2317-2334 (fetch) e 2943-2956 (render + Tab pra aceitar)
```

Sugere **uma** frase de até 140 caracteres a partir da última mensagem do cliente
(`ghost_suggestion_service.rb:63-69`). É o ponto de contato de IA com **menor atrito de todos: zero
cliques, Tab aceita**. Mesma stack do C2. [FATO]

**[HIPÓTESE]** É o melhor protótipo do que o Walisson quer: IA sugere, humano aprova com um toque. Vale
preservar o gesto no redesign.

### C4 — Ações inline ✨ [COPILOTO, dependência COMPARTILHADA no serviço]

`POST /captain/tasks/{rewrite,summarize,reply_suggestion,label_suggestion,follow_up,sentiment_analysis}`
(`app/controllers/api/v1/accounts/captain/tasks_controller.rb`), **síncrono**.
Front: menu ✨ do composer (`CopilotMenuBar.vue`), `useCopilotReply.js`, e o command bar (`CMD_AI_ASSIST`).
Tem `follow_up` com `follow_up_context` — multi-turno rudimentar já funcionando (`useCaptain.js:360-392`).

### C5 — AI Assistant V2 [COPILOTO]

`components-next/ai-assistant/` (15 arquivos, 3.083 linhas). Consome C4. Detalhado em §7.

---

## 3. A FRONTEIRA — dependências compartilhadas, uma a uma

Cada item abaixo é um ponto onde mexer no copiloto pode atingir o atendimento ao cliente.

### 3.1 O vínculo estrutural [COMPARTILHADO — o principal]

| Dependência | Onde | Natureza |
|---|---|---|
| `copilot_threads.assistant_id` → `Captain::Assistant` | `enterprise/app/models/copilot_thread.rb:22`; `db/schema.rb:1010` | **Leitura**. `belongs_to` sem `optional: true` → **assistente é obrigatório** para abrir thread |
| Escolha de qual assistente | `CopilotContainer.vue:81-100` | Preferência do usuário → assistente da caixa → primeiro da conta |
| Job recebe o objeto assistente inteiro | `copilot_message.rb:41-48`; `response_job.rb:7,84` | Serializado no payload do job |

[FATO — SELECT] `CopilotThread.where(assistant_id: nil).count = 0`. Todas as 5 threads apontam para um
assistente. Não há caminho "copiloto sem assistente" hoje.

**Consequência prática:** se a conta não tem nenhum `Captain::Assistant`, **não existe copiloto C1**.
O front trata isso mostrando "nenhum assistente disponível" (`CopilotPanel.vue:280-284`).

### 3.2 O que o copiloto lê do assistente [COMPARTILHADO — leitura]

| O que | Onde | Impacto se o assistente mudar |
|---|---|---|
| **Persona/prompt**: `config['product_name']` + `config` inteiro | `captain/copilot/chat_service.rb:111-120` → `SystemPromptsService.copilot_response_generator` (`system_prompts_service.rb:90-120`) | Editar o agente de atendimento muda o tom do copiloto |
| **Citações**: `config['feature_citation']` liga o formato `[[n](URL)]` | `system_prompts_service.rb:91-100` | Flag do assistente controla se o copiloto cita fonte |
| **RAG**: `assistant.responses.approved.search(query)` | `search_documentation_service.rb:16` | FAQ aprovada do assistente **é** a base de conhecimento do copiloto |
| **Temperatura**: `assistant.config['temperature']` | `chat_helper.rb:98-100` | idem |
| **Idioma da conta**: `account.locale_english_name` | `chat_service.rb:129` | — |

**Prompt do copiloto é próprio** (`copilot_response_generator`), separado do prompt do agente de
atendimento — bom sinal: dá para reescrever o prompt do copiloto sem tocar no do atendimento. [FATO]

### 3.3 O que o copiloto escreve [COMPARTILHADO — escrita]

| Tabela | Onde | Risco |
|---|---|---|
| `copilot_threads` / `copilot_messages` | `chat_service.rb:149-156`; `response_job.rb:100-105` | **Nenhum** — tabelas exclusivas do copiloto |
| `accounts` (contador de uso do plano) | `captain/copilot/chat_service.rb:31` → `increment_response_usage` (`plan_usage_and_limits.rb:18`) | **MÉDIO.** O mesmo contador é incrementado pelo agente de atendimento (`response_builder_job.rb:62`) e pelo `base_task_service.rb:30`. Uso pesado de copiloto **consome cota do atendimento** |
| `captain_assistant_logs` | **não escreve** | — |
| `captain_tool_calls` | **não escreve** (ver 3.4) | — |
| `captain_documents` / `captain_assistant_responses` | **não escreve hoje** | ⚠️ passaria a escrever se as Respostas Prontas virarem base de conhecimento (§6) |
| `conversations`, `messages`, `contacts`, `labels` | **via tools** (3.4) | **ALTO** |

**Verificação do `captain_tool_calls`** [FATO]: o `TraceRecorder` (`enterprise/lib/captain/tools/trace_recorder.rb:28`)
é prependado só em `BasePublicTool` (`base_public_tool.rb:11`) — a árvore das tools do **agente de
atendimento** (`atualizar_resumo`, `registrar_assunto`, `salvar_info_lead`…). As 32 tools do copiloto
herdam de `Captain::Tools::BaseTool` (`enterprise/app/services/captain/tools/base_tool.rb:1`), outra
árvore, sem TraceRecorder. Portanto **o copiloto não contamina os traces lidos por
`conversation_eval_service.rb:125` e `episode_gate_service.rb:36`**. Isso é uma boa notícia:
a avaliação dos Agentes de IA não enxerga o copiloto.
Na conta 3, `custom_attributes['eval_enabled'] = true` — ou seja, se um dia o copiloto migrar para
`BasePublicTool`, ele **começaria a poluir o eval de produção**. Não fazer isso.

### 3.4 As 32 tools — o ponto mais perigoso [COMPARTILHADO — escrita em produção]

`captain/copilot/chat_service.rb:63-96` lista as tools. Classifico por efeito:

**Leitura (seguras) — 20:** `search_documentation`, `get_conversation`, `search_conversations`,
`get_contact`, `get_article`, `search_articles`, `search_contacts`, `search_linear_issues`,
`get_account_stats`, `get_agent_workload`, `get_team_info`, `get_csat_data`, `search_messages`,
`get_inbox_info`, `get_conversation_full`, `get_contact_conversations`, `get_labels`, `get_agents`,
`get_conversation_analysis`, `assign_conversation`(*)

**Escrita em produção (perigosas) — 12:**

| Tool | Efeito | Arquivo |
|---|---|---|
| **`send_message`** | **Envia mensagem OUTGOING ao cliente** (ou nota privada) | `copilot/send_message_service.rb:12-20` |
| **`send_template`** | Envia template (WhatsApp) | `copilot/send_template_service.rb` |
| `assign_conversation` | Reatribui a conversa | `copilot/assign_conversation_service.rb` |
| `add_label` / `remove_label` | Mexe nas etiquetas | `copilot/{add,remove}_label_service.rb` |
| `change_status` / `resolve_conversation` / `snooze_conversation` | Muda o estado do atendimento | `copilot/*_service.rb` |
| `change_priority` | Muda prioridade | `copilot/change_priority_service.rb` |
| `transfer_to_inbox` | Move de caixa | `copilot/transfer_to_inbox_service.rb` |
| `update_contact` / `set_custom_attributes` / `add_note_to_contact` | Escreve no contato | `copilot/*_service.rb` |

**`send_message` em detalhe** (`enterprise/app/services/captain/tools/copilot/send_message_service.rb:12-20`):

```ruby
def execute(conversation_id:, content:, private: false)
  ...
  message = Messages::MessageBuilder.new(nil, conversation, params).perform   # sai para o cliente
end
def active? = user_has_permission('conversation_manage')
```

E o gate de permissão (`enterprise/app/services/captain/tools/base_tool.rb:19-27`):

```ruby
return account_user.custom_role.permissions.include?(permission) if account_user.custom_role.present?
account_user.administrator? || account_user.agent?     # ← sem custom role, TODO agente passa
```

**Conclusão [FATO]:** hoje, um agente comum pedindo "responde pra ele que o pedido chegou" ao copiloto
pode resultar em **mensagem enviada ao cliente sem clique de aprovação**. Isso viola a decisão
"o copiloto NÃO fala com o cliente: ele sugere, o humano aprova".

**[HIPÓTESE] Recomendação:** na reescrita, dividir `TOOL_CLASSES` em `READ_ONLY_TOOLS` (sempre ativas) e
`WRITE_TOOLS` (atrás de confirmação explícita na UI, ou removidas do copiloto). Como as tools são
compartilhadas com custom tools da conta (`chat_service.rb:102-107`, hoje 1 habilitada em homologação),
a lista precisa de allowlist, não denylist.

### 3.5 Credencial e modelo [COMPARTILHADO — parcialmente separado]

| Item | Copiloto | Agente de IA | Separado? |
|---|---|---|---|
| **Modelo** | `captain_models['copilot']` | `captain_models['assistant']` | ✅ **SIM** — `app/models/account.rb:53-64`, `captain_featurable.rb:16-20`, `base_ai_service.rb:46-73`. Conta 3: `copilot=gpt-4.1`, `assistant=claude-sonnet-4.5` |
| **Toggle de feature** | `captain_features['copilot']` | `captain_features['assistant']` | ✅ SIM — UI em `settings/captain/Index.vue:89` |
| **Chave de API** | `Llm::Config.context_for_account` | idem | ❌ **NÃO** — `lib/llm/config.rb:33-47`, resolvida por conta via `Llm::AccountCredentialsResolver`. Chave sem saldo derruba os dois |
| **Contador de uso do plano** | `increment_response_usage` | idem | ❌ NÃO (§3.3) |
| **Instrumentação Langfuse** | `feature_name = 'copilot'` (`chat_service.rb:158-160`) | `feature_name` próprio | ✅ SIM — spans separados (`chat_helper.rb:79`) |
| **C2/C3 (OpenAI direto)** | `account.settings['openai_api_key']` / `ENV` | não usa | ✅ SIM — pilha totalmente à parte (`openai_settings.rb:16-20`) |

**Leitura:** a separação de **modelo e feature-toggle já existe e funciona**. O que não é separado é
**chave** e **cota**. [FATO]

### 3.6 Tabela-resumo da fronteira

| # | Dependência | Direção | Caminho:linha | Gravidade |
|---|---|---|---|---|
| 1 | `copilot_threads.assistant_id` | copiloto → agente | `copilot_thread.rb:22` | **Estrutural** — preservar |
| 2 | Prompt/persona do assistente | leitura | `captain/copilot/chat_service.rb:111-120` | Média |
| 3 | RAG em `assistant.responses.approved` | leitura | `search_documentation_service.rb:16` | Média |
| 4 | `assistant.config['temperature']` | leitura | `chat_helper.rb:98-100` | Baixa |
| 5 | 12 tools que escrevem em conversa real | **escrita** | `chat_service.rb:63-96` + `copilot/*_service.rb` | **CRÍTICA** |
| 6 | Custom tools da conta ficam no copiloto | escrita | `chat_service.rb:102-107` | **Alta** |
| 7 | `increment_response_usage` (cota do plano) | escrita | `captain/copilot/chat_service.rb:31` | Média |
| 8 | Chave de API por conta | leitura | `lib/llm/config.rb:33-47` | Média |
| 9 | Migrar canned → `captain_assistant_responses` | **escrita futura** | §6 | **Alta (planejada)** |
| 10 | Se as tools do copiloto migrarem p/ `BasePublicTool` | escrita futura | `base_public_tool.rb:11` | **Alta — evitar** |

---

## 4. Inventário classificado — frontend

### 4.1 [COPILOTO] — alvo da reescrita

| Arquivo | Papel | Vivo? |
|---|---|---|
| `components/copilot/CopilotContainer.vue` (365 l) | Container do painel C1: thread, polling, timeout, guarda de API key | **VIVO** |
| `components-next/copilot/CopilotPanel.vue` (305 l) | O painel em si (fork ChatSPX) | **VIVO** |
| `components-next/copilot/CopilotInput.vue` | Textarea auto-resize, Enter envia | VIVO |
| `components-next/copilot/CopilotQuickActions.vue` | 4 chips | VIVO |
| `components-next/copilot/CopilotAssistantMessage.vue` | Bolha + "Usar"/copiar/👍👎 | VIVO |
| `components-next/copilot/CopilotToolCard.vue` | Card de chamada de ferramenta | VIVO |
| `components-next/copilot/CopilotThinkingGroup.vue` + `ThinkingBlock` | Raciocínio colapsável | VIVO |
| `components-next/copilot/CopilotLoader.vue` | Loader | VIVO |
| `components-next/copilot/ToggleCopilotAssistant.vue` | Troca de assistente (só se >1) | VIVO |
| `components-next/copilot/CopilotLauncher.vue` | Botão flutuante — **escondido em rota de conversa** (linhas 13-34) | VIVO |
| `components-next/copilot/CaptainApiKeyMissingModal.vue` | Modal de chave ausente | VIVO |
| `components-next/ai-assistant/` (15 arq., 3.083 l) | **Painel V2** + composables | **desligado** |
| `WootWriter/CopilotMenuBar.vue` | Menu ✨ do composer | **VIVO — mais usado** |
| `composables/useCopilotReply.js` | Estado das ações inline + follow-up | VIVO |
| `composables/useCaptain.js` | Transporte: timeout, abort, classificação de erro, PII | VIVO |
| `conversation/CopilotEditorSection.vue` + `CopilotEditor.vue` + `copilot/CaptainLoader.vue` | Composer trocado pelo preview da IA | VIVO |
| `store/captain/{copilotThreads,copilotMessages}.js`, `api/captain/{...}.js`, `api/captain/tasks.js` | Estado e HTTP | VIVO |
| `ReplyBox.vue` — ghost suggestion (2317-2334, 2943-2956) | C3 | VIVO |

**Órfãos confirmados** (nenhum import fora de `.story`/`spec`) — apagar na reescrita [FATO]:
`components/widgets/conversation/CopilotPanel.vue` (front do C2), `components-next/copilot/Copilot.vue`
(versão upstream substituída pelo fork), `CopilotEmptyState.vue`, `CopilotAgentMessage.vue`,
`CopilotAvatar.vue`, `CopilotInlineAction.vue`, `CopilotToolCallIndicator.vue`.

### 4.2 [AGENTES-IA] — não tocar

| Área | Arquivos | Nota |
|---|---|---|
| Telas novas "Agentes IA" | `routes/dashboard/agents/` (6 arq., 2.324 l) + `components-next/agents/` (14) + `components-next/agents-ui/` (25) | É o que está no menu (`Sidebar.vue:566-572` → `agents_dashboard`), permissão `administrator` |
| Telas antigas de gestão | `routes/dashboard/captain/` (16 arq., 2.884 l) + `components-next/captain/` (50 arq., 8.873 l) | **Órfãs de navegação** (§8.1) — mas são dos Agentes de IA: fora do meu escopo propor o que fazer |
| Store/API de assistentes | `store/captain/{assistant,document,response,scenarios,inboxes,tools,customTools,assistantLogs,bulkActions}.js` | Compartilhado só na leitura |

### 4.3 [COMPARTILHADO] — cuidado redobrado

| Item | Por quê |
|---|---|
| `store/captain/assistant.js` (`captainAssistants/get`) | O copiloto carrega a lista de assistentes para escolher um (`CopilotContainer.vue:320`) |
| `store/captain/preferences.js` + `api/captain/preferences.js` | Estado da conexão LLM — usado pela guarda de API key do copiloto (`CopilotContainer.vue:170`) e pela config dos agentes |
| `FEATURE_FLAGS.CAPTAIN_V2` | **Mesmo gate** para copiloto e telas de agentes (`CopilotLauncher.vue:44`, `CopilotContainer.vue:66`, `captain.routes.js:23`, `agents.routes.js:29`). Não dá para ligar um sem o outro |
| `composables/captain/constants.js` | Tipos de erro e timeout usados pelos dois |
| i18n `CAPTAIN.*` | Namespace único |

---

## 5. Fluxo do agente — pontos de contato com o copiloto

Verificado em tela (`/accounts/3/conversations/681`, usuário de teste).

| # | Ponto | Onde | Cliques | Classe |
|---|---|---|---|---|
| 1 | **Ghost suggestion** (texto fantasma + **Tab**) | `ReplyBox.vue:2943-2956` | **0 + Tab** | C3 |
| 2 | **Botão ✨ "Copilot"** no composer | `ReplyBox.vue` / `CopilotMenuBar.vue` | **1** abre | C4 |
| 3 | └ *Sobre a conversa*: Analisar tom · Resumir | `CopilotMenuBar.vue:60-92` | 2 | C4 |
| 4 | └ *Polir*: Melhorar · Ortografia · Formal · Amigável · Informal · Firme · Direto · Encurtar · Expandir | `CopilotMenuBar.vue:94+` | 2–3 | C4 |
| 5 | └ *Criar do zero*: **Sugerir uma resposta** | `CopilotMenuBar.vue:89` | 2 | C4 |
| 6 | └ **Perguntar ao Copilot** → abre o painel | `CopilotMenuBar.vue:268` → `useCopilotReply.js:157-163` | 2 | C1 |
| 7 | **Painel lateral** (chat) | `CopilotContainer.vue` | 2 + 1/pergunta | C1 |
| 8 | **Botão flutuante** | `CopilotLauncher.vue` | 1 | **escondido em conversa** |
| 9 | **Command bar Ctrl+K → AI Assist** | `useConversationHotKeys.js:459-476` | atalho + 2 | C4 |
| 10 | **Ctrl+J** | `AIAssistantPanel.vue:442-449` | 1 | C5 — só com flag |
| 11 | Sugestão de etiquetas | `conversation/LabelSuggestion.vue` | 0 | C4 (`label_suggestion`) |
| 12 | Card "Resumo da IA" na sidebar | `ConversationSummary.vue` via `ContactPanel.vue:178` | 0 | lê `custom_attributes` escrito pelo **agente de IA** → [AGENTES-IA] |
| 13 | Resumo da IA no banner do composer | `ReplyBoxBanner.vue:295-322` | 0 | idem |

**Custo de atrito:** usar a IA custa 0–2 cliques (bom). **Conversar** com a IA custa 2 cliques, fecha a
sidebar de contato (`useCopilotReply.js:158-161`) e não deixa histórico visível.

---

## 6. Respostas prontas — o que é aposentado e o que atravessa a fronteira

**Premissa (decisão do Walisson, não rediscutida):** o atalho `/` é aposentado; a IA escreve do zero; o
acervo atual vira base de conhecimento.

### 6.1 O que sai [COPILOTO/produto]

| Camada | Arquivo |
|---|---|
| Atalho `/` no composer | `WootWriter/Editor.vue:296` (`trigger: '/'`) → `conversation/CannedResponse.vue` |
| Bloqueio em nota privada | `Editor.vue:236-238` |
| Item no menu "+" | `ReplyBox.vue:3119-3124` → `components-next/canned-response/CannedResponseModal.vue` |
| "Salvar como resposta pronta" | `MessageContextMenu.vue:109-114, 272` |
| Tela de gestão | `settings/canned/{Index,AddCanned,EditCanned}.vue`, rota `canned_list` (`canned.routes.js:22-30`) |
| Store/API | `store/modules/cannedResponse.js` · `api/cannedResponse.js` |
| Uso no chat interno | `internalChat/components/redesign/ChatComposer.vue` ⚠️ **não esquecer** |

### 6.2 Volume [FATO — SELECT em homologação]

```
CannedResponse.count = 9   |  contas com canned = 2 de 4
  acct 5 "Realizare Imobiliária" = 8      acct 3 "Simplex Tecnologia" = 1
Captain::AssistantResponse.count = 77     (já 8,5× mais conteúdo curado no Captain)
```

⚠️ **[HIPÓTESE]** Isto é homologação. Sem SSH para outras VMs neste task, **não sei o volume em produção**
(.229, Tozi .109, Realizare, fábrica). Rodar `CannedResponse.group(:account_id).count` em cada VM antes
de remover a UI — não para rediscutir a decisão, e sim para dimensionar a migração e o comunicado.

### 6.3 O ponto de fronteira da migração [COMPARTILHADO — atenção]

O destino natural do acervo é `Captain::AssistantResponse`, que é **tabela dos Agentes de IA** e é
exatamente o que o RAG do copiloto consulta (`search_documentation_service.rb:16`,
`assistant.responses.approved`). Consequências:

1. Uma resposta pronta migrada e **aprovada** passa a ser conhecimento **também do agente que atende o
   cliente**, não só do copiloto. Um texto interno ("informar ao cliente que o financeiro liga
   segunda") vira material que o bot pode usar sozinho.
2. `AssistantResponse` é `question`/`answer`; `CannedResponse` é `short_code`/`content` (HTML). A
   migração exige gerar uma "pergunta" para cada texto — trabalho de curadoria, não de script.
3. Elas pertencem a **um assistente**. Com 8 assistentes na conta 3, é preciso decidir para qual vão.

**[HIPÓTESE] Alternativa que não cruza a fronteira:** criar um acervo próprio do copiloto
(`copilot_snippets`, ou um assistente dedicado "Copiloto" com `assistant_id` fixo nas threads). Custa
uma tabela/registro a mais e **isola completamente** o conhecimento do copiloto do conhecimento do bot
de atendimento. Dado que a regra é "não mexer nos agentes de IA", esta é a opção que respeita a regra —
recomendo levar a decisão ao Walisson antes da migração.

### 6.4 O que se perde ao aposentar (para dimensionar, não para rediscutir)

Determinismo (texto idêntico para termos jurídicos/dados bancários) · latência e custo zero · memória
muscular do `/atalho` · funciona sem chave de LLM configurada · curadoria auditável.
**[HIPÓTESE] Mitigação barata:** manter o gesto `/` como *entrada do copiloto* — digitar `/` abre
sugestões geradas pela IA no mesmo lugar onde hoje aparece a lista. Zero reaprendizado para o agente.

---

## 7. O estado do V2 (`components-next/ai-assistant/`) [COPILOTO]

### 7.1 O que já está pronto e vale preservar [FATO]

Dialog Headless UI com focus trap/Esc (`AIAssistantPanel.vue:490-496`) · slide-in 280ms + full-screen
<375px (linhas 526-561) · respeita `prefers-reduced-motion` · **Ctrl+J** (linhas 436-449) · quick prompts
em 2 seções (linhas 83-125) · markdown sanitizado com DOMPurify hardened (`composables/useMarkdown.js`) ·
typewriter cancelável com rAF (`composables/useTypewriter.js`) · **copiar / aplicar no composer /
regenerar / 👍👎 / cancelar** (`AIMessageBubble.vue:222-282`) · banner de erro com 5 tipos
(`AIErrorBanner.vue` + `useAIErrorState.js`) · edge cases incl. **janela WhatsApp 24h expirada**
(linhas 460-486) · smart banner proativo (`AISmartBanner.vue`) · tour guiado (`useAITour.js`) ·
**`sanitizePII` antes de enviar ao LLM** (`utils/sanitizePII.js`, chamado em `useCaptain.js:275,361`) ·
telemetria granular · abort ao trocar de conversa (linhas 398-410).

### 7.2 Os três defeitos que o impedem de ser ligado [FATO]

1. **i18n quebrado.** 83 chamadas pedem `CONVERSATION.AI_ASSISTANT_PANEL.*`; as strings estão na **raiz**
   do arquivo (`i18n/locale/pt_BR/conversation.json:931`, `en/conversation.json:939`). Na tela:
   `CONVERSATION.AI_ASSISTANT_PANEL.EMPTY.SUBTITLE` renderizado como texto. Correção mecânica.
2. **O campo de texto não é chat.** `sendPrompt()` (linhas 313-331) manda o que foi digitado como
   *rótulo* de uma ação fixa `reply_suggestion` — `useCaptain.js:414` ignora a pergunta. É promessa de
   conversa entregando ação fixa.
3. **Sem histórico.** `history = ref([])` local (linha 128), zerado ao trocar de conversa e perdido no
   reload. O V2 **não usa** `copilot_threads` (que já existem e já são por usuário).

E o "streaming" é typewriter sobre resposta completa (`AIMessageBubble.vue:51-55`) — efeito visual, não
streaming de rede. Nenhum controller Captain faz SSE/chunked. [FATO]

### 7.3 Flag e pegadinha operacional [FATO]

Resolução: `sessionStorage.chatspx_ai_panel_v2_session` → `localStorage.chatspx_ai_panel_v2` → flag de
servidor `ai_assistant_v2` → **OFF** (`useAIAssistantFlag.js:39-60`).
Nenhuma conta desta base tem a flag ligada. **`?aiv2=1` não funciona em navegação SPA** — o override é
aplicado no `mounted` do `Dashboard.vue:68` e o computed não reage a `sessionStorage`; **exige reload**.
Confirmei: só depois de `sessionStorage.setItem(...)` + `reload()` o painel montou.

⚠️ Ligar a flag muda **dois** comportamentos, não um: além do painel, as ações inline do composer passam
a renderizar chip de sugestão em vez de trocar o composer (`ReplyBox.vue:1917-1927`).

---

## 8. Fora de escopo / contexto (mapeado antes da correção de escopo)

Mantido porque é contexto útil, mas **não é alvo da reescrita**.

### 8.1 As telas de gestão do Captain estão órfãs de navegação [AGENTES-IA]

[FATO] O menu lateral aponta para `agents_dashboard` (`Sidebar.vue:566-572`). As 14 rotas
`captain_assistants_*` de `routes/dashboard/captain/` (2.884 linhas) continuam registradas
(`dashboard.routes.js:11`) e acessíveis por URL, mas **nada no app navega até elas** — grep de
`captain_assistants_*` fora do diretório só encontra o `AssistantSwitcher` (menu interno do próprio
bloco) e o órfão `CopilotEmptyState.vue:103`. Confirmado na tela: os links do sidebar são `/agents/...`.
Há também `Sidebar.vue:758-762` com o item "Settings Captain" comentado, e a rota
`routes/dashboard/settings/captain/` continua registrada (`settings.routes.js:30`).
**Duas cascas de UI sobre o mesmo store** (`captainAssistants/getRecords` em `AgentsDashboard.vue:29`).
Não proponho ação — é decisão do dono dos Agentes de IA.

### 8.2 Direção visual [contexto para o redesign do copiloto]

Duas linguagens coexistem: **skin WhatsApp** (`assets/scss/_wa-skin.scss`, 3.334 linhas, tokens `--wa-*`
com par claro/escuro, linhas 15-29) na tela de conversa — onde o copiloto vive; e **glass/aurora**
(`components-next/agents-ui/`, assinatura `rounded-2xl border-n-weak bg-n-solid-1/70 backdrop-blur-xl
backdrop-saturate-150`, `AiCard.vue:14`; `AiBackdrop.vue`) nas telas de Agentes IA.

Hoje cada painel escolheu sozinho: V1 é chapado com acento `n-brand` (`CopilotPanel.vue:138-142`); V2 usa
**roxo literal** `purple-600/300` (`AIAssistantPanel.vue:570, 795`) — **não é token de branding**, então
não acompanha a cor do cliente. Tokenizar antes de expor.

**Armadilha do `Icon.vue` — confirmada** (`components-next/icon/Icon.vue:46-57`): `renderIcon` devolve
`props.icon` **sem chamar** quando é função, e o template passa isso para `:is`. VNode funciona; função
que retorna VNode, não. Sempre `h(Comp, props)` direto. Bônus: o `Icon` troca `i-lucide-*` por
componente animado se existir `animated-icons/<Nome>Icon.vue` (linhas 8-44).

Regras do vault que continuam valendo: scrollbars pelo `_wa-skin.scss` global
(`BP - Scrollbars Branding ChatSPX.md`) · `rgb(var(--solid-2))`, nunca `var(--n-solid-2)` ·
classe `reset-base` em inputs custom (o V2 já usa, linha 787) · Playwright em light+dark obrigatório
antes de declarar fase pronta — *este relatório é o caso de uso: o V2 compila, tem 15 arquivos de spec
passando, e exibe chaves i18n cruas na tela* · bitmask de `feature_flags` no limite (66) → usar
`internal_attributes` para flag nova.

### 8.3 Lacunas vs. um chat de IA moderno

Melhor caso combinando C1+C5 (nenhum agente tem os dois hoje):

| Recurso | C1 (vivo) | C5 (desligado) | Evidência |
|---|---|---|---|
| Streaming token a token | ❌ | ⚠️ só visual | nenhum SSE no backend; `AIMessageBubble.vue:51-55` |
| Chat livre de verdade | ✅ | ❌ | `copilot_messages` aceita texto livre; `AIAssistantPanel.vue:328` força `reply_suggestion` |
| Histórico persistido e navegável | ⚠️ persiste, nunca lista | ❌ | store só chama `copilotThreads/create` (`CopilotContainer.vue:264`) |
| Regenerar | ❌ | ✅ | `AIMessageBubble.vue:242-254` |
| Editar a pergunta | ❌ | ❌ | — |
| Parar geração | ⚠️ só no cliente (job continua) | ✅ AbortController | `CopilotContainer.vue:140-142`; `AIAssistantPanel.vue:375-378` |
| Copiar | ✅ | ✅ | — |
| Aplicar no composer | ✅ | ✅ | `CopilotAssistantMessage.vue:52-59` |
| Citar fonte | ⚠️ só se `feature_citation` do assistente | ❌ na UI | `system_prompts_service.rb:91-100` |
| Anexar arquivo | ❌ | ❌ | `CopilotMenuBar.vue:29-34`: "IA atual só aceita texto" |
| Markdown / código | ⚠️ formatter genérico | ✅ | `useMarkdown.js` — nenhum tem highlight nem "copiar bloco" |
| Atalhos | ⚠️ Ctrl+K | ✅ Ctrl+J | — |
| Erros tipados | ⚠️ timeout genérico | ✅ 5 tipos | `AIErrorBanner.vue` |
| Feedback 👍👎 persistido | ❌ (`CopilotAssistantMessage.vue:74` = `TODO backend`) | ❌ (só telemetria) | — |
| Trocar assistente no chat | ✅ | ❌ | `ToggleCopilotAssistant.vue` |
| a11y (focus trap, reduced-motion) | ❌ | ✅ | `AIAssistantPanel.vue:490-561` |
| Renderiza em pt-BR | ✅ (hardcoded, sem i18n) | ❌ **quebrado** | `CopilotPanel.vue:147-151`; §7.2 |

---

## 9. Recomendação

### 9.1 Preservar

`components-next/ai-assistant/composables/` inteiro (markdown, typewriter, erros, sugestões, tour) ·
`utils/sanitizePII.js` · `useCaptain.js` como camada de transporte (timeout + `AbortSignal.any` +
classificação granular) · `CopilotToolCard.vue` e `CopilotThinkingGroup.vue` (já sabem desenhar tool call
e raciocínio) · o schema `copilot_threads`/`copilot_messages` · o gesto do **ghost suggestion** (Tab) ·
os pontos inline de 1 clique.

### 9.2 Reescrever

Transporte (POST síncrono → streaming; o `response_job` já publica por ActionCable, dá para evoluir para
chunks) · o rodapé do V2 (§7.2 item 2) · o painel V1 e os 7 componentes órfãos · **a lista de tools**
(§9.4) · o endpoint morto `copilot_chat` (remover ou reativar conscientemente).

### 9.3 Ordem sugerida — resultado visível cedo

| Passo | O que | Prazo | Cruza a fronteira? |
|---|---|---|---|
| **0** | Corrigir o i18n (mover `AI_ASSISTANT_PANEL` para dentro de `CONVERSATION` nos 2 locales) e validar com Playwright em light+dark | ~30 min | Não |
| **1** | **Tirar as 12 tools de escrita do copiloto** (allowlist só-leitura) — garante "sugere, humano aprova" antes de qualquer outra coisa | 1–2 dias | **Sim — mas é o passo que PROTEGE** |
| **2** | Painel vira chat de verdade: rodapé manda a pergunta real; história em `copilot_threads` | ~1 semana | Não |
| **3** | Streaming real via ActionCable; typewriter vira fallback de reduced-motion | 1–2 semanas | Não |
| **4** | Lista de conversas com a IA (as threads já estão no banco desde sempre) | poucos dias | Não |
| **5** | Motor único servindo painel-na-conversa (fase 1) e tela própria (fase 2) | — | Não |
| **6** | Aposentar Respostas Prontas + migrar acervo | — | **Sim** — decidir antes: `captain_assistant_responses` (mexe nos Agentes de IA) vs. acervo próprio do copiloto (§6.3) |

Colocar o passo 1 antes do 2 é deliberado: enquanto `send_message` estiver ativa, **melhorar o chat
aumenta a chance de o copiloto falar com o cliente**.

### 9.4 Regras de segurança para a reescrita

1. **Allowlist de tools, nunca denylist** — custom tools da conta entram automaticamente
   (`chat_service.rb:102-107`).
2. **Não migrar as tools do copiloto para `BasePublicTool`** — o `TraceRecorder` passaria a gravar em
   `captain_tool_calls`, poluindo o eval dos Agentes de IA (conta 3 já tem `eval_enabled=true`).
3. **Preservar `copilot_threads.assistant_id`** — é `belongs_to` obrigatório; toda thread depende dele.
4. **Não escrever em `captain_assistant_responses`/`captain_documents`** sem decisão explícita (§6.3).
5. **Contador de cota compartilhado** — se o uso do copiloto crescer, revisar `increment_response_usage`
   (`chat_service.rb:31`) para não consumir a cota do atendimento.
6. **Flag `CAPTAIN_V2` é a mesma para os dois lados** — não dá para ligar copiloto sem ligar as telas de
   agentes. Se precisar de rollout separado, criar sinal próprio via `internal_attributes` (bitmask cheio).

---

## Anexos

**Evidências de tela** (fora do repo, em
`/tmp/claude-1001/-home-chatwoot-chatwoot/1b6fb63c-f6b3-4b74-8609-7a41f5ab2e53/scratchpad/`):
`20-conversa.png` · `30-menu-copilot.png` (menu ✨: Polir / Mudar o tom / Mudar o tamanho / Criar do zero
/ Perguntar ao Copilot) · `31-v2.png` (painel V2 com chaves i18n cruas).

**Consultas executadas** (somente `SELECT`, nesta VM de homologação):
`CannedResponse.count/group(:account_id)` · `Captain::{Assistant,Document,AssistantResponse,Scenario,CustomTool}.count` ·
`CopilotThread/CopilotMessage.count/group` · `CopilotThread.where(assistant_id: nil).count` ·
`Account#feature_enabled?`, `captain_models`, `captain_features`, `custom_attributes['eval_enabled']`.

**Não verificado / fora de alcance neste task:** volume de respostas prontas nas VMs de produção
(sem SSH) · qualidade das respostas do modelo · o pipeline de contexto do agente que atende (P1/P3).
