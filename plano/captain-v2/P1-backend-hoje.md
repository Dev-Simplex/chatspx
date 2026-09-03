# P1 — O Captain hoje, por dentro (backend)

> **Escopo:** pesquisa read-only no repo `/home/chatwoot/chatwoot`, branch `homologacao`
> (HEAD `ee87f5e799`), com leitura do banco de homologação (`SELECT` apenas) e do GlitchTip da frota.
> **Data:** 2026-07-28. **Nenhum código de aplicação foi alterado.**
>
> **CORREÇÃO DE ESCOPO (aplicada em 28/07, após o levantamento inicial):**
> "Captain", para o Walisson, é o **chat de copiloto que o agente humano usa** — não os
> **Agentes de IA** (assistentes) que atendem o cliente. Este documento foi reorganizado:
>
> - **Parte I — O COPILOTO E A FRONTEIRA** → o alvo da reescrita + todas as dependências
>   compartilhadas com os agentes de IA. **É a parte que importa.**
> - **Parte II — CONTEXTO: os agentes de IA** → o levantamento original, preservado como
>   contexto de **zona proibida**. Nada ali é proposta de mudança.
>
> **Classificação usada em todo o documento:**
> **[COPILOTO]** alvo da reescrita · **[AGENTES-IA]** não tocar · **[COMPARTILHADO]** cuidado redobrado.
>
> **Convenção de confiança:**
> - **[F]** FATO VERIFICADO — li o código / rodei o SELECT / rodei o grep. Tem caminho:linha ou query.
> - **[H]** HIPÓTESE — inferência plausível que eu **não** consegui provar aqui.

---
---

# PARTE I — O COPILOTO E A FRONTEIRA

## I.0 Resposta curta às 4 perguntas do coordenador

**1. O copiloto usa o assistente para quê?**
Para **quatro** coisas, e só no caminho upstream: **persona** (`product_name` + `config` no system
prompt), **conhecimento** (a FAQ *daquele assistente* — `assistant.responses.approved.search`),
**tenancy** (`assistant.account` resolve conta, chave e permissões) e **cota**. **Não** usa o
`assistant.config['tools']`, **não** usa o `assistant.liquid`, **não** usa `knowledge_mode`/chunks,
**não** usa cenários, **não** usa `behavior`. O vínculo é mais raso do que o `belongs_to` sugere.

**2. Dá para trocar interface e motor mantendo o vínculo?**
**Sim, e o vínculo é barato de manter** — são 4 pontos de leitura, todos isoláveis atrás de uma
interface. **Onde dói:** na **cota compartilhada** (§I.3-D) e na **chave de API** (§I.3-C), que não
são leitura — são efeito colateral em produção.

**3. O copiloto escreve em tabela dos agentes de IA?**
**Sim, em uma — e é a mais perigosa possível.** `Captain::Copilot::ChatService:31` chama
`account.increment_response_usage`, que grava em `accounts.custom_attributes['captain_responses_usage']`
— **o mesmo contador que decide se o agente de IA pode responder ao cliente**. Não escreve em
`captain_assistant_logs` (fora do trigger dormente), nem em `captain_tool_calls`, nem em
`captain_documents`. Detalhe completo em §I.3-D.

**4. Há dois caminhos de copiloto?**
**Há TRÊS.** Não dois. Detalhe em §I.2. E o terceiro (`AIAssistantPanel`) está desligado por flag
em todas as contas, mas com override por localStorage — ou seja, alguém já está testando.

---

## I.1 O achado que muda o plano

`app/services/copilot/` **não tem nada a ver** com `enterprise/app/services/captain/copilot/`.
São dois sistemas com o mesmo nome, escritos por pessoas diferentes, em épocas diferentes,
com **stacks completamente distintas** [F]:

| | Copiloto SPX (nosso) | Copiloto upstream (Chatwoot) |
|---|---|---|
| Serviço | `app/services/copilot/chat_service.rb` | `enterprise/app/services/captain/copilot/chat_service.rb` |
| Cliente LLM | `OpenAI::Client` **direto** (gem `ruby-openai`) | `RubyLLM` via `Llm::BaseAiService` |
| Chave | `account.settings['openai_api_key']` → `ENV['OPENAI_API_KEY']` | `InstallationConfig CAPTAIN_OPEN_AI_API_KEY` (via hook da conta) |
| Modelo | `account.settings['openai_model_default']` → `gpt-4o-mini` | `config/llm.yml` feature `copilot` → `gpt-5-mini` |
| Prompt | heredoc Ruby, em português, hardcoded | `SystemPromptsService.copilot_response_generator` |
| Tools | **nenhuma** | **32** |
| Vínculo com `Captain::Assistant` | **ZERO** | `belongs_to` obrigatório |
| Persistência | `conversations.additional_attributes['copilot_history']` | tabelas `copilot_threads`/`copilot_messages` |
| Cota Captain | **não consome** | **consome** |
| Telemetria de custo | **tokens + custo em USD** (`OpenaiSettings.log_chat_usage`) | só OTel/Langfuse, se habilitado |

**Consequência direta:** já existe, no repo, um copiloto **sem nenhuma dependência dos agentes de IA**.
Ele é rústico (sem tools, sem RAG, prompt fixo, histórico em jsonb), mas é a **prova de que o copiloto
pode viver desacoplado** — e é o melhor candidato a esqueleto do v2, porque começar por ele significa
**zero risco de contaminar o atendimento ao cliente**.

---

## I.2 São TRÊS caminhos, não dois

### Caminho A — Copiloto SPX inline **[COPILOTO]**

```
ReplyBox.vue (ghost) ──POST /conversations/:id/ghost_suggestion──► GhostSuggestionsController
CopilotPanel.vue     ──POST/GET/DELETE /conversations/:id/copilot_chat──► CopilotChatsController
                                    │
                        Copilot::LanguageDetectorService  (detecta idioma, cache 1h)
                                    │
                        Copilot::ChatService  |  Copilot::GhostSuggestionService
                                    │
                        OpenAI::Client (direto)  ─── gpt-4o-mini
                                    │
                        Copilot::OpenaiSettings.log_chat_usage  → tokens + custo USD no log
```
- Rotas: `config/routes.rb:241` (`ghost_suggestion`), `:242` (`copilot_chat`) [F]
- Controllers: `app/controllers/api/v1/accounts/conversations/{copilot_chats,ghost_suggestions}_controller.rb`
- Histórico: `conversation.additional_attributes['copilot_history']`, cap de 50 turnos
  [F: `copilot_chats_controller.rb:2,49`]
- **Estado de uso [F]:** `0` conversas com `copilot_history` não-vazio nesta base. O
  `CopilotPanel.vue` **foi removido do `ConversationBox.vue`** — o comentário na linha 4 diz
  *"CopilotPanel.vue removido — CopilotContainer (Dashboard.vue) já renderiza"*.
  **O ghost suggestion continua vivo** e ligado no `ReplyBox.vue:2316-2329`.
- **Leitura:** o painel de chat do caminho A está **desmontado**; sobrou o autocomplete fantasma.

### Caminho B — Copiloto upstream com threads **[COMPARTILHADO — é aqui que mora a fronteira]**

```
CopilotContainer.vue (Dashboard.vue, ramo v-else)
    │  store: captain/copilotThreads.js + copilotMessages.js
    ▼
POST /captain/copilot_threads   (cria thread + 1ª msg)     ← routes.rb:77
POST /captain/copilot_threads/:id/copilot_messages          ← routes.rb:78
    │  ensure_captain_api_key!  ← gate: exige a chave dos AGENTES DE IA
    │  usage_limits[:captain][:responses]  ← gate: cota dos AGENTES DE IA
    ▼
CopilotMessage#enqueue_response_job → Captain::Copilot::ResponseJob (queue :high, timeout 30s)
    ▼
Captain::Copilot::ChatService.new(assistant, ...)      ◄══ RECEBE UM Captain::Assistant
    ├─ system_prompt ← SystemPromptsService.copilot_response_generator(assistant.config['product_name'], …)
    ├─ tools ← 32 nativas + captain_custom_tools da conta
    ├─ RAG  ← SearchDocumentationService → assistant.responses.approved.search  (FAQ DO ASSISTENTE)
    ├─ modelo ← feature 'copilot' → account.captain_copilot_model (gpt-4.1 na conta 3)
    ▼ RubyLLM (Captain::ChatHelper#request_chat_completion)
    ├─ persist_message → copilot_messages
    └─ @account.increment_response_usage   ◄══ ESCREVE NA COTA DOS AGENTES DE IA
```
- **Estado de uso [F]:** 5 threads, 12 mensagens, **todas do mesmo usuário (id 1) e do mesmo
  assistente (id 3, Clara)**, última em **2026-05-04** — quase 3 meses parado.

### Caminho C — AI Assistant Panel v2 **[COPILOTO]**

```
AIAssistantPanel.vue  (components-next/ai-assistant/)
    │  flag: useAIAssistantFlag → feature 'ai_assistant_v2' (bit 39)
    │        + override localStorage 'chatspx_ai_panel_v2' / ?aiv2=1
    ▼  composable useCaptain → TasksAPI
POST /captain/tasks/{rewrite,summarize,reply_suggestion,label_suggestion,follow_up,sentiment_analysis}
    ▼
app/controllers/api/v1/accounts/captain/tasks_controller.rb
    ▼
lib/captain/{rewrite,summary,reply_suggestion,label_suggestion,follow_up,sentiment_analysis}_service.rb
    ├─ Captain::PiiSanitizer  (sanitiza PII antes de subir ao provider)
    └─ Enterprise::Captain::BaseTaskService → increment_response_usage  ◄══ COTA COMPARTILHADA
```
- **Não é um chat.** É um painel de **ações pontuais** (reescrever, resumir, sugerir resposta…),
  com histórico só no client. Não tem thread persistida, não tem tools, não tem assistente.
- **Estado [F]:** `ai_assistant_v2` está **OFF em todas as 4 contas** (decodifiquei o bitmask).
  Só aparece via override de storage — canary manual.
- Mutex garantido por spec: `AIAssistantPanel.mutex.spec.js` verifica que `CopilotContainer` só
  renderiza no ramo `v-else` [F].

### O que isso significa para a reescrita

> **[F]** Existem hoje **3 front-ends, 3 back-ends e 3 modelos de persistência** para a mesma ideia
> ("IA que ajuda o agente"), e **nenhum dos três está em uso relevante** nesta base (0 / 5 threads
> paradas em maio / desligado por flag).
>
> **Isso é uma boa notícia.** A decisão "um só motor de chat servindo copiloto-na-conversa e tela
> própria" não precisa migrar usuários nem preservar compatibilidade — precisa **escolher um dos três
> e matar os outros dois**. O custo aqui é de remoção, não de migração.
>
> **[H]** Em produção (Tozi/.229) o uso pode ser diferente. Não pude verificar — sem SSH. Antes de
> deletar qualquer um dos três, vale um `SELECT count(*) FROM copilot_threads` nas VMs de produção.

---

## I.3 A FRONTEIRA — dependências compartilhadas, uma a uma

Cada linha é um ponto onde mexer no copiloto **pode** afetar o atendimento ao cliente.
Ordenado por risco decrescente.

### A. `CopilotThread belongs_to Captain::Assistant` — **estrutural, risco BAIXO**

| Item | Valor |
|---|---|
| Onde | `enterprise/app/models/copilot_thread.rb:22` · `db/schema.rb` `copilot_threads.assistant_id` |
| Natureza | FK obrigatória (`belongs_to` sem `optional: true`) |
| Quem preenche | `copilot_threads_controller.rb:51` — `Current.account.captain_assistants.find(params[:assistant_id])`, **o front escolhe qual assistente** |
| Risco de contaminar produção | **BAIXO** — é leitura da FK; o copiloto não altera o assistente |
| Cuidado | `find` (não `find_by`) → **404 se o assistente for apagado**. E `dependent:` não está declarado do lado do assistente para `copilot_threads`, então **apagar um assistente com threads deixa FK órfã** ou estoura, dependendo da constraint. **[H]** — não testei o delete |

### B. A FAQ do assistente é o RAG do copiloto — **funcional, risco BAIXO-MÉDIO**

| Item | Valor |
|---|---|
| Onde | `enterprise/app/services/captain/tools/search_documentation_service.rb:16` |
| O quê | `assistant.responses.approved.search(query)` — busca vetorial na **`captain_assistant_responses` daquele assistente** |
| Também usa | `Captain::Llm::TranslateQueryService` (traduz a query para o idioma da conta antes de buscar) |
| Risco | **Leitura pura.** O copiloto não escreve na FAQ |
| **Implicação para a decisão de aposentar as respostas prontas** | O "acervo vira base de conhecimento" precisa de um destino. Hoje há **dois** acervos possíveis: `captain_assistant_responses` (FAQ, 77 registros, **é dos agentes de IA**) e `captain_document_chunks` (38 chunks, **também dos agentes**). **Escrever o acervo de canned responses em qualquer um dos dois é contaminar a zona proibida** — mudaria o que o agente de IA responde ao cliente. Recomendo acervo próprio do copiloto |

**Volume atual das respostas prontas [F]:** `canned_responses` = **9 registros** (1 na conta 3,
8 na conta 5). Nesta base o acervo é irrelevante; **[H]** em produção pode ser grande — verificar
antes de dimensionar a migração.

### C. Chave de API — **operacional, risco MÉDIO**

| Caminho | Chave usada | Compartilhada com agentes de IA? |
|---|---|---|
| A (SPX) | `account.settings['openai_api_key']` → `ENV['OPENAI_API_KEY']` [F: `openai_settings.rb:16-20`] | **NÃO** — chave própria |
| B (upstream) | `Captain::OpenaiHookService` → `InstallationConfig CAPTAIN_OPEN_AI_API_KEY` | **SIM** |
| C (tasks) | idem B, via `Captain::BaseTaskService#api_key` | **SIM** |

**[F]** Estado nesta base: só a conta 5 tem `settings.openai_api_key`; `ENV['OPENAI_API_KEY']` está
presente no `.env`. Ou seja, o caminho A funciona hoje com a **chave global do ambiente**.

**Risco concreto:** o gate `ensure_captain_api_key!`
[`app/controllers/concerns/captain/api_key_validation.rb:4`] bloqueia o **copiloto** quando a chave
**dos agentes de IA** não está configurada. Inversamente, estourar rate-limit da chave por uso do
copiloto degrada o atendimento ao cliente. **A chave é um recurso compartilhado sem isolamento.**
O eval já resolveu isso para si (`EVAL_OPEN_AI_API_KEY`) — o copiloto deveria fazer o mesmo.

### D. **COTA COMPARTILHADA — risco ALTO. O item mais importante desta seção.**

```
Captain::Copilot::ChatService:31        →  @account.increment_response_usage
Enterprise::Captain::BaseTaskService:30 →  account.increment_response_usage   (caminho C)
                                                    │
                                                    ▼
                        accounts.custom_attributes['captain_responses_usage'] += 1
                                                    │
                                                    ▼
  Enterprise::MessageTemplates::HookExecutionService:195  captain_quota_available?
                                                    │
                                        se zerou ──► perform_handoff
                                                    ├─ manda a mensagem de handoff ao cliente
                                                    ├─ SOLTA o espelho (assignee_agent_bot_id = nil)
                                                    └─ bot_handoff!
```

**[F]** Cada mensagem do copiloto (caminhos B e C) consome **uma unidade da mesma cota** que decide
se o agente de IA pode responder ao cliente. Não há segregação por finalidade.

**Cenário de falha real:** um agente humano usa o copiloto intensamente numa tarde; a cota mensal
da conta zera; **o atendimento automático ao cliente para** e todas as conversas caem em handoff.
O agente que usou o copiloto não tem como saber que causou isso.

**Isto não é hipotético em desenho** — é o comportamento atual do código. E é exatamente o tipo de
acoplamento que uma reescrita do copiloto **pode piorar sem perceber**: se o copiloto novo for mais
usado (que é o objetivo), ele consome mais cota, e o atendimento quebra antes.

> **Recomendação:** o primeiro PR da reescrita do copiloto deveria ser **separar o contador**
> (`captain_copilot_usage` distinto de `captain_responses_usage`), antes de qualquer mudança de UX.
> É uma mudança pequena, isolada, e remove o maior risco de a reescrita derrubar produção.

### E. Modelo de LLM por conta — **config, risco BAIXO**

`config/llm.yml` define a feature **`copilot`** (default `gpt-5-mini`) separada de **`assistant`**
(default `gpt-5-mini`), resolvidas por `account.captain_copilot_model` / `captain_assistant_model`
[F: `captain_featurable.rb:17`]. **Já são independentes.**
Estado [F]: conta 3 usa `{"copilot": "gpt-4.1", "assistant": "claude-sonnet-4.5"}`.
O caminho A ignora tudo isso e usa `gpt-4o-mini`.

### F. Tools do copiloto — **compartilham a base, não o catálogo — risco MÉDIO**

**[F]** As 32 tools do copiloto (`enterprise/app/services/captain/tools/copilot/`) são **exclusivas
do copiloto** — o agente de IA não as usa (o `agent_tools` do assistente monta outro conjunto,
`assistant.rb:132`). **Mas:**

- Elas herdam de `Captain::Tools::BaseTool`, enquanto as do agente herdam de
  `Captain::Tools::BasePublicTool`. Consequência **[F]**: o `TraceRecorder` é prependado só em
  `BasePublicTool` → **as tools do copiloto NÃO gravam em `captain_tool_calls`**. Zero telemetria.
- As **custom tools da conta são compartilhadas**: `chat_service.rb:102` carrega
  `@account.captain_custom_tools.enabled` (filtrando `copilot_only` só do lado do agente,
  `assistant.rb:68`). **Uma custom tool criada para o agente aparece no copiloto.**

### G. 🔴 **O copiloto atual PODE falar com o cliente — contradiz a premissa**

**[F]** `enterprise/app/services/captain/tools/copilot/send_message_service.rb:11-19`:

```ruby
def execute(conversation_id:, content:, private: false)     # ← private FALSE por padrão
  ...
  Messages::MessageBuilder.new(nil, conversation, params).perform
```

Isso cria uma **mensagem outgoing real, entregue ao cliente**, sem aprovação humana — basta o LLM
decidir chamar a tool. O único gate é `user_has_permission('conversation_manage')` (linha 22), que
a maioria dos agentes tem. Existe também `send_template_service.rb` (templates de WhatsApp).

Além dessas duas, **8 tools do copiloto escrevem em produção** [F: grep por `create!`/`update!`]:
`update_contact`, `snooze_conversation`, `change_status`, `change_priority`, `add_note_to_contact`,
`set_custom_attributes`, `transfer_to_inbox`, `resolve_conversation`.

> **A decisão do Walisson — "o copiloto NÃO fala com o cliente: sugere, o humano aprova" — NÃO é
> o comportamento atual.** É uma mudança de contrato. O copiloto v2 precisa de um princípio
> explícito: **toda tool é ou `read` ou `propose`; nenhuma é `commit`.** As 10 tools de escrita
> viram propostas que aparecem na UI para o humano confirmar.

### H. O que **NÃO** é compartilhado (bom saber — é onde se pode mexer à vontade)

**[F]**, verificado por leitura de código:

| Recurso dos agentes de IA | O copiloto usa? |
|---|---|
| `assistant.liquid` (prompt do agente) | **NÃO** — o copiloto tem prompt próprio (`SystemPromptsService`) |
| `Captain::Scenario` (cenários) | **NÃO** |
| `assistant.config['tools']` | **NÃO** — o catálogo do copiloto é fixo no `TOOL_CLASSES` |
| `assistant.behavior` (router, debounce, humanizer, dedup, business_hours) | **NÃO** |
| `knowledge_mode` / `captain_document_chunks` / `search_knowledge` | **NÃO** — o copiloto só busca a FAQ |
| `Captain::Assistant::AgentRunnerService` / gem `ai-agents` | **NÃO** — o copiloto usa o motor V1 |
| `AgentBot`-espelho / `assignee_agent_bot_id` / gate por atribuição | **NÃO** |
| `captain_assistant_logs` | **NÃO** escreve (o único ponto seria `copilot_trigger`, dormente — §II.2.7) |
| `captain_tool_calls` | **NÃO** escreve (ver F) |
| `captain_documents` / `captain_document_chunks` | **NÃO** escreve |
| `Captain::ConversationEval` / episódios | **NÃO** |
| `ResponseBuilderJob` e todo o pipeline de resposta ao cliente | **NÃO** |

**Leitura:** a fronteira real é **muito mais estreita** do que o `belongs_to` sugere. São
**4 pontos de contato** (persona, FAQ, chave, cota) — e só **dois deles são perigosos** (chave, cota).

---

## I.4 Recomendação para a reescrita do copiloto

### Ordem sugerida (do mais seguro para o mais arriscado)

1. **Separar a cota** (`captain_copilot_usage` ≠ `captain_responses_usage`). PR pequeno, isolado,
   remove o único risco ALTO de derrubar o atendimento. **Faça isto primeiro.**
2. **Separar a chave** — dar ao copiloto uma `COPILOT_OPEN_AI_API_KEY` própria, no padrão que o
   eval já usa. Remove o acoplamento de rate-limit e o gate cruzado `ensure_captain_api_key!`.
3. **Escolher UM dos três caminhos** e apagar os outros dois. Recomendo **partir do caminho B
   (threads)** como modelo de dados — `copilot_threads`/`copilot_messages` já tem thread, papéis,
   `assistant_thinking`, broadcast por ActionCable e `reply_suggestion` no schema da mensagem
   [F: `copilot_message.rb:112`] — e **trazer do caminho A** o desacoplamento
   (LLM próprio, sem `Captain::Assistant` obrigatório) e a **telemetria de custo em USD**, que é
   melhor do que qualquer coisa no lado dos agentes.
4. **Reclassificar as tools** em `read` / `propose`, e mover `send_message`/`send_template` para
   `propose`. Sem isso, a premissa "o humano aprova" não é verdadeira.
5. **Acervo próprio para o conhecimento do copiloto.** Não reaproveitar
   `captain_assistant_responses` nem `captain_document_chunks` — são dos agentes de IA. As canned
   responses aposentadas viram uma tabela do copiloto (ou um `documentable_type` próprio).
6. **Só então** mexer em UX/streaming.

### Sobre o vínculo com o assistente

**Manter ou cortar?** Recomendo **tornar opcional** (`belongs_to :assistant, optional: true`) em vez
de cortar: hoje ele carrega a persona (`product_name`) e a FAQ, e quem já tem thread perde contexto
se sumir. Mas o copiloto v2 deve funcionar **sem** assistente configurado — hoje não funciona
(`copilot_threads_controller.rb:51` faz `find`, e `ensure_captain_api_key!` exige a chave dos agentes).
Um cliente que não usa agentes de IA **não consegue usar o copiloto** — o que é um bug de produto,
não só de arquitetura.

### Sobre streaming (decisão "experiência ChatGPT")

**[F]** Nenhum dos três caminhos tem streaming. **Mas o copiloto é MUITO mais fácil de streamar que
o agente de IA**, porque não tem as 4 travas que o `ResponseBuilderJob` impõe (dedup, sanitização
para WhatsApp, humanizer, `wait_for_dispatch`). O copiloto escreve numa UI, não num canal.
O caminho B já tem `assistant_thinking` como tipo de mensagem e broadcast por ActionCable
[F: `copilot_message.rb:70,106`] — **a infraestrutura de streaming incremental já existe pela metade.**

### O que NÃO fazer

- ❌ Não escrever nas tabelas `captain_*` dos agentes de IA a partir do copiloto.
- ❌ Não reaproveitar `assistant.liquid` como prompt do copiloto (ele é do agente, e tem viés de
  imobiliária — §II.7.2b).
- ❌ Não usar a `Captain::Assistant` como container de configuração do copiloto — hoje ela já é um
  jsonb sem schema servindo a 15 chaves diferentes.
- ❌ Não apagar `copilot_threads` de produção sem antes contar o uso lá (§I.2, **[H]**).

---
---

# PARTE II — CONTEXTO: os agentes de IA **[ZONA PROIBIDA — não mexer]**

> Levantamento original, feito antes da correção de escopo. **Preservado como contexto**: descreve o
> sistema que atende o cliente e que **não deve ser alterado**. As recomendações da §II.8 estão
> **fora de escopo** — ficam registradas para um projeto futuro, não para este.
>
> O que aqui é útil para o projeto do copiloto: entender o que existe do outro lado da fronteira,
> para não colidir com ele.

## II.1 Resumo executivo **[AGENTES-IA]**

O Captain **não é um chatbot**. É um **motor de atendimento autônomo com identidade**, construído em cima de
um fork do Chatwoot, com ~11.6k linhas de Ruby [F: `find app/ lib/ enterprise/ -path "*captain*" -name "*.rb" | xargs wc -l` → 11.558]
e 308 linhas de prompt Liquid. A parte que **funciona de verdade** é surpreendentemente boa e sofisticada:
o modelo "IA-como-atendente" via **AgentBot-espelho** (gate de resposta por atribuição) é uma solução
elegante para o problema mais difícil desse domínio — *quem é o dono da conversa agora*. Isso deve ser
**preservado**, não reescrito.

O que está podre é outra coisa: **a camada de geração**. Concretamente:

1. **Existem dois motores de LLM coexistindo** — o V2 (gem `ai-agents`, com tools e handoffs) e o V1
   (`Captain::Llm::AssistantChatService`, chat completion manual). O V1 está *aparentemente* morto, mas
   **as ações de IA das Automações (Flows) chamam o V1 direto, sem checar a flag** — ou seja, o motor
   legado está vivo por uma porta lateral [F: `app/services/flows/ai_actions.rb:85`].

2. **O prompt de sistema é um arquivo global no disco, com regras hardcoded de imobiliária de Sinop-MT.**
   Todo cliente do ChatSPX, de qualquer vertical, recebe "horário de Sinop/MT" e "dúvida sobre um imóvel"
   no system prompt [F: `enterprise/lib/captain/prompts/assistant.liquid:17,26`]. Isso é multi-tenancy
   quebrada no lugar mais caro possível.

3. **O mecanismo de cenários (multi-agente/handoff entre personas) está 100% desligado.** Todos os 11
   cenários da base estão `enabled = false` [F: `SELECT ... FROM captain_scenarios` → 11 linhas, todas `f`].
   O `assistant.liquid` gasta seu "Decision Framework" inteiro instruindo o LLM a usar `handoff_to_*`
   para cenários que não existem em runtime. A multi-persona real migrou para outra coisa
   (`transferir_para_agente`, assistant→assistant).

4. **Há config que o usuário liga na tela e que não faz absolutamente nada.** 6 dos 8 assistants têm
   `behavior.media_pipeline = {image_description: true, audio_transcription: true}` gravado no banco
   [F: SELECT], e o serviço que leria essa config, `Captain::Behavior::MediaPipelineService`, **não tem
   um único caller** [F: grep 0 refs]. A transcrição real acontece por outro caminho
   (`Messages::AudioTranscriptionJob`).

5. **Não há streaming, não há controle de custo por token, e o cache de prompt é opt-in escondido.**
   A cota é contada em "respostas", não em tokens [F: `plan_usage_and_limits.rb:18-22`]. O único lugar
   que vê tokens é o exporter de OpenTelemetry/Langfuse, e só se `otel_enabled?`.

6. **Não há fallback de provider.** Chave OpenAI inválida = erro cru e conversa parada. Isso não é
   teórico: 21 ocorrências de `RubyLLM::UnauthorizedError` no GlitchTip do projeto `producao`,
   a última hoje (28/07 13:10) [F: GlitchTip].

**Veredito para a reescrita:** o que preservar é a **camada de orquestração de conversa** (espelho,
gate por atribuição, kick, debounce, humanizer, handoff, auto-closure). O que jogar fora é a
**camada de geração** (dois motores, prompt em disco, cenários, response_schema anêmico) e a
**camada de instrumentação de qualidade** (eval), que é boa em intenção mas está construída como
batch cron desacoplado em vez de fazer parte do loop.

---

## II.2. Inventário

### II.2.1 Núcleo do fluxo de resposta — **VIVO**

| Peça | Caminho | O que faz | Quem chama | Estado |
|---|---|---|---|---|
| Hook de entrada | `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb` (241 ln) | Ponto de entrada de TODA mensagem. Gate por atribuição, router, business hours, debounce, quota, reentrada órfã (D-12) | `MessageTemplates::HookExecutionService` (core, no `message_created`) | **VIVO** — o coração |
| Router | `.../captain/behavior/router_service.rb` (56 ln) | Só 3 guards técnicos: activity, conteúdo vazio, grupos WhatsApp | `hook_execution_service.rb:53` | **VIVO** |
| Debounce | `.../captain/behavior/debounce_service.rb` (36 ln) | Agrupa rajada do cliente via token Redis + job atrasado | `hook_execution_service.rb:83` | **VIVO** (todos os assistants com `debounce_seconds` 5–15) |
| Job debounced | `enterprise/app/jobs/captain/conversation/debounced_response_job.rb` | Valida token, re-checa dono, loga `debounce_fire` | `DebounceService#schedule` | **VIVO** — 205 eventos no log |
| **Job de resposta** | `enterprise/app/jobs/captain/conversation/response_builder_job.rb` (**513 ln**) | Monta histórico, chama motor, dedup, sanitiza, humaniza, envia, agenda follow-up | 4 callers | **VIVO** — a peça mais crítica e mais inchada |
| Runner V2 | `.../captain/assistant/agent_runner_service.rb` (304 ln) | Envelopa a gem `ai-agents`: contexto, state, handoffs, instrumentação OTel | `response_builder_job.rb:44,311`; playground; `spx/ai_config` | **VIVO** — motor real |
| Kick pós-atribuição | `enterprise/app/jobs/captain/conversation/assignment_kick_job.rb` | Re-executa o hook quando o espelho é atribuído (triagem assíncrona / transferência IA→IA) | `enterprise/app/models/enterprise/concerns/conversation.rb:86` | **VIVO** |
| Espelho | `.../captain/assistant_mirror_service.rb` | Cria/atualiza o `AgentBot` bot_type `captain` 1:1 com o assistant | `after_commit`/`after_touch` do Assistant | **VIVO** — 8 espelhos no banco |
| Humanizer | `.../captain/behavior/humanizer_service.rb` | Quebra a resposta em bolhas de WhatsApp | `response_builder_job.rb:380` | **VIVO** — 109 `humanizer_split` |
| Dedup | `.../captain/behavior/dedup_service.rb` | Hash MD5 + Redis TTL, anti-repetição | `response_builder_job.rb:326` | **VIVO** (1 `dedup_skip`) |
| Business hours | `.../captain/behavior/business_hours_checker.rb` | Dentro/fora do expediente | hook + `agentable.rb:60` | **VIVO** |
| Handoff p/ humano | `.../captain/conversation/human_handoff_service.rb` | Fila por time + `aguardando_humano_desde` + distribuição | `HandoffTool`, `FollowupJob` | **VIVO** |
| Follow-up | `enterprise/app/jobs/captain/conversation/followup_job.rb` (98 ln) | Cutucada com token, quiet hours, escala p/ humano ao esgotar | `ProgramarFollowupTool` + auto-agendamento | **VIVO** |
| Retriage manual | `.../captain/retriage_service.rb` | "Devolver para a IA" (endpoint + job de órfãs) | `conversations_controller.rb:120` | **VIVO** |
| Auto-resolve / encerramento | `enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb` (311 ln) | Classifica conversa parada e resolve/enfileira/avisa | cron `Account::ConversationsResolutionSchedulerJob` | **VIVO** (`auto_closure.enabled=true` na conta 3) |
| Fila de encerramento | `.../captain/conversation/pending_closure_service.rb` | Marca `aguardando_encerramento_desde` | job acima, linha 109 | **VIVO** |
| Concern de conversa | `enterprise/app/models/enterprise/concerns/conversation.rb` (148 ln) | Solta espelho no resolve, kick na atribuição, auditoria, limpa marcadores | callbacks do model | **VIVO** |
| Listener | `enterprise/app/listeners/captain_listener.rb` (22 ln) | Só no `conversation_resolved`: gera notas de contato + FAQ | event dispatcher | **VIVO** (condicional a `feature_memory`/`feature_faq`) |

### II.2.2 Conhecimento / RAG — **VIVO (parcialmente exercitado)**

| Peça | Caminho | Estado |
|---|---|---|
| `Captain::Document` | `enterprise/app/models/captain/document.rb` (183 ln) | **VIVO** — 2 documentos na base |
| `Captain::DocumentChunk` + busca híbrida RRF | `.../captain/document_chunk.rb` (109 ln) | **VIVO** — 38 chunks; `hybrid_search` = vetorial (HNSW cosine) + full-text (GIN tsvector) fundidos por Reciprocal Rank Fusion |
| `Captain::AssistantResponse` (FAQ) | `.../captain/assistant_response.rb` | **VIVO** — 77 registros; busca vetorial ivfflat |
| `SearchKnowledgeTool` | `enterprise/app/services/captain/tools/search_knowledge_tool.rb` | **VIVO** — injetada automaticamente quando `knowledge_mode` ∈ {chunks, hybrid}. *Grep de referência direta dá 0 — a resolução é dinâmica via `resolve_tool_class('search_knowledge')` em `captain_tools_helpers.rb:25`. Cuidado: grep ingênuo classificaria como morta.* |
| `FaqLookupTool` | `enterprise/lib/captain/tools/faq_lookup_tool.rb` | **VIVO** — sempre injetada (`assistant.rb:134`) |
| Chunking / embedding / contextual retrieval | `.../captain/llm/document_chunking_service.rb`, `embedding_service.rb`, `contextual_chunk_service.rb` | **VIVO** |
| Crawl (Firecrawl + fallback simples) | `.../captain/tools/firecrawl_service.rb`, `simple_page_crawl_service.rb` | **VIVO** |
| PDF | `.../captain/llm/pdf_processing_service.rb` | **VIVO** |

### II.2.3 Avaliação (Eval 2.0) — **VIVO mas em modo LEGADO**

| Peça | Caminho | Estado |
|---|---|---|
| Juiz LLM | `enterprise/lib/captain/conversation_eval_service.rb` (221 ln) | **VIVO** — 6 vereditos gravados, últimos em 24/07 |
| Schema do veredito | `enterprise/lib/captain/conversation_eval_schema.rb` (42 ln) | **VIVO** — 16 categorias de falha |
| Gate determinístico | `enterprise/lib/captain/episode_gate_service.rb` (91 ln) | **DORMENTE** — só é chamado por `EpisodeEvalJob`, que só roda em modo `eval_unit=episode`. `custom_attributes.eval_unit` é **NULL** na conta 3 → modo legado. **Nunca executou aqui.** |
| Segmentador de episódios | `enterprise/lib/captain/episode_segmenter_service.rb` (176 ln) | **DORMENTE aqui / VIVO E QUEBRANDO na Tozi PROD** — ver §7.1 |
| Cron do eval | `enterprise/app/jobs/captain/conversation_eval_scheduler_job.rb` | **VIVO** — `cron: '7 * * * *'` em `config/schedule.yml:140` |
| Trace de tools | `enterprise/lib/captain/tools/trace_recorder.rb` | **VIVO mas raso** — só grava se `eval_enabled`; 4 registros na base |

### II.2.4 Copilot (IA para o agente humano) — **VIVO, sistema paralelo**

`Captain::Copilot::ChatService` [`enterprise/app/services/captain/copilot/chat_service.rb`] roda no motor
**V1** (chat completion manual) com **32 tools** próprias em `enterprise/app/services/captain/tools/copilot/`
(31 arquivos + `SearchDocumentationService`) [F: `TOOL_CLASSES` em `chat_service.rb:63-96`].
Todas herdam de `Captain::Tools::BaseTool` [F: grep → 31/31].
**Volume real:** 5 threads, 12 mensagens, última em 2026-05-04 → praticamente **abandonado em uso**,
mas é código vivo com 32 tools de manutenção.

### II.2.5 Tarefas clássicas do Captain — **VIVAS**

`lib/captain/{rewrite,summary,reply_suggestion,label_suggestion,sentiment_analysis,follow_up}_service.rb`,
todas expostas em `app/controllers/api/v1/accounts/captain/tasks_controller.rb`.
Gate de cota via `enterprise/lib/enterprise/captain/base_task_service.rb`.
`Captain::PiiSanitizer` [`lib/captain/pii_sanitizer.rb`] sanitiza PII antes de subir ao provider —
usado por summary, sentiment e follow_up **[F]**, mas **não** pelo caminho de conversa (o
`ResponseBuilderJob` manda o histórico cru).

### II.2.6 **MORTO** — prova por grep

| Peça | Caminho | Prova |
|---|---|---|
| `Captain::ToolRegistryService` | `enterprise/app/services/captain/tool_registry_service.rb` | 0 refs em `app/ lib/ enterprise/ config/`; única referência é `spec/enterprise/services/captain/tool_registry_service_spec.rb` |
| `Captain::Tools::BaseService` | `enterprise/app/services/captain/tools/base_service.rb` | 0 subclasses (todas as 31 copilot tools herdam de `BaseTool`); só é consumido pelo `ToolRegistryService`, que também é morto |
| `Captain::Onboarding::WebsiteAnalyzerService` | `enterprise/app/services/captain/onboarding/website_analyzer_service.rb` | 0 refs; só `spec/enterprise/services/captain/onboarding/website_analyzer_service_spec.rb` |
| `Captain::Llm::ContactAttributesService` | `enterprise/app/services/captain/llm/contact_attributes_service.rb` | **0 refs em qualquer lugar do repo** — nem spec |
| `Captain::Behavior::MediaPipelineService` | `enterprise/app/services/captain/behavior/media_pipeline_service.rb` | 0 callers. **Agravante:** 6 assistants têm `behavior.media_pipeline` gravado no banco — config viva apontando para código morto |

### II.2.7 **DORMENTE** — código vivo, ninguém liga

| Peça | Por quê |
|---|---|
| `Captain::Llm::AssistantChatService` (motor V1 no fluxo de conversa) | Só roda se `captain_integration_v2` estiver **off**. Bit 47 do bitmask está **on** na única conta com IA (conta 3) [F: decodifiquei `feature_flags = 7278217375621054423`]. **MAS** — ver §7.2, o V1 está vivo por outra porta |
| **Todos os 11 cenários** (`Captain::Scenario`) | `enabled = false` em 100% deles [F: SELECT]. `assistant.rb:177` só passa `scenarios.enabled` pro prompt, e `agent_runner_service.rb:218` só registra handoff dos enabled → **o Decision Framework do prompt referencia agentes inexistentes** |
| `Captain::Behavior::CopilotTriggerService` | Requer `behavior.copilot_trigger.enabled`; nenhum assistant tem a chave [F: `SELECT DISTINCT jsonb_object_keys(behavior)` → business_hours, debounce_seconds, dedup, humanizer, media_pipeline, router] |
| `Captain::EpisodeGateService` + `EpisodeEvalJob` | Requerem `eval_unit = 'episode'`; é NULL [F] |
| 6 tools built-in | `add_contact_note`, `add_private_note`, `update_priority`, `add_label_to_conversation`, `resolve_conversation`, `buscar_empreendimento` — não aparecem em nenhum `config.tools` de assistant nem em `scenarios.tools` [F: SELECT DISTINCT] |
| `Captain::ConversationCompletionService` | Vivo, mas só através do auto-resolve avaliado |

---

## II.3. O fluxo de uma resposta — ponta a ponta

### II.3.1 Diagrama textual

```
 CLIENTE manda mensagem no WhatsApp
        │
        ▼
 Message#after_create → MessageTemplates::HookExecutionService#perform
        │
        ▼
 Enterprise::MessageTemplates::HookExecutionService#trigger_templates   ← hook_execution_service.rb:4
        │
        ├─◆ orphan_captain_reentry?  (open + sem dono humano + sem espelho + tem triagem
        │   e a conta NÃO está em modo fila)                            ← :157
        │   └──► reattach_triage_assistant → seta espelho da triagem → RETORNA
        │        (a atribuição dispara o AssignmentKickJob e o fluxo recomeça)
        │
        ├─◆ should_process_captain_response?                            ← :139
        │   (status ∈ {pending, open}) ∧ incoming ∧ assignee_agent_bot é espelho captain
        │   └── FALSO ──► EARLY RETURN (silêncio total)
        │
        ├─◆ captain_quota_available?  (usage_limits[:captain][:responses]) ← :195
        │   └── FALSO ──► perform_handoff: bolha de handoff + solta espelho + bot_handoff!
        │
        ▼
 process_captain_behavior(assistant)                                     ← :38
        │
        ├─◆ message.private? ──► CopilotTriggerService (DORMENTE) e RETORNA
        │
        ├─◆ RouterService#should_respond?                                ← router_service.rb:18
        │   ├── activity?            ──► false
        │   ├── content e anexos vazios ──► false
        │   └── grupo WhatsApp (default SEGURO = não responde) ──► false
        │   └── FALSO ──► AssistantLog('router_skip') e EARLY RETURN
        │
        ├──► ensure_conversation_open  (pending → open, autoria = a IA)  ← :65
        │
        ├─◆ outside_hours_ignore?  (fora do horário ∧ action == 'ignore') ← :56
        │   └── VERDADEIRO ──► AssistantLog('business_hours_skip') e EARLY RETURN
        │
        ├──► mark_customer_message_read  (tique azul, best-effort WhatsApp Cloud)
        │
        ▼
 schedule_or_debounce                                                    ← :79
        │
        ├── debounce_seconds > 0 ──► DebounceService#schedule
        │        │  Redis SET token (TTL = debounce + 30s)
        │        └─ DebouncedResponseJob.set(wait: N).perform_later
        │              │
        │              ├─◆ stored_token == token?  (não: rajada nova venceu → morre)
        │              ├─◆ dono ainda é este assistant? (não: morre)
        │              ├──► AssistantLog('debounce_fire')
        │              └──► ResponseBuilderJob.perform_now
        │
        └── senão ──► ResponseBuilderJob.perform_later (+ wait 1–5s se tem anexo)
        │
        ▼
╔═══════════════════════════════════════════════════════════════════════════════╗
║ Captain::Conversation::ResponseBuilderJob#perform      response_builder_job.rb ║
╚═══════════════════════════════════════════════════════════════════════════════╝
        │
        ├─◆ captain_can_respond?  (RE-CHECK uncached: status ∈ {pending,open}
        │   ∧ assignee_agent_bot_id == espelho DESTE assistant)          ← :501
        │   └── FALSO ──► EARLY RETURN  (humano assumiu / outra IA pegou / job em voo)
        │
        ├──► reset_followup_state  (cliente respondeu → zera cadência)   ← :103
        ├──► Current.executed_by = assistant  (atividades saem com o nome da IA)
        │
        ├──► collect_previous_messages                                    ← :68
        │       • incoming/outgoing, não-privadas
        │       • filtra pesquisas NPS/CSAT (senão o LLM mimetiza)        ← :95
        │       • multimodal: imagens só em turnos de USER               ← :77
        │       • injeta contexto de reply citado ("[Respondendo a: ...]") ← :186
        │       • encaminha agent_name só se for persona PRÓPRIA          ← :168
        │       • acrescenta @directive (follow-up) como último turno user
        │
        ├─◆ captain_v2_enabled?  (feature_flag captain_integration_v2)    ← :472
        │   │
        │   ├── SIM ──► AgentRunnerService#generate_response  ◄══ CAMINHO REAL HOJE
        │   │            │
        │   │            ├─ build_and_wire_agents:                        ← :216
        │   │            │    assistant.agent  (Concerns::Agentable#agent)
        │   │            │      ├─ instructions: lambda → agent_instructions(context)
        │   │            │      │    ├─ prompt_context (nome, descrição, instructions,
        │   │            │      │    │   scenarios ENABLED, response_guidelines, guardrails)
        │   │            │      │    ├─ time_awareness (data/hora + status do expediente)
        │   │            │      │    └─ Captain::PromptRenderer.render('assistant', ctx)
        │   │            │      │         → Liquid: enterprise/lib/captain/prompts/assistant.liquid
        │   │            │      │           (+ snippets conversation/contact/campaign)
        │   │            │      │         → se prompt_cache_system: 2 blocos (estável+volátil)
        │   │            │      ├─ tools: faq_lookup + handoff [+ search_knowledge]
        │   │            │      │          + config['tools'] filtradas por active?
        │   │            │      ├─ model: account.captain_assistant_model || 'gpt-4.1'
        │   │            │      └─ response_schema: Captain::ResponseSchema
        │   │            │                          { response: string, reasoning: string }
        │   │            │    + scenario_agents (VAZIO hoje — todos disabled)
        │   │            │
        │   │            ├─ context: session_id, conversation_history, state
        │   │            │    (state remove 'aguardando_humano_desde' de propósito ← :205)
        │   │            │
        │   │            ├─ Agents::Runner#run(msg, context:, max_turns: 100)
        │   │            │    └─► gem ai-agents 0.9.1 ──► RubyLLM 1.9.2 ──► OpenAI/Anthropic
        │   │            │         (loop de tool calls; cada tool passa pelo TraceRecorder)
        │   │            │
        │   │            └─ process_agent_result                          ← :108
        │   │                 • output Hash → {response, reasoning}
        │   │                 • se response vazio → last_assistant_message_text (ponte de handoff)
        │   │                 • anti-papagaio: descarta se replays histórico ← :134
        │   │                 • agent_name = context[:current_agent]
        │   │            (erro → error_response = 'conversation_handoff')
        │   │
        │   └── NÃO ──► Captain::Llm::AssistantChatService  (V1, 1 tool só: SearchDocumentation)
        │
        ▼
 process_response                                                        ← :50
        │
        ├─◆ captain_can_respond?  (RE-CHECK #2)
        │
        ├─◆ response['response'] == 'conversation_handoff'?
        │   └── SIM ──► create_handoff_message + bot_handoff! + OOO  ──► FIM
        │
        ├──► create_messages                                             ← :279
        │       ├─◆ no_reply?  ([IGNORAR] / vazio) ──► NÃO ENVIA NADA
        │       ├─◆ skip_duplicate? ──► regenerate_to_avoid_repeat (1 tentativa)
        │       │                        └─ se ainda duplicado ──► silêncio
        │       └──► send_response
        │              ├─ sanitize_for_whatsapp  (markdown, sentinelas,
        │              │   travessões, URLs de imóvel inventadas)         ← :346
        │              └─◆ humanizer_enabled?
        │                   ├─ SIM: split em bolhas; POR BOLHA:
        │                   │    typing indicator → sleep(proporcional)
        │                   │    → RE-CHECK #3 captain_can_respond? (break)
        │                   │    → create! (commit isolado) → wait_for_dispatch(source_id)
        │                   └─ NÃO: uma bolha só
        │
        ├──► account.increment_response_usage      (cota: +1 RESPOSTA, não tokens)
        ├──► ensure_handoff_if_promised  (regex: prometeu humano e não acionou → aciona) ← :244
        └──► auto_schedule_followup      (agenda cutucada em ~N min)      ← :118
        │
        ▼
 Message#after_create_commit → SendReplyJob → canal → CLIENTE
```

### II.3.2 Pontos de decisão e early-returns (contagem)

**Da mensagem até o LLM há 8 portões que podem calar a IA** [F]:
1. `should_process_captain_response?` (gate por atribuição) — `hook_execution_service.rb:139`
2. `captain_quota_available?` — `:195`
3. `message.private?` → desvia p/ copilot — `:39`
4. `RouterService#should_respond?` (3 sub-guards) — `router_service.rb:18`
5. `outside_hours_ignore?` — `:56`
6. Token de debounce vencido — `debounced_response_job.rb:10`
7. Dono trocou (checado no debounce job) — `:16`
8. `captain_can_respond?` no início do `ResponseBuilderJob` — `:501`

**Depois do LLM, mais 5** [F]: re-check #2 (`:51`), `no_reply?` (`:296`), `skip_duplicate?` (`:323`),
re-check #3 por bolha (`:394`), `wait_for_dispatch` timeout (`:407`).

> **Observação de arquitetura:** o mesmo predicado (`captain_can_respond?`) é avaliado **3 vezes**
> no mesmo job, com `Conversation.uncached` e `pick` a cada vez. Isso é sintoma, não defeito:
> o job é longo (dorme segundos entre bolhas) e o mundo muda embaixo dele. Uma reescrita
> deveria transformar isso num **lease explícito** em vez de re-leitura otimista.

---

## II.4. Capacidades reais

### II.4.1 Assistentes

8 assistants na base, todos da conta 3 (Simplex Tecnologia / Tozi) [F]. Cada um tem:
- `config` jsonb: `instructions` (persona livre), `product_name`, `temperature`, `handoff_message`,
  `knowledge_mode`, `tools[]`, `team_id`, `triage`, `voice_id`, `feature_faq/memory/contact_attributes`
- `behavior` jsonb: `debounce_seconds`, `humanizer`, `dedup`, `router`, `business_hours`, `media_pipeline`
- `response_guidelines[]` e `guardrails[]` (listas de strings injetadas no prompt)
- Um **espelho `AgentBot`** 1:1 (`bot_type: captain`) que é o que a conversa realmente referencia

Um deles (Clara, id 3) é a **triagem** (`config.triage = true`) — para onde volta toda conversa órfã.

### II.4.2 Cenários — **desligados**

`Captain::Scenario` [`enterprise/app/models/captain/scenario.rb`, 177 ln] cria **sub-agentes** com
instrução e tools próprias, ligados ao agente principal por handoff bidirecional
(`agent_runner_service.rb:216-224`). Tem lógica sofisticada de nomeação (limite de 64 chars da OpenAI
para nomes de function, `scenario.rb:33-38`) e parsing de `[Tool](tool://id)` na instrução.

**Todos os 11 estão `enabled = false`.** [F: SELECT] O recurso foi substituído na prática por
`transferir_para_agente` (assistant→assistant, trocando o dono-espelho) — que é conceitualmente
diferente: o cenário é um sub-agente dentro da mesma execução; a transferência é uma troca de dono
que reinicia o pipeline.

### II.4.3 Conhecimento (RAG) — dois modos + híbrido

`knowledge_mode` ∈ `faq` (default/legado) | `chunks` | `hybrid` [F: `assistant.rb:80-90`]:

- **FAQ** — `Captain::AssistantResponse` (pergunta/resposta com embedding 1536, ivfflat).
  Populada por `FaqGeneratorService`/`PaginatedFaqGeneratorService` a partir dos documentos, e por
  `ConversationFaqService` a partir de conversas resolvidas. 77 registros. Tool: `faq_lookup`.
- **Chunks** — `Captain::DocumentChunk`, com **busca híbrida real**: candidatos vetoriais (HNSW cosine)
  + candidatos full-text (GIN tsvector `simple`), fundidos por **Reciprocal Rank Fusion** (k=60)
  [F: `document_chunk.rb:49-92`]. Opcionalmente com *contextual retrieval* (1 chamada LLM por chunk
  na ingestão, `contextual_chunks_enabled?`). 38 chunks. Tool: `search_knowledge`.
- 6 dos 8 assistants estão em `hybrid` [F].

Ingestão: URL (Firecrawl com fallback `SimplePageCrawlService`), PDF (`PdfProcessingService`), ou
texto colado inline (`external_link` sentinela `TEXT:`) [F: `document.rb:68`].

### II.4.4 Tools built-in — as 22 do catálogo

Catálogo: `config/agents/tools.yml`. Resolução: `Captain::Tools::#{id.classify}Tool`
[F: `captain_tools_helpers.rb:25`]. **Memoizada em variável de classe** → **mudar o YAML exige restart**.

| # | id | O que faz | Em uso na base? |
|---|---|---|---|
| 1 | `faq_lookup` | Busca semântica na FAQ | **sempre injetada** |
| 2 | `search_knowledge` | Busca híbrida nos chunks (RRF) | **injetada** se chunks/hybrid |
| 3 | `handoff` | Passa p/ humano. Descrição **dinâmica por conta**: modo "time fixo" vs "IA escolhe o time" | **sempre injetada** |
| 4 | `transferir_para_agente` | Troca o dono-espelho p/ outra IA da conta | ✅ 7 assistants |
| 5 | `salvar_info_lead` | Grava status do lead + descrição; move card no Kanban | ✅ 7 |
| 6 | `programar_followup` | Agenda cutucada (token + job) | ✅ 6 |
| 7 | `atualizar_resumo` | Resumo vivo do atendimento em custom_attribute | ✅ 7 |
| 8 | `registrar_observacao` | Nota privada p/ a equipe | ✅ 7 |
| 9 | `registrar_assunto` | Item de checklist p/ a equipe | ✅ 7 |
| 10 | `responder_em_audio` | Voice note via ElevenLabs (exige `voice_id`) | ✅ 1 (Clara) |
| 11 | `buscar_imovel` | Busca no CRM Vista, monta URL canônica, registra códigos | ✅ 2 (Júlia, Bruna) |
| 12 | `enviar_fotos_imovel` | Fotos em lotes de 3, com trava anti-alucinação por código | ✅ 2 |
| 13 | `enviar_localizacao_imovel` | Pin do imóvel (lat/lng do Vista) | ✅ 2 |
| 14 | `enviar_localizacao` | Pin do escritório | ✅ 1 |
| 15 | `buscar_localizacao` | Geocoding Google | ✅ 2 |
| 16 | `buscar_lugar` | Google Places por nome | ✅ 2 |
| 17 | `buscar_empreendimento` | Cadastro de empreendimentos do Vista | ❌ **nenhum** |
| 18 | `add_contact_note` | Nota no perfil do contato | ❌ nenhum |
| 19 | `add_private_note` | Nota privada na conversa | ❌ nenhum |
| 20 | `update_priority` | Prioridade da conversa | ❌ nenhum |
| 21 | `add_label_to_conversation` | Etiqueta | ❌ nenhum |
| 22 | `resolve_conversation` | Resolver a conversa | ❌ nenhum |

**Leitura:** 11 das 22 tools são **verticais de imobiliária** (Vista/Google/Tozi) ou utilitários
criados para esse cliente. As 5 tools genéricas herdadas do upstream Chatwoot (18–22) estão sem uso.
O catálogo não é um catálogo de produto — é o histórico de um projeto.

### II.4.5 Custom tools (HTTP, por conta)

`Captain::CustomTool` [`enterprise/app/models/captain/custom_tool.rb`] + motor `Captain::Tools::HttpTool`.
GET/POST, auth none/bearer/basic/api_key, `param_schema` jsonb, templates Liquid de request/response,
guard SSRF (`Concerns::SafeEndpointValidatable`), flag `copilot_only`.
Na base: 2 registros, **1 deles desabilitado** (migrado para tool built-in) [F: SELECT].

### II.4.6 Handoff, auto-resolve e encerramento

- **Handoff para humano** (`HumanHandoffService`): idempotente, cria dossiê privado, `bot_handoff!`,
  roteia para o time (validando o id contra a conta — *o LLM alucina ids*), marca
  `aguardando_humano_desde`, chama o motor de distribuição. **Não solta o espelho** — a IA continua
  dona até um humano puxar.
- **Rede de segurança**: se o texto enviado *prometeu* humano mas nenhum handoff disparou, dois regexes
  detectam a promessa e acionam a mecânica [F: `response_builder_job.rb:233-252`]. Gambiarra funcional
  e honesta, documentada com o número da conversa que a motivou (18973).
- **Auto-resolve/encerramento** (`InboxPendingConversationsResolutionJob`, 311 ln): três modos por conta
  (`evaluated`/`legacy`/`disabled`) × política `auto_closure` opt-in. Classifica com LLM
  (`ConversationCompletionService`), e por classe decide `queue` (fila humana) / `close` (fecha com
  aviso quando a janela de 24h permite) / `off`. Máquina de estados via `custom_attributes`
  (`aguardando_encerramento_desde`, `encerramento_avisado_em`, `encerramento_classe`) reavaliada a
  cada ciclo do cron. **Ligado na conta 3** (`auto_closure.enabled = true`) [F].

### II.4.7 Avaliação (LLM-as-a-Judge)

`ConversationEvalService` monta um transcript rotulado (`[Cliente]` / `[R#][IA|Humano]` / `[Sistema]`)
**com as tool calls intercaladas cronologicamente** [F: `:120-129`] e pede ao juiz um veredito
estruturado: interesse, intenção, funil, quem conduziu, qualidade do handoff, nota 0–10, resumo,
objeções e **uma entrada por resposta problemática** com 16 categorias de falha (alucinação,
narrou_ferramenta, contradisse_tool, handoff_ausente…).

Usa **chave e modelo dedicados** (`EVAL_OPEN_AI_API_KEY`/`EVAL_OPEN_AI_MODEL`) para isolar custo e
blast radius [F: `:46-53`], e **não consome a cota do Captain** (não expõe `:message`, que é o que o
wrapper de cobrança olha) [F: `:5-7` + `base_task_service.rb:25`]. Design cuidadoso.

O `EpisodeGateService` (asserts determinísticos: "a tool devolveu resultado e a resposta negou",
"tool falhou", "IA repetiu literalmente") **nunca rodou nesta base** — depende do modo episódio.

### II.4.8 Logs

`Captain::AssistantLog` grava 14 tipos de evento [F: `assistant_log.rb:9-13`]. Na base:

| event_type | volume | último |
|---|---|---|
| `debounce_fire` | 205 | 23/07 |
| `humanizer_split` | 109 | 23/07 |
| `mirror_assigned` | 53 | 23/07 |
| `human_takeover` | 21 | 24/07 |
| `mirror_released` | 10 | 23/07 |
| `dedup_skip` | 1 | 25/06 |

**Quem lê:** a API `GET /captain/assistant_logs` (`assistant_logs_controller.rb`, 20 linhas) e o
`ConversationEvalService#system_events_summary`, que resume os eventos para o juiz [F: `:157-164`].
Note o que **não** aparece: `response`, `handoff`, `error`, `media_process`, `router_skip`,
`business_hours_skip` estão declarados no enum mas **nenhum foi gravado** — o log só cobre o que
alguém instrumentou no caminho, não o ciclo de vida completo.

---

## II.5. Modelo de dados

11 tabelas `captain_*` [F: `\dt captain*`]. Volumes desta base (**homologação** — volumes baixos são
esperados; o sinal útil é *zero vs. não-zero* e a data do último registro):

| Tabela | Linhas | Últ. atualização | Colunas-chave | Leitura |
|---|---|---|---|---|
| `captain_assistants` | **8** | 22/07 | `config` jsonb, `behavior` jsonb, `guardrails`, `response_guidelines` | Viva. Note: **toda a configuração é jsonb sem schema** |
| `captain_inboxes` | **7** | 20/07 | (assistant, inbox) unique | Viva — elegibilidade, não posse |
| `captain_scenarios` | **11** | 11/06 | `tools` jsonb, `enabled` | **Todas disabled** — funcionalidade morta em runtime |
| `captain_assistant_responses` | **77** | 24/06 | `embedding vector(1536)` ivfflat, `status` | Viva (FAQ) |
| `captain_documents` | **2** | 11/06 | `status`, `metadata` | Viva, mas rasa |
| `captain_document_chunks` | **38** | 11/06 | `embedding` **HNSW cosine**, `content_search` tsvector **GIN**, `contextual_content` | Viva — a melhor modelagem do conjunto |
| `captain_assistant_logs` | **399** | 24/07 | `event_type`, `payload` jsonb, `duration_ms` | Viva mas cobertura parcial. **`duration_ms` nunca é preenchido** no caminho de conversa |
| `captain_custom_tools` | **2** | 14/07 | `auth_config` jsonb, templates Liquid | Viva (1 ativa) |
| `captain_tool_calls` | **4** | 23/07 | `args`, `result_preview`, `status`, `duration_ms` | **Quase vazia** — só grava com `eval_enabled`; é o único lugar com telemetria de tool |
| `captain_conversation_evals` | **6** | 24/07 | `veredito_raw` jsonb, `response_findings` jsonb, `episode_id` | Viva em modo legado — **todos com `episode_id` NULL** [F] |
| `captain_conversation_episodes` | **0** | — | `seq`, `boundary_reason`, `segmenter_version` | **VAZIA** — a Eval 2.0 F1 nunca foi ligada aqui |

Tabelas relacionadas fora do namespace: `copilot_threads` (5) e `copilot_messages` (12), ambas
paradas desde 04/05 [F].

**Observações sobre o schema:**

- **[F]** A relação IA↔conversa **não tem coluna própria**: usa `conversations.assignee_agent_bot_id`
  apontando para um `AgentBot` com `bot_type: captain` e FK `captain_assistant_id`
  (unique parcial `WHERE captain_assistant_id IS NOT NULL`, `schema.rb:150`). Solução deliberada para
  evitar migration em `conversations` [F: nota do vault]. Funciona, mas exige o join duplo em todo lugar.
- **[F]** Estado de conversa da IA mora em `conversations.custom_attributes` (jsonb livre):
  `aguardando_humano_desde`, `aguardando_encerramento_desde`, `encerramento_avisado_em`,
  `encerramento_classe`, `followup_token`, `followup_count`, `followup_status`, `motivo_encerramento`,
  `urls_imoveis`, `codigos_buscados`, `tozi_status_lead`. **Sem schema, sem índice, sem tipo.**
- **[F]** `captain_conversation_episodes` **não tem FK** para `conversations` — daí o bug de episódio
  órfão (§7.1).
- **[F]** Dois espaços vetoriais paralelos com dimensões iguais (1536) mas índices diferentes:
  ivfflat na FAQ, HNSW nos chunks. Não há razão técnica para a divergência além de idade do código.

---

## II.6. LLM e custo

### II.6.1 Stack

```
Captain::Assistant#agent (Concerns::Agentable)
        │
        ▼
   gem ai-agents 0.9.1        ← Gemfile.lock; wrapper de orquestração (runner, handoffs, tools)
        │
        ▼
   gem ruby_llm 1.9.2         ← cliente HTTP multi-provider + schema
        │
        ▼
   OpenAI  |  Anthropic       ← providers configurados
```

### II.6.2 Modelo escolhido

Cascata [F: `agentable.rb:47-50` + `captain_featurable.rb`]:
```
account.captain_assistant_model  (settings.captain_models['assistant'], validado contra config/llm.yml)
  → LlmConstants::DEFAULT_MODEL = 'gpt-4.1'
  → Llm::Models.runtime_id_for(...)  (traduz 'claude-sonnet-4.5' → 'claude-sonnet-4-5')
```
`config/llm.yml` define, para a feature `assistant`, default `gpt-5-mini` e um menu de 7 modelos.
**Na prática, as contas 1 e 3 estão em `claude-sonnet-4.5`** [F: `SELECT settings->>'captain_models'`].

Serviços que não passam pelo `Agentable` (tasks clássicas, eval, completion) usam
`Llm::Config::DEFAULT_MODEL = 'gpt-4.1-mini'` — **um default diferente**, definido em
`lib/llm/config.rb:6` vs. `lib/llm_constants.rb:4`. **Dois DEFAULT_MODEL divergentes no mesmo repo.** [F]

### II.6.3 De onde vem a chave

Três camadas, resolvidas em `Llm::AccountCredentialsResolver` [F: `lib/llm/account_credentials_resolver.rb`]:
1. **Por conta:** `Captain::OpenaiHookService` / `Captain::AnthropicHookService` (hook de integração da conta)
2. **Global:** `InstallationConfig` `CAPTAIN_OPEN_AI_API_KEY` / `CAPTAIN_ANTHROPIC_API_KEY` / `CAPTAIN_OPEN_AI_ENDPOINT`
3. **Eval:** chave própria `EVAL_OPEN_AI_API_KEY` (isolamento de custo) [F: `conversation_eval_service.rb:47`]

O initializer `config/initializers/ai_agents.rb` configura a gem `Agents` **no boot**, lendo o
`InstallationConfig`. **[F]** Consequência: **trocar a chave global exige restart** — a config da gem
`Agents` é lida uma vez em `after_initialize`.

### II.6.4 Streaming — **NÃO EXISTE**

**[F]** Grep por `stream`/`streaming` em todo o backend do Captain retorna apenas um comentário e
`IO.copy_stream` (PDF). O `Agents::Runner#run` é síncrono e bloqueante, e o `ResponseBuilderJob`
depende disso (ele precisa do texto completo para dedup, sanitização e split do humanizer).

**Implicação direta para a reescrita "experiência ChatGPT":** streaming não é um flag a ligar. É uma
mudança arquitetural que quebra 4 mecanismos do `ResponseBuilderJob` (dedup, `sanitize_for_whatsapp`,
humanizer, `wait_for_dispatch`), todos os quais operam sobre o texto final.

### II.6.5 Cache de prompt — existe, opt-in duplo

**[F]** `Concerns::Agentable#split_instructions_for_cache` (`agentable.rb:163-174`) separa o prefixo
estável (identidade, persona, guardrails) do volátil (data/hora, contexto da conversa) e emite dois
blocos de system, com `cache_control: {type: 'ephemeral'}` só no estável — o desconto de cache da
Anthropic. Fail-safe: qualquer exceção cai no render inteiro.

Ligado por `account.custom_attributes['prompt_cache_system']` ou ENV `SPX_PROMPT_CACHE_SYSTEM`.
**Está `true` na conta 3** [F: SELECT]. Default global: **off**.

### II.6.6 Controle de custo — **quase inexistente**

**[F]** A cota é contada em **respostas**, não em tokens:
`account.increment_response_usage` incrementa `custom_attributes['captain_responses_usage']` em +1
por resposta (`plan_usage_and_limits.rb:18-22`). Uma resposta que gastou 200 tokens e outra que
gastou 80.000 (histórico longo + 6 tool calls) custam **exatamente a mesma coisa** no contador.

- `config/llm.yml` tem `credit_multiplier` por modelo (gpt-4.1: 3, claude-sonnet-4.5: 3, mini: 1),
  mas **[F]** ele **só é usado no frontend** (`ModelDropdown.vue`, `preferences.js`) para ordenar e
  exibir — **nenhum código de backend multiplica nada por ele**.
- Tokens só são observados no exporter OTel/Langfuse (`chat_generation_recorder.rb:37-38`), e apenas
  se `ChatwootApp.otel_enabled?`.
- **`max_turns: 100`** no runner [F: `agent_runner_service.rb:31`]. Cem turnos de tool call num único
  turno de conversa é um teto que não protege ninguém.
- Não há limite de tokens de histórico: `collect_previous_messages` carrega **todas** as mensagens
  não-privadas da conversa [F: `response_builder_job.rb:68-72`]. Numa conversa perpétua de WhatsApp
  com meses de histórico, cada turno reenvia tudo.

### II.6.7 Fallback quando o provider falha — **NÃO EXISTE**

**[F]** `AgentRunnerService#handle_run_error` (`:48`) captura qualquer `StandardError`, reporta e
devolve `{'response' => 'conversation_handoff'}` — ou seja, **qualquer falha de LLM vira handoff
para humano**. Não há retry com outro modelo, outro provider ou degradação graciosa.

Evidência de que isso dói: **21 ocorrências de `RubyLLM::UnauthorizedError: Incorrect API key`** no
projeto `producao` do GlitchTip, primeira em 16/07, última **hoje 28/07 13:10**, todas em
`lib/captain/base_task_service.rb → execute_ruby_llm_request` [F: GlitchTip].

O único fallback existente é de *modelo inválido*: `Llm::Models.first_runtime_supported` escolhe o
primeiro modelo que a gem reconhece na lista de candidatos [F: `base_ai_service.rb:46-59`].

---

## II.7. Dívidas e armadilhas

### II.7.1 Bugs vivos, com evidência

**[F] `EpisodeSegmenterService` com conversa nil — 1.014 ocorrências em PRODUÇÃO, ainda hoje.**
GlitchTip projeto `tozi`, `NoMethodError: undefined method 'messages' for nil` em
`enterprise/lib/captain/episode_segmenter_service.rb → #rows`, primeira em 21/07, **última hoje
28/07 14:16**. Causa: episódio órfão (conversa apagada; a tabela não tem FK).
**O fix já está no repo** — `return [] if conversation.nil?` (`:25`) + `joins(:conversation)` no
scheduler (`:96`), no commit `ee87f5e799` de **hoje 13:43**. **Ainda não deployado na Tozi PROD.**

**[F] `OpenAiMessageBuilderService#pdf_attachment?` — `nil.downcase`**, 4 ocorrências (projeto tozi,
última 27/07): `get_attachment_url(attachment).to_s.split('?').first.downcase` — `split` devolve
`[]` quando a URL é string vazia, e `[].first` é nil.

**[F] `column captain_assistant_logs.account_id does not exist`** e
**`undefined method 'details' for Captain::AssistantLog`** — 1 ocorrência cada (25–27/07).
Sinal de que **alguém (código ou console) espera um schema de `AssistantLog` que não existe**.
Hipótese **[H]**: divergência entre a VM Tozi e o repo, ou script de análise escrito contra um schema
imaginado.

**[F] `PG::GroupingError` em `captain_tool_calls`** — 1 ocorrência (23/07): `GROUP BY tool_name
ORDER BY created_at`. Mesmo padrão: consulta ad-hoc de análise que não é código de produção testado.

### II.7.2 Acoplamentos que uma reescrita vai bater de frente

**a) Dois motores de LLM, e o legado tem porta lateral. [F]**
`ResponseBuilderJob` escolhe V2/V1 pela flag `captain_integration_v2` (`:472`). Mas
`app/services/flows/ai_actions.rb:85` chama `Captain::Llm::AssistantChatService` **direto, sem
checar a flag**. Ou seja: as ações de IA das **Automações** rodam no motor V1 — sem as tools do
agente, sem cenários, sem o `assistant.liquid` (usa `SystemPromptsService`), com uma única tool
(`SearchDocumentationService`). Um assistant configurado com 11 tools se comporta como um assistant
sem nenhuma quando invocado por um Flow. Matar o V1 quebra as Automações.

**b) Prompt de sistema global com viés de vertical. [F]**
`enterprise/lib/captain/prompts/assistant.liquid` é lido do **disco** por conta:
- `:17` — *"horário de Sinop/MT"* hardcoded no bloco de data/hora
- `:26` — *"dúvida sobre um imóvel"* como exemplo de pergunta respondível
- `:5` — *"You will not answer anything about other products"* + *"act as an orchestrator"* —
  a identidade base é de orquestrador de cenários que não existem
- `:34,:99` — instrui a usar `captain--tools--faq_lookup` mesmo quando a conta está em modo `chunks`
  (onde a tool relevante é `search_knowledge`)

Não há prompt por conta. Para mudar o comportamento base de um cliente, edita-se um arquivo do repo
e faz-se deploy na frota inteira.

**c) Lógica de cliente único dentro do core genérico. [F]**
| Onde | O quê |
|---|---|
| `response_builder_job.rb:369-377` | `fix_property_links` — regex `toziimoveis` **dentro do job genérico de resposta** |
| `followup_job.rb:65,69` | grava `tozi_status_lead` e chama `Spx::Tozi::FunnelPlacementService` |
| `salvar_info_lead_tool.rb:18,37-47` | idem + `Spx::Tozi::ReactivationCadenceService` |
| `programar_followup_tool.rb:25` | idem |
| `integration_credentials.rb:22-30` | constantes `DEFAULT_OFFICE_NAME = 'Tozi Imóveis - Av. das Figueiras...'`, `DEFAULT_SITE_DOMAIN = 'toziimoveis.com.br'` como **último fallback global** |
| `followup_job.rb:90` | timezone `America/Cuiaba` **hardcoded** para quiet hours |

**d) Config que não faz nada. [F]**
`behavior.media_pipeline` está gravado em **6 dos 8 assistants** com
`{image_description: true, audio_transcription: true}`, e `Captain::Behavior::MediaPipelineService`
**não tem caller**. O operador liga na tela e nada acontece; a transcrição real vem por outro caminho
(`Messages::AudioTranscriptionJob`). Sintoma de duas implementações que se cruzaram e uma venceu sem
que a outra fosse removida.

**e) O bitmask de features está no limite. [F]**
`config/features.yml` tem **65 features**; `Featurable::FEATURES` mapeia posição→bit começando em 1
(`app/models/concerns/featurable.rb:11-13`), e a coluna é `bigint` (63 bits úteis + sinal).
`captain_tasks` ocupa o **bit 63 — o último**. As features 64 (`conversation_required_attributes`)
e 65 (`advanced_assignment`) **não cabem**. Confirmado no código: `app/models/account.rb:108` já
documenta *"NÃO vai em features.yml — o bitmask bigint já estourou os 63 bits"*.
**Uma feature nova do Captain v2 não pode usar o bitmask.**

**f) Catálogo de tools memoizado em variável de classe. [F]**
`built_in_agent_tools` usa `@built_in_agent_tools ||=` (`captain_tools_helpers.rb:16`), lendo
`config/agents/tools.yml` uma vez por processo. Mudança no YAML só vale após restart de todos os
workers.

**g) `Captain::ResponseSchema` é anêmico. [F]**
`enterprise/lib/captain/response_schema.rb` inteiro tem **6 linhas**: `{response: string,
reasoning: string}`. Toda a semântica extra é passada por **strings mágicas dentro do campo `response`**:
- `'conversation_handoff'` sinaliza handoff (`response_builder_job.rb:224`)
- `[IGNORAR]` / `sem resposta` / `no reply` sinalizam silêncio (`:296-300`)
- e depois há um `gsub` para **remover a sentinela** caso o LLM a anexe a uma resposta real (`:350`)

Um schema de saída de verdade (`action: reply|silence|handoff`, `text`, `confidence`) eliminaria
`no_reply?`, parte do `sanitize_for_whatsapp` e o `ensure_handoff_if_promised` inteiro.

**h) `ResponseBuilderJob` faz 12 coisas. [F: 513 linhas, 1 classe]**
Montagem de histórico, multimodal, contexto de reply, seleção de motor, detecção de handoff,
regex de promessa de handoff, dedup + regeneração, sanitização de markdown, correção de URLs de
imóvel, humanização com sleep, typing indicator, espera de despacho, agendamento de follow-up,
contagem de cota, logging. **Este arquivo é o gargalo de qualquer mudança no Captain.**

**i) O job dorme. [F]**
`send_humanized_response` chama `sleep()` entre bolhas (1.5–7s cada, `:390`) e `wait_for_dispatch`
faz polling de até 6s (`:407`). Uma resposta em 4 bolhas pode segurar um worker Sidekiq por **~30
segundos**. Com N conversas simultâneas isso é fome de worker garantida.

**j) Sem PII sanitization no caminho principal. [F]**
`Captain::PiiSanitizer` existe e é usado por summary/sentiment/follow_up. O `ResponseBuilderJob`
envia o histórico **cru** ao provider.

### II.7.3 Migrations e schema

**[F] Não há migrations pendentes** nesta base: 218 arquivos em `db/migrate`, 241 versões em
`schema_migrations`, `comm -23` = vazio (o banco tem 23 versões a mais — migrations de merges
anteriores já removidas do repo). **Nenhum timestamp duplicado** (`uniq -d` vazio).
Ainda assim, o GlitchTip registra `PG::DependentObjectsStillExist: cannot drop table kanban_items`
(4x, projeto homologacao, até 22/07) — migration que falha em ambientes com dados, não relacionada
ao Captain mas indicativa de que a esteira de migration da frota não é confiável.

### II.7.4 Os documentos internos ainda batem?

**`plano/agentes-tools-mcp-PLANO.md`** (2026-06-29, "Status: PLANEJAMENTO, nada implementado") —
**está DESATUALIZADO no bom sentido: quase tudo foi feito.** Confronto item a item:

| Item do plano | Status hoje |
|---|---|
| Bug 4: `config['tools']` fora do strong-params | ✅ **corrigido** — `assistants_controller.rb:114` tem `{ tools: [] }` |
| Bug 7: `transferir_para_agente` duplicado no tools.yml | ✅ **corrigido** — `sort \| uniq -d` vazio |
| Bug 5/6: tools ENV-only, credenciais sem model | ✅ **feito** — tabela `account_integrations` existe (`schema.rb:31`), model `app/models/account_integration.rb`, concern `Captain::Tools::IntegrationCredentials` com cascata AccountIntegration → custom_attributes → ENV |
| Fase D: MCP real | ✅ **existe** — diretório `mcp/chatspx-tools` |
| Bugs 1/2/3 (frontend: autofill, catálogo hardcoded, form quebrado) | ❓ **não verificado** — fora do escopo deste P1 (backend) |

**`vault/01-Permanentes/Padrao - IA como atendente via AgentBot-espelho.md`** — **BATE integralmente
com o código.** Os 5 pontos do padrão e as 4 armadilhas descritas estão todos implementados e
verificáveis linha a linha (espelho, gate, `CaptainInbox` como elegibilidade, re-check nos jobs,
`AssignmentKickJob`, override de `activity_message_owner`). É o documento mais confiável do conjunto
e **deve ser a base do desenho do v2**.

---

## II.8. O que eu faria diferente

> ⚠️ **FORA DE ESCOPO.** Escrito antes da correção de escopo, quando "Captain" foi entendido como
> os agentes de IA. **Nada nesta seção é proposta para o projeto atual** — os agentes de IA são
> zona proibida. Fica registrado para um projeto futuro. A recomendação válida para **este**
> projeto está na **§I.4**.

### II.8.1 MANTER INTACTO

**A camada de posse e orquestração de conversa.** É o ativo real. Especificamente:

1. **AgentBot-espelho + gate por atribuição.** Resolve "quem fala agora" sem migration, sem User falso,
   com exclusividade bot×humano garantida pelo core do Chatwoot. Reescrever isso é queimar 6 meses
   de armadilhas já mapeadas (o vault documenta as 4 principais).
2. **`AssignmentKickJob`** — o padrão "re-execute o mesmo entry point quando o dono muda" é
   idempotente e elegante. Mantém a triagem assíncrona funcionando sem duplicar caminho de código.
3. **Debounce por token Redis.** Simples, correto, com margem de TTL pensada para lag de Sidekiq.
4. **`HumanHandoffService` / `PendingClosureService`** — dois eixos (atendimento vs. encerramento),
   idempotentes, com dossiê privado. Bem desenhados.
5. **A busca híbrida com RRF** em `DocumentChunk`. É a melhor peça técnica do conjunto: vetorial +
   full-text fundidos sem dependência externa, com o ponto de extensão para reranker já marcado.
6. **O `ConversationEvalSchema`** — as 16 categorias de falha são um catálogo de erro de agente
   ganho em campo. Vale ouro para regressão. Não invente outro.
7. **O padrão `Current.executed_by`** para atribuir autoria das ações à IA.

### II.8.2 REFATORAR

1. **Quebrar o `ResponseBuilderJob` em três.**
   `ResponsePlanner` (monta contexto e histórico) → `ResponseGenerator` (chama o motor, devolve
   estrutura) → `ResponseDelivery` (dedup, sanitiza, humaniza, envia). Hoje é uma classe de 513
   linhas que ninguém consegue mudar com segurança.

2. **Trocar o `ResponseSchema` por um schema de ação real.**
   ```
   { action: "reply" | "silence" | "handoff" | "resolve",
     text: string|null, handoff_reason: string|null, team_id: int|null,
     confidence: float, reasoning: string }
   ```
   Isso mata: `no_reply?`, metade do `sanitize_for_whatsapp`, `ensure_handoff_if_promised`
   (~80 linhas de regex e gambiarra), e torna o comportamento **testável**.

3. **Prompt por conta, versionado no banco.** `assistant_prompts(assistant_id, version, body,
   active)` com o Liquid atual como *template base do sistema* e o texto do cliente como camada.
   Fim do "editar arquivo + deploy na frota" para mudar a persona de um cliente. Mantenha o
   `PromptRenderer` (Liquid + snippets é uma boa escolha) — mude só a **origem** do template.

4. **Um motor só.** Decida V2 e mate o V1 — mas **antes** migre `Flows::AiActions` para o
   `AgentRunnerService` (ou para um `Captain::OneShotService` explícito, que é o que as automações
   realmente querem: um prompt sem tools nem histórico). Deixar o V1 vivo "só para os flows" é
   como o débito nasceu da primeira vez.

5. **Extrair o vertical.** Todo código `Tozi`/`Vista`/`toziimoveis`/`Spx::Tozi::*` sai do core
   (`response_builder_job`, `followup_job`) e vira **hook por conta** — um `after_response` /
   `on_lead_status_change` registrável. As tools de imobiliária ficam onde estão (são tools, é o
   lugar certo), mas o *job genérico* não pode conhecer `toziimoveis.com.br`.

6. **Cota em tokens, não em respostas.** O `credit_multiplier` já existe no `llm.yml` e já é
   exibido ao usuário — só falta o backend usar. Registre `input_tokens`/`output_tokens` por
   execução numa tabela (`captain_runs`) e cobre por crédito real. Hoje o produto cobra igual por
   uma resposta de 200 e uma de 80.000 tokens.

7. **Janela de histórico.** `collect_previous_messages` precisa de um teto (N mensagens ou M tokens)
   com sumarização do que ficou para trás. Numa conversa perpétua de WhatsApp o custo cresce
   linearmente para sempre.

8. **Tirar o `sleep` do worker.** O humanizer deve enfileirar N jobs com `wait:` escalonado, não
   segurar um worker Sidekiq por 30 segundos. O `wait_for_dispatch` vira uma cadeia de callbacks.

### II.8.3 JOGAR FORA

1. **Os 5 arquivos mortos** (§2.6): `ToolRegistryService`, `Tools::BaseService`,
   `WebsiteAnalyzerService`, `ContactAttributesService`, `MediaPipelineService` — **e as configs
   `behavior.media_pipeline` órfãs no banco junto** (senão a UI continua oferecendo um botão que
   não faz nada).
2. **Cenários (`Captain::Scenario`).** 177 linhas de modelo + tabela + controller + policy +
   ~40% do `assistant.liquid` para um recurso desligado em 100% dos registros. A multi-persona real
   que emergiu foi `transferir_para_agente` (assistant→assistant). **Escolha uma.** Se a escolhida
   for a transferência, o prompt precisa ser reescrito — hoje ele instrui o LLM a orquestrar
   sub-agentes que não existem, o que é ruído puro em todo turno.
3. **As 5 tools genéricas sem uso** (`add_contact_note`, `add_private_note`, `update_priority`,
   `add_label_to_conversation`, `resolve_conversation`) — ou implemente-as no produto novo com
   intenção, ou remova. Hoje ocupam espaço no catálogo e no *prompt de seleção de tool* de qualquer
   assistant que as arme por engano.
4. **`Captain::ConversationEval` em modo legado (por conversa).** O modo episódio é
   conceitualmente correto (a conversa de WhatsApp é perpétua; o *atendimento* é o episódio).
   Ligue o modo episódio e **remova o legado** — manter os dois é ter duas definições de "o que é
   um atendimento" no mesmo sistema, e a tabela de episódios vazia prova que ninguém está usando
   a boa.
5. **O Copilot como está.** 32 tools, motor V1, 12 mensagens em 3 meses, parado desde maio. Ou é um
   produto (e merece o motor novo) ou é peso morto com 32 superfícies de manutenção. Não pode
   continuar sendo um terceiro sistema de IA no repo.

### II.8.4 O que a reescrita precisa resolver e hoje ninguém resolve

| Lacuna | Por que importa para "experiência ChatGPT" |
|---|---|
| **Streaming** | Não existe, e 4 mecanismos do `ResponseBuilderJob` dependem do texto completo. É a decisão arquitetural nº 1 do v2 |
| **Fallback de provider** | Qualquer erro de LLM vira handoff. 21 erros de chave inválida em prod nos últimos 12 dias |
| **Estado tipado da conversa** | Hoje é jsonb livre em `custom_attributes`, sem schema nem índice, com 11 chaves conhecidas |
| **Telemetria de execução** | `captain_tool_calls` só grava com `eval_enabled` (4 linhas). Não há tabela de *runs* com tokens, latência e modelo |
| **Memória de longo prazo** | Existe `feature_memory` → `ContactNotesService` no `conversation_resolved`, mas não há recuperação estruturada de memória por contato no prompt |
| **Testabilidade determinística** | Não há harness de replay/regressão contra histórico real. O `run_raw` em `spx/ai_config` é o embrião disso e deveria virar cidadão de primeira classe |

---

## Apêndice A — Como reproduzir as verificações

### A.0 Copiloto e fronteira (Parte I)

```bash
# Os TRÊS caminhos, pelas rotas
grep -n "copilot" config/routes.rb          # :77-78 (threads) · :242 (copilot_chat)
grep -n "ghost_suggestion" config/routes.rb # :241

# Copiloto SPX NÃO toca Captain::Assistant
grep -rn "Captain::Assistant\|assistant" app/services/copilot/     # → nada
grep -rn "OPENAI_API_KEY\|openai_api_key" app/services/copilot/openai_settings.rb

# A cota compartilhada (o risco ALTO)
grep -rn "increment_response_usage" --include="*.rb" app/ enterprise/
#   → captain/copilot/chat_service.rb:31          (copiloto)
#   → enterprise/captain/base_task_service.rb:30  (tasks)
#   → captain/conversation/response_builder_job.rb:62 (AGENTE DE IA)
grep -n "captain_quota_available?" -A3 enterprise/app/services/enterprise/message_templates/hook_execution_service.rb

# O copiloto pode falar com o cliente
sed -n '11,22p' enterprise/app/services/captain/tools/copilot/send_message_service.rb

# Uso real dos três caminhos
psql ... -c "SELECT count(*) FROM copilot_threads;"                       # B → 5 (paradas em maio)
psql ... -c "SELECT count(*) FROM conversations
             WHERE additional_attributes ? 'copilot_history'
               AND jsonb_array_length(additional_attributes->'copilot_history') > 0;"  # A → 0
python3 -c "import yaml; ns=[f['name'] for f in yaml.safe_load(open('config/features.yml'))]; \
i=ns.index('ai_assistant_v2'); print('bit',i+1, [bool(m>>i&1) for m in \
[2306313755731427287,7278217375621054423,2306313755748204503,2306269775280996311]])"   # C → todas False

# Respostas prontas (o /atalho a ser aposentado)
psql ... -c "SELECT account_id, count(*) FROM canned_responses GROUP BY 1;"  # → 9 no total
```

### A.1 Agentes de IA (Parte II)

```bash
# Volumes das tabelas
psql -h localhost -U chatwoot -d chatwoot_production -c "\dt captain*"

# Cenários desligados
psql ... -c "SELECT id, assistant_id, title, enabled FROM captain_scenarios;"

# Feature flags decodificadas (bit N = posição N em config/features.yml)
python3 -c "import yaml; ns=[f['name'] for f in yaml.safe_load(open('config/features.yml'))]; \
m=7278217375621054423; print([n for i,n in enumerate(ns) if m>>i&1 and 'captain' in n])"

# Provas de código morto
grep -rn "Captain::ToolRegistryService" --include="*.rb" app/ lib/ enterprise/ config/   # → 1 (a própria def)
grep -rn "Captain::Behavior::MediaPipelineService" --include="*.rb" app/ lib/ enterprise/ # → 1
grep -rn "Captain::Llm::ContactAttributesService" --include="*.rb" .                      # → 1

# Migrations pendentes
comm -23 <(ls db/migrate/*.rb | sed 's|.*/||; s|_.*||' | sort) \
         <(psql ... -At -c "SELECT version FROM schema_migrations ORDER BY 1;")           # → vazio
```

## Apêndice B — Limites desta pesquisa

- **[Não verificado]** **Uso dos três copilotos em produção.** Os volumes da §I.2 são de
  **homologação**. Antes de apagar qualquer um dos três caminhos, contar o uso nas VMs de produção
  (`copilot_threads`, `copilot_history`, canned responses). Sem SSH, não pude.
- **[Não verificado]** **O front do copiloto em profundidade.** Mapeei os pontos de entrada
  (`CopilotPanel.vue`, `CopilotContainer.vue`, `AIAssistantPanel.vue`, `ReplyBox.vue` ghost, stores
  e composables) o suficiente para provar que são três caminhos distintos, mas não auditei os ~20
  componentes de `components-next/copilot/` nem o `useCopilotReply.js` linha a linha. Isso é
  trabalho de um P dedicado a front.
- **[Não verificado]** **O comportamento do `dependent:` ao apagar um assistente com threads de
  copiloto** (§I.3-A). Marcado como **[H]**.
- **[Não verificado]** O frontend dos agentes de IA (`app/javascript/dashboard/.../captain/`) — os
  bugs 1–3 do `agentes-tools-mcp-PLANO.md` são todos de front e continuam sem confirmação.
- **[Não verificado]** O estado real das outras VMs da frota. As proibições da task (sem SSH para
  .109/.229/fábrica) foram respeitadas — a leitura de produção veio **só** do GlitchTip. O bug do
  §7.1 está *inferido como não-deployado* pela combinação "fix commitado hoje 13:43" + "erro
  ocorrendo hoje 14:16 no projeto tozi" — **[H]** forte, mas não provada por inspeção da VM.
- **[Não verificado]** Comportamento em runtime: **nenhuma IA foi disparada** contra nenhuma conversa,
  conforme a restrição. Tudo aqui é leitura de código, de schema e de dados persistidos.
- Volumes vêm de **homologação**. Para dimensionar (custo, throughput, taxa de handoff) é preciso ler
  a base de produção — trabalho para outro P.
