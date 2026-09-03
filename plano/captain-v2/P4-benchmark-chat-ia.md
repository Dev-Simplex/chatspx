# P4 — Benchmark: o que faz um chat de IA parecer o ChatGPT (e o que faz ele ser bom)

**Data:** 28/07/2026
**Escopo:** pesquisa externa (web) + **mapeamento da fronteira no código** (§6). Nenhuma alteração de código.
**Entregável para:** reescrita do **copiloto do agente** no ChatSPX.

> **ALVO desta reescrita:** o chat de copiloto que o **agente humano** usa dentro da conversa.
> **ZONA PROIBIDA:** os agentes de IA que atendem o cliente (assistentes, cenários, base de
> conhecimento/documentos, avaliação, handoff, auto-resolve). Não propor mudança neles.
> Os dois estão interligados — **§6 mapeia exatamente onde**, com `caminho:linha`.

> Convenção deste documento: tudo que é **fato com fonte** vem com link.
> Tudo que é **julgamento meu** aparece marcado como `[opinião minha]`.

> **Premissas já decididas pelo Walisson** (não rediscutidas aqui): respostas prontas são
> aposentadas (a IA escreve do zero, acervo vira base de conhecimento); um só motor de chat
> servindo o copiloto-na-conversa (fase 1) e a tela própria (fase 2); o copiloto **não fala
> com o cliente** — sugere, e o humano aprova. ⚠️ Essa última premissa **não é o estado atual
> do código** — ver §6.5.

---

## 0. Resumo executivo

1. **A "cara do ChatGPT" é barata de copiar; a experiência do ChatGPT não é.** O que os usuários leem como "parece o ChatGPT" são cinco coisas concretas: coluna de leitura estreita (~65 caracteres/linha), composer que cresce com o texto, streaming token a token, markdown rico com bloco de código copiável, e histórico agrupado por data. Nada disso é difícil. O que é difícil é o resto.

2. **Streaming é o item que mais muda percepção e o mais arriscado tecnicamente aqui.** Usuários percebem respostas em streaming como **40–60% mais rápidas** mesmo com tempo total idêntico ([TianPan](https://tianpan.co/blog/2026-04-16-streaming-ttft-latency-perception)). Mas o ChatSPX **não tem streaming real hoje** — o Copilot inline faz uma requisição única e roda um efeito máquina-de-escrever local (ver §2.1). Ou seja: hoje o agente espera a resposta inteira em silêncio.

3. **`[opinião minha, com base em fonte]` Não use ActionCable para streaming token a token.** ActionCable é *at-most-once* e **não numera mensagens**, então não há garantia de ordem sob carga — a Evil Martians documentou exatamente esse cenário com LLM ([Evil Martians](https://evilmartians.com/chronicles/anycable-rails-and-the-pitfalls-of-llm-streaming), [Ably](https://ably.com/blog/rails-actioncable-the-good-and-the-bad)). Chunks fora de ordem em texto = palavras embaralhadas na frente do agente. A recomendação é **SSE** (§2.4), que é o que OpenAI e Anthropic usam nas próprias APIs.

4. **A infra da frota já está pronta para SSE.** O nginx do repo tem `proxy_buffering off` e `proxy_read_timeout 900s` **no nível do server block** (`deployment/nginx_chatwoot.conf:45-51`), valendo para `/api/` e `/`. Não precisa mexer em nginx. O que precisa de ajuste é o **Puma** (§2.7).

5. **Confiança vem de citação de fonte, não de "raciocínio".** A NN/g é explícita: mostrar cadeia de raciocínio passo a passo é **contraindicado**, porque as explicações "are often unfaithful to the model's actual computation" — são racionalizações post-hoc que inflam confiança indevidamente ([NN/g, Explainable AI](https://www.nngroup.com/articles/explainable-ai/)). O que funciona é fonte próxima da afirmação, com rótulo verificável e link para o trecho.

6. **Chat de atendimento ≠ ChatGPT genérico.** A NN/g mediu: usuários (e agentes) não querem conversa, querem resposta — *"users who land on your site with a question aren't looking for a conversation — they're looking for an answer"* ([NN/g, Less Chat More Answer](https://www.nngroup.com/articles/less-chat-more-answer/)). Um participante descreveu resposta em stream longa como *"kind of made me feel overwhelmed"*. Para o agente com cliente esperando, isso vale em dobro.

7. **Ninguém matou as respostas prontas. Todo mundo fundiu.** Intercom, Zendesk e Freshdesk mantêm macros/canned responses e usam a IA para **escolher, preencher e reescrever** o template — não para eliminá-lo. O Zendesk gera a primeira resposta *"based on existing macros and help center articles"* e mostra macros sugeridas **com indicador de confiança** ([Zendesk](https://support.zendesk.com/hc/en-us/articles/7908817636378-About-agent-copilot)). Detalhe operacional: essa é a resposta direta ao pedido do Walisson (§4.4).

8. **O modelo dominante é sugerir ao agente, não responder ao cliente — quando há agente na tela.** Freddy/Copilot/MagicReply são todos *human-sends*. A IA autônoma (Fin, Lyro, Captain Assistant) atua **antes** do agente entrar. São dois produtos diferentes que compartilham a mesma base de conhecimento.

9. **Adoção morre em uma semana se a qualidade for ruim.** *"Agents will learn to ignore Copilot suggestions within the first week, killing adoption permanently"* ([Assembled](https://www.assembled.com/page/contact-center-ai-copilot)). O bloqueador número um relatado não é o modelo — é qualidade da base de conhecimento, encaixe no fluxo e transparência de fonte.

10. **Risco jurídico é real e já tem jurisprudência.** *Moffatt v. Air Canada*, 2024 BCCRT 149: tribunal responsabilizou a empresa por promessa inventada pelo chatbot, rejeitando a defesa de que o bot seria entidade separada — *"This is a remarkable submission"* ([ABA](https://www.americanbar.org/groups/business_law/resources/business-law-today/2024-february/bc-tribunal-confirms-companies-remain-liable-information-provided-ai-chatbot/)).

### 0.1 Achados do mapeamento de código (§6) — leia estes primeiro

11. **Não existe "o copiloto". Existem quatro caminhos vivos e três motores de LLM diferentes**, com **chaves de API diferentes** e capacidades muito distintas. Reescrever sem saber disso é reescrever um dos quatro e deixar os outros três em pé. Mapa completo em §6.1.

12. **⚠️ O copiloto HOJE fala com o cliente.** `Captain::Tools::Copilot::SendMessageService` envia mensagem **outgoing** (`private: false` é o default) via `Messages::MessageBuilder`, e há mais 11 tools que agem sobre o atendimento real (resolver, atribuir, transferir, mudar status, editar contato). O único portão é a permissão `conversation_manage` do usuário — **não há aprovação humana da mensagem**. A premissa "o copiloto não fala com o cliente" é um **requisito a implementar**, não o estado atual. Ver §6.5.

13. **⚠️ O copiloto e os agentes de IA disputam a MESMA cota de respostas.** `@account.increment_response_usage` é chamado tanto pelo copiloto (`enterprise/app/services/captain/copilot/chat_service.rb:31`) quanto pelas tasks (`enterprise/lib/enterprise/captain/base_task_service.rb:30`) e pelo atendimento automático (`response_builder_job.rb:62`). **Aumentar o uso do copiloto pode esgotar a cota e derrubar o atendimento ao cliente**, que é produção. Esse é o risco número um da reescrita. Ver §6.4.

14. **O vínculo `CopilotThread → Captain::Assistant` é obrigatório e sem fallback.** O `belongs_to` é obrigatório no model e o controller usa `find` (não `find_by`) — `enterprise/app/controllers/api/v1/accounts/captain/copilot_threads_controller.rb:51`. Sem agente de IA criado, ou com o agente apagado, **o copiloto não abre**. Ver §6.2.

15. **O painel v2 que já existe é mais pobre que o v1 que ele substitui.** `AIAssistantPanel.vue` (atrás da flag `ai_assistant_v2`) usa `useCaptain` → `captain/tasks`, e **não** usa `copilot_threads`. Ou seja: perde as 33 tools, o thread persistido e o RAG do assistente. Isso é uma decisão arquitetural já tomada no código que provavelmente ninguém registrou. Ver §6.1 e §6.6.

---

## 1. Anatomia da interface

### 1.1 Layout

O padrão consolidado (ChatGPT, Claude, Gemini, Perplexity) tem **nove regiões** ([Setproduct](https://www.setproduct.com/blog/ai-chat-interface-ui-design)):

| Região | Descrição | Essencial? |
|---|---|---|
| Lista de conversas (sidebar esq.) | threads com títulos auto-gerados, agrupadas por recência | **Sim** |
| Header | seletor de modelo, título editável, compartilhar | Parcial |
| Message stream | coluna vertical centralizada, `max-width` ~720–768px | **Sim** |
| Mensagem do usuário | alinhada à direita, editável (permite branch) | **Sim** |
| Mensagem do assistente | markdown rico (headings, código, tabelas) | **Sim** |
| Composer | textarea multilinha, cresce sozinho, anexo | **Sim** |
| Stop / Regenerate | parar durante stream, regenerar depois | **Sim** |
| Ações por mensagem | copiar, editar, feedback — revelam no hover | **Sim** |
| Chips de sugestão | prompts clicáveis, descartáveis | Opcional |

**Largura de leitura.** O ChatGPT restringe a coluna de resposta a ~**65 caracteres por linha** — é a decisão de design mais subestimada da interface segundo a análise da 925studios: *"ChatGPT constrains its response area to roughly 65 characters per line, which is the optimal reading line length"* ([925studios](https://www.925studios.co/blog/chatgpt-interface-design-breakdown)). A recomendação do Setproduct é 65–72 caracteres, `line-height` 1.6.

**O vazio é deliberado.** *"a blank text field at the center of the screen. No instructions. No templates."* — o placeholder "Message ChatGPT" comunica *"you already know what to do"*. A análise resume o design como *"radical subtraction, not creative innovation"*.

`[opinião minha]` No contexto de atendimento esse vazio é o **oposto** do que você quer. O agente sob pressão não está explorando: ele tem uma tarefa. A NN/g mede isso — chatbot que abre com "Como posso ajudar?" vago deixa o usuário sem sinal de capacidade; com três exemplos nomeados o usuário decide em ~5 segundos se a ferramenta serve. Para o Captain, a tela vazia deve trazer as 3–5 ações mais usadas naquela conversa, não um convite em branco.

**Mobile.** Coluna única, composer **ancorado ao fundo, não flutuante**, 16px de padding lateral.

### 1.2 A mensagem

Elementos que compõem uma mensagem de assistente que "parece profissional":

- **Markdown completo**: headings, listas, negrito, tabelas, links, math.
- **Bloco de código com botão copiar.** Ausência disso é listada como anti-pattern explícito.
- **Rótulo/avatar** que identifique claramente máquina vs humano. A NN/g coloca transparência sobre identidade do bot como diretriz ([NN/g, chat UX #17](https://www.nngroup.com/articles/chat-ux/)).
- **Timestamp** revelado no estado completo.

**Armadilha técnica real: markdown incompleto durante o stream.** A árvore de parse é instável no meio do fluxo — *"A line that has just shown two backticks is briefly an inline-code start until the third backtick arrives"*. Um renderizador ingênuo pisca texto cru e layout quebrado até o stream fechar ([The Prompt Bench](https://thepromptbench.com/ai-product-ux/streaming-ui-patterns-that-dont-break/)). Soluções conhecidas:

- Fazer *debounce* do parse em **50–100ms** — *"Re-parsing at 60fps on every token is wasteful — the user cannot read that fast anyway"*.
- Bufferizar nós de bloco até estarem completos; renderizar fence aberto **como bloco de código**, nunca como inline.
- Adiar renderização de math até o fim do stream (pisca muito).
- `contain: layout` em listas longas para evitar layout thrash.
- Referências de implementação: [`vercel/streamdown`](https://github.com/vercel/streamdown/issues/473), [`parseIncompleteMarkdown.ts` do HuggingFace chat-ui](https://huggingface.co/spaces/mishig/chat-ui/blob/700a2240da17049333f7f4adbec7357ea0d4f7da/src/lib/utils/parseIncompleteMarkdown.ts), [markstream-vue](https://markstream-vue-docs.simonhe.me/guide/ai-chat-streaming) (esse é Vue, relevante aqui).

### 1.3 Ações por mensagem

| Ação | Presente em | Essencial? |
|---|---|---|
| Copiar | todos | **Sim** |
| Regenerar | todos | **Sim** |
| Editar a pergunta (e re-ramificar) | ChatGPT, Claude | **Sim** — ver §1.9 |
| Feedback 👍/👎 | todos | Sim (barato, alimenta melhoria) |
| Ler em voz alta | ChatGPT | Penduricalho no atendimento |
| Compartilhar mensagem | ChatGPT | Penduricalho |

### 1.4 O composer

Comportamentos obrigatórios:

- **Cresce com o texto** até um teto, depois rola internamente.
- **Enter envia, Shift+Enter quebra linha.** (Confirmado como padrão do ChatGPT — [Coursera cheat sheet](https://www.coursera.org/articles/chatgpt-keyboard-shortcuts); Setproduct sugere também Cmd+Enter.)
- **Botão parar** durante geração, no lugar do botão enviar. Ausência é anti-pattern.
- **Anexos** (opcional no contexto de atendimento).
- Detalhe do ChatGPT: o próprio campo do composer *"shimmers"* enquanto a resposta está streamando, e ao terminar aparece um snippet efêmero truncado acima do composer ([OpenAI Apps SDK — UI guidelines](https://developers.openai.com/apps-sdk/concepts/ui-guidelines)).

### 1.5 Estados

Os seis estados que precisam existir ([Setproduct](https://www.setproduct.com/blog/ai-chat-interface-ui-design)):

| Estado | Tratamento | Duração típica |
|---|---|---|
| Queued | ponto pulsante / shimmer | 200ms–2s |
| Thinking | seção **colapsável** | variável |
| Streaming | caret piscando, reflow contínuo, **respeitando o scroll do usuário** | — |
| Complete | ações reveladas, timestamp | — |
| Error | mensagem **específica** + ação de recuperação (nunca genérica) | — |
| Stopped | **preserva a resposta parcial** + "Continuar" e "Regenerar" | — |

**Auto-scroll — modelo de 3 estados** (esse detalhe separa app bom de app irritante):

1. **Ancorado**: auto-scroll ativo quando o usuário está a ~100px do fim.
2. **Desancorado**: para assim que o usuário rola para cima.
3. **Reancoragem**: mostra botão "ir para o fim" até o usuário voltar explicitamente.

A NN/g vai além e recomenda **não** rolar automaticamente para o fim da resposta: *"Manter posição de rolagem do usuário no topo da nova mensagem"*, porque as pessoas leem de cima para baixo e o auto-scroll desorienta em respostas streamadas ([NN/g, 10 guidelines #7](https://www.nngroup.com/articles/ai-chatbots-design-guidelines/)).

### 1.6 Histórico

- Agrupamento por data: **Hoje / Ontem / Últimos 7 dias**. A leitura da 925studios é que o agrupamento cria *"a sense that the product remembers them"* — a sidebar vira *"a kind of external memory, a log of your thinking history with the model"*.
- Renomear, apagar, buscar: essenciais.
- Anti-pattern explícito: **histórico não persistido**.

### 1.7 Atalhos de teclado

Do ChatGPT ([fonte](https://www.coursera.org/articles/chatgpt-keyboard-shortcuts), [fonte](https://fastshortcuts.com/shortcuts/chatgpt/)):

| Atalho | Ação |
|---|---|
| `Ctrl/Cmd + /` | abre a própria lista de atalhos |
| `Enter` / `Shift+Enter` | enviar / quebra de linha |
| `Ctrl/Cmd + Shift + C` | copiar a última resposta |
| `Ctrl/Cmd + Shift + ;` | copiar o último bloco de código |
| `Ctrl/Cmd + Shift + O` | nova conversa |

Comparação útil: o Intercom expõe o Copilot em `⌘/Ctrl K` (paleta de comando, buscar "Ask Copilot") e `⌘/Ctrl J` para as opções de IA; `Tab` aceita smart reply, `Esc` descarta ([Intercom](https://www.intercom.com/help/en/articles/6955446-ai-features-available-in-the-inbox)).

`[opinião minha]` Para o Captain, os atalhos que realmente importam são três: invocar (paleta ou tecla única), **aceitar/inserir no composer**, e **descartar**. `Tab` para aceitar e `Esc` para descartar é convenção já estabelecida (Intercom, Copilot de código) — usar outra coisa é criar atrito de graça.

### 1.8 Essencial vs. penduricalho

| Essencial (não entregar sem) | Penduricalho (adiar) |
|---|---|
| Streaming token a token com botão Parar | Ler em voz alta |
| Markdown + bloco de código com copiar | Seletor de modelo exposto ao agente |
| Composer que cresce, Enter/Shift+Enter | Anexos no chat com a IA |
| Copiar / Regenerar / Editar pergunta | Compartilhar conversa |
| Estados de erro específicos e acionáveis | Entrada por voz |
| Histórico persistido, agrupado, buscável | Chips de sugestão genéricos |
| Auto-scroll com desancoragem | Branching visual de conversas |
| Citação de fonte clicável | Animação de digitação artificial (**é anti-pattern**) |
| `aria-live` correto (§1.10) | Temas/customização visual |

### 1.9 Um achado de pesquisa que muda o design: Accordion Editing e Apple Picking

A NN/g fez estudo qualitativo (8 participantes, sessões de 90 min, setembro/2023) e nomeou dois comportamentos que aparecem sempre ([NN/g](https://www.nngroup.com/articles/accordion-editing-apple-picking/)):

- **Accordion Editing** — *"users ask the AI to shrink or expand its outputs, often back to back"*. O usuário fica encurtando/expandindo para chegar num alvo.
- **Apple Picking** — *"users reference one or multiple, previous AI-responses in their following prompt"*, tendo que descrever ou copiar manualmente pedaços de respostas anteriores.

Conclusão dos pesquisadores: *"conversational user interface stops being easy"* na hora de iterar. As três recomendações são:

1. **Compartimentalização** — editar uma porção sem regenerar tudo.
2. **Edição direta** — deixar o usuário editar o texto à mão, sem escrever um novo prompt.
3. **Point-to-select** — selecionar o trecho e agir sobre ele, em vez de descrevê-lo.

`[opinião minha]` Isso é o requisito mais importante desta seção para o Captain, e é onde o ChatGPT é fraco. Um agente de atendimento faz *accordion editing* o tempo todo ("mais curto", "mais formal", "tira essa parte"). Se a saída da IA cair num **editor de verdade** (o próprio composer de resposta), com seleção de trecho + ação sobre a seleção, você entrega algo melhor que o ChatGPT no ponto que mais dói. O Intercom já caminhou nessa direção com "Add to composer & modify" (More friendly / More formal / Rephrase / Translate).

### 1.10 Acessibilidade (não-negociável, e sutil no streaming)

- Região viva para o conteúdo: `role="log"` tem `aria-live="polite"` implícito e `aria-atomic="false"` ([W3C WAI ARIA23](https://www.w3.org/WAI/WCAG21/Techniques/aria/ARIA23)).
- **Não anunciar token a token** — vira enxurrada de fala. Ou faz batch a cada poucos segundos, ou suprime a live region durante o stream e anuncia a mensagem completa ao final ([A11Y Collective](https://www.a11y-collective.com/blog/aria-live/)).
- A live region precisa existir **vazia no carregamento**; se inserida dinamicamente, esperar ~2s antes de injetar texto.
- Contraste WCAG 2.2 AA (4.5:1) e respeitar `prefers-reduced-motion`.

---

## 2. Streaming — recomendação técnica para Rails + Vue + ActionCable

### 2.1 Diagnóstico: o que o ChatSPX tem hoje

Lendo o repo (`app/javascript/dashboard/composables/useCopilotReply.js`):

- O fluxo é `await processEvent(action, data, { signal })` — **uma requisição, uma resposta completa**. Não há `EventSource`, `ReadableStream`, `getReader()` nem consumo de `text/event-stream`.
- Existe `AbortController` bem implementado (cancelamento em troca de conversa, linha ~355: *"Phase 2.5 — AbortController contract on context switch"*).
- O comentário na linha 357 fala em *"request or typewriter is mid-flight"*, e há telemetria `ai.streaming.cancelled` (linha 363).
- Não há `ActionController::Live` em `app/`, `enterprise/` ou `lib/`. Não há rota de stream em `config/routes.rb`.

**Conclusão:** o "streaming" atual é **efeito máquina-de-escrever no cliente sobre uma resposta já completa**. O agente espera o tempo inteiro de geração olhando um loader, e só então o texto aparece letra a letra — o que, ironicamente, **adiciona** latência percebida ao final. `[opinião minha]` Isso é o maior ganho isolado disponível na reescrita: streaming real corta a espera percebida sem tocar no modelo.

### 2.2 SSE vs WebSocket vs long-polling

| Critério | SSE | WebSocket | Long-polling |
|---|---|---|---|
| Direção | servidor → cliente | bidirecional | servidor → cliente (simulado) |
| Ordem dos chunks | garantida (mesma conexão TCP/HTTP) | garantida no socket, **não** no ActionCable (§2.3) | garantida |
| Reconexão | **nativa** no browser (`EventSource` + `Last-Event-ID`) | manual | manual |
| Proxy/CDN | amigável (é HTTP) | precisa de Upgrade | trivial |
| Custo por conexão | 1 thread/conexão em Rails (§2.7) | 1 conexão persistente | requisições repetidas |
| Usado pelas APIs de LLM | **sim** (OpenAI, Anthropic) | não | não |

Consenso das fontes: *"For the common 2026 case — streaming AI completions — SSE is almost always the right call, which is why every major LLM API ships it"* ([BuildMVPFast](https://www.buildmvpfast.com/blog/streaming-llm-responses-sse-vs-websockets-2026), [Hivenet](https://www.hivenet.com/post/llm-streaming-sse-websockets), [GetStream](https://getstream.io/blog/websocket-sse/)).

Fonte primária: a API da Anthropic usa SSE com tipos de evento nomeados — `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`, e cada content block carrega um **índice** ([docs.anthropic.com](https://docs.anthropic.com/en/api/messages-streaming)). Ou seja, o próprio provedor já entrega ordenação explícita; você só precisa não perdê-la no caminho.

### 2.3 Por que o ActionCable já existente **não** resolve isso

Essa é a pergunta central da task, e a resposta é contraintuitiva: **ter ActionCable não muda a recomendação — piora o caso do WebSocket.**

- **Sem número de série.** *"each message published does not have a serial number so it is impossible for the receiving end to ensure that it processes messages in order"* ([Ably](https://ably.com/blog/rails-actioncable-the-good-and-the-bad)).
- **At-most-once.** Chunks perdidos numa desconexão **não são recuperáveis**; o servidor não guarda histórico efêmero.
- **A "maldição das threads".** O pool de threads do ActionCable distribui broadcasts em paralelo, então sob carga a ordem embaralha. A Evil Martians demonstrou isso especificamente com LLM streaming e observou que *throttling* de 100ms **não é suficiente** sob carga, e que o **Solid Cable** (adapter de banco) produziu artefatos visuais com mais frequência que o Redis ([Evil Martians](https://evilmartians.com/chronicles/anycable-rails-and-the-pitfalls-of-llm-streaming)).
- Nenhuma das mitigações propostas dá garantia de 100% de ordem enquanto o pool de threads existir.

Mitigações que existem, se por algum motivo o WebSocket for obrigatório: AnyCable (log de publicações em Redis Streams + posição por mensagem + *at-least-once* com reordenação), `actioncable-next` com *fastlane mode*, ou emular *at-least-once* **enviando o texto acumulado em vez de chunks** (isto é, mandar o snapshot completo a cada broadcast — resolve ordem por idempotência, ao custo de banda O(n²)).

### 2.4 Recomendação

**Recomendação primária: SSE dedicado, com o trabalho desacoplado da conexão.**

```
Vue (EventSource / fetch+ReadableStream)
   │  GET /api/v1/.../copilot/stream?stream_id=...
   ▼
Rails endpoint SSE (ActionController::Live)  ── lê ──►  Redis Stream (buffer de chunks, TTL)
                                                              ▲
                                                              │ escreve chunks numerados
                                              Sidekiq job ────┘  (chama o LLM com stream:true)
```

Por que assim:

- **A geração não morre se o agente fechar a aba.** É a recomendação explícita da Ably: *"The generation runs in its own process or service (e.g. an API worker or background job) that isn't directly tethered to the client's connection"* ([Ably](https://ably.com/blog/token-streaming-for-ai-ux)).
- **Ordem garantida de graça** — chunks chegam numerados do Redis Stream e trafegam numa única conexão HTTP.
- **Reconexão nativa**: `EventSource` reconecta sozinho e reenvia `Last-Event-ID`; o servidor retoma do offset. Isso é exatamente o que a Ably lista como os 4 requisitos: conexão persistente, buffer server-side com TTL, session tracking com ID estável, e ordem + dedup por identificador de sequência.
- **A infra da frota já aceita.** `deployment/nginx_chatwoot.conf` tem `proxy_buffering off` (linha 51) e `proxy_read_timeout 900s` (linha 45) **no server block**, valendo para `/api/` e `/`. Sem mudança de nginx.
- **ActionCable continua útil** — mas para o que ele faz bem: avisar *"a geração terminou / falhou / foi cancelada"*, notificar outras abas do mesmo agente, atualizar contadores. Eventos discretos, não fluxo.

**Referência de implementação madura:** o padrão do Vercel AI SDK (`resumable-stream` + Redis) — o servidor gera um `streamId`, grava o stream SSE no Redis e salva `activeStreamId` no banco; ao remontar, o cliente faz `GET /api/chat/[id]/stream` e o servidor re-ataca no offset atual, retornando **204** se não houver stream ativo ([AI SDK docs](https://ai-sdk.dev/docs/ai-sdk-ui/chatbot-resume-streams)). Um único *drain loop* lê da origem e escreve simultaneamente no cliente **e** no Redis, então se o cliente cair os chunks continuam sendo persistidos. Ver também [LibreChat resumable streams](https://www.librechat.ai/docs/features/resumable_streams) e [zirkelc/ai-resumable-stream](https://github.com/zirkelc/ai-resumable-stream).

**Plano B (se não puder pagar as threads):** ActionCable + numeração de sequência própria no payload + buffer Redis + endpoint REST de *replay* a partir do último `seq` recebido. Funciona, mas é reimplementar à mão o que o SSE dá pronto. `[opinião minha]` só faria isso se o dimensionamento de Puma (§2.7) se provasse inviável na frota.

### 2.5 Reconexão, mensagem parcial, cancelamento, ordem

| Problema | Tratamento |
|---|---|
| **Ordem** | chunks numerados na origem (Redis Stream dá o ID); cliente descarta `seq <= último visto` |
| **Reconexão** | `EventSource` reconecta sozinho; enviar `id:` em cada evento SSE e retomar por `Last-Event-ID` |
| **Mensagem parcial** | persistir o acumulado a cada N chunks; no `stopped`, **preservar o parcial** com "Continuar"/"Regenerar" (não descartar) |
| **Cancelamento** | `AbortController` no cliente (já existe no repo) **+ propagar até a chamada do LLM** para não pagar tokens desperdiçados — o Prompt Bench é explícito sobre isso |
| **Timeout de proxy** | mandar heartbeat/comentário SSE (`: keep-alive\n\n`) periódico; o `proxy_read_timeout 900s` já é folgado |
| **Duas abas do mesmo agente** | vários clientes podem consumir o mesmo stream do buffer; limpar `activeStreamId` ao iniciar novo stream (race documentada pelo AI SDK) |

### 2.6 O que fazer quando o agente sai da tela no meio da geração

Aqui existe uma decisão de produto, não só técnica. O AI SDK trata **abort do cliente como desconexão, não cancelamento** — fechar aba, dar reload ou chamar `stop()` só fecha o HTTP; **o trabalho continua no servidor**. Isso permite retomar depois, mas cria o problema oposto: sem endpoint explícito de stop, o modelo segue gerando (e cobrando). A doc avisa: *"Não chame o endpoint de stop em código de limpeza de rota"* — só em ação explícita do usuário.

`[opinião minha]` Para o Captain, a regra certa é:

- **Trocou de conversa** → cancela de verdade (aborta e para o LLM). É o que o repo já faz hoje e está correto: aquele rascunho perdeu o contexto.
- **Fechou a aba / reload / trocou de aba do navegador** → **não cancela**; a geração termina no Sidekiq, grava o resultado, e ao voltar o rascunho está lá esperando. É a diferença entre uma ferramenta que respeita o tempo do agente e uma que castiga quem se distraiu.
- **Clicou em "Parar"** → cancela de verdade e **preserva o parcial**.

### 2.7 A restrição que ninguém vê chegando: threads do Puma

`config/puma.rb` no repo:

```ruby
max_threads_count = ENV.fetch('RAILS_MAX_THREADS', 5)
workers ENV.fetch('WEB_CONCURRENCY', 0)
```

**Cada conexão SSE segura uma thread do Puma pelo tempo inteiro da geração.** Com o default de 5 threads e `WEB_CONCURRENCY=0` (single process), **5 agentes gerando ao mesmo tempo derrubam o dashboard inteiro** — não sobra thread para servir requisição normal. Isso é confirmado como limitação estrutural: *"If you specify workers 1; threads 2 2 [...] the server can only handle 2 concurrent requests at any one time"* ([puma#1009](https://github.com/puma/puma/issues/1009)), e *"handling SSE requires some adjustments [...] needing another server to manage the streaming requests or using a multithreaded server"* ([mooreniemi](https://mooreniemi.github.io/rails/web/2016/09/04/rails-sse.html)).

`[opinião minha]` Mitigações, em ordem de preferência:

1. **Subir `WEB_CONCURRENCY` e `RAILS_MAX_THREADS`** nas VMs da frota antes de ligar o streaming. A thread SSE fica quase toda em I/O (lendo do Redis), então threads são baratas aqui; o gargalo é contagem, não CPU. Fazer a conta por conta: pico de agentes gerando simultaneamente × margem.
2. **Endpoint SSE num processo Puma dedicado** (porta separada, upstream nginx próprio), isolando o risco do dashboard.
3. Manter a geração **sempre** no Sidekiq — a thread web nunca deve esperar o LLM diretamente.

Sem esse ajuste, ligar streaming em produção troca uma latência ruim por uma indisponibilidade.

### 2.8 Render incremental no Vue

Ver §1.2 para as armadilhas de markdown. Especificamente para Vue: [markstream-vue](https://markstream-vue-docs.simonhe.me/guide/ai-chat-streaming) é uma referência direta de renderizador markdown streaming-aware. Regras mínimas: debounce 50–100ms, keys estáveis por bloco, fence aberto renderizado como bloco.

---

## 3. Padrões de confiança

### 3.1 Citação de fonte — o que funciona e o que atrapalha

A NN/g é a fonte mais dura aqui ([Explainable AI](https://www.nngroup.com/articles/explainable-ai/)):

- **Colocar a fonte junto da afirmação que ela sustenta**, não numa lista no rodapé.
- **Rótulos significativos** (nome da publicação, título do artigo) — não "[1]".
- **Linkar para a parte relevante** da fonte, reduzindo o esforço de verificação.
- Alerta: *"Citations are often hallucinated and point to nonexistent URLs."* Em RAG interno isso é evitável — a citação deve apontar para um `document_id` real do índice, não ser gerada pelo modelo como texto livre.

Densidade de citação como referência de mercado ([Whitehat](https://whitehat-seo.co.uk/blog/ai-engines-comparison-citations)): Perplexity ~21,87 citações por resposta (inline, por afirmação, + painel de fontes visível por padrão); ChatGPT ~7,92; Gemini ~8,34. Claude cita inline mas sem painel de fontes.

`[opinião minha]` Para o Captain, o modelo do Perplexity (inline, por afirmação, clicável, com preview no hover) é o correto — porque o agente precisa **verificar antes de mandar para o cliente**, e verificar precisa ser mais rápido que reescrever. O Intercom já faz isso: hover na fonte mostra um resumo curto, clique abre a fonte inteira no painel lateral, e fonte interna vem **marcada em amarelo com símbolo "internal"** para o agente saber que aquele conteúdo não pode ser citado ao cliente ([Intercom](https://www.intercom.com/help/en/articles/8587194-how-to-use-copilot)). Esse detalhe de "interno vs público" é obrigatório num produto de atendimento.

### 3.2 Não mostre "raciocínio" como explicação

Contraintuitivo e importante: a NN/g recomenda **evitar** o padrão de raciocínio passo a passo como mecanismo de explicabilidade, porque *"explanations are often unfaithful to the model's actual computation"* — são racionalizações geradas depois do fato, e promovem confiança enganosa.

`[opinião minha]` Isso não significa esconder a caixa de "pensando". Significa que a caixa de raciocínio é **feedback de progresso**, não prova de correção — e não deve ser vendida ao agente como "veja por que a resposta está certa". O que prova correção é a fonte. O repo já tem `CopilotThinkingBlock.vue` e `CopilotThinkingGroup.vue`; mantê-los colapsados por padrão está alinhado com a pesquisa.

### 3.3 Transparência de ferramenta

Mostrar "consultei o pedido #123" é o padrão que separa assistente de brinquedo, e é para onde as plataformas foram: o Chatwoot lançou **Captain Custom Tools** em 03/04/2026 — *"Captain can now call external APIs during a conversation [...] This helps answer questions like warranty checks, order lookups, or service availability instantly, without involving an agent"* ([Chatwoot](https://www.chatwoot.com/blog/captain-custom-tools)). O contraste com o estado anterior é o exemplo da crítica do eesel: perguntado "onde está meu pedido?", uma IA limitada aponta para a página de login; uma IA com ferramenta responde *"Seu pedido #1234 está a caminho e deve chegar sexta-feira"* ([eesel](https://www.eesel.ai/blog/chatwoot-captain)).

### 3.4 Controle: parar, refazer, corrigir o rumo

Já coberto em §1.5 e §1.9. O ponto de pesquisa é que **iteração é a norma, não a exceção**: a NN/g observou que *"users almost always engage in multistep iteration because the AI doesn't deliver exactly what the user wants — it can only guess at the intent"*. Projetar assumindo acerto de primeira é projetar errado.

### 3.5 Memória e contexto

O Chatwoot já tem "Captain Memories" (detalhes importantes retidos entre conversas). O requisito de confiança é: **o usuário precisa ver e editar o que a IA lembra**. `[opinião minha]` Memória invisível é a forma mais rápida de perder a confiança do agente — quando a IA erra citando algo que "lembrou" e o agente não consegue achar onde aquilo está guardado, a ferramenta vira suspeita. Vale também um ponto de LGPD: o repo já tem `docs/copilot-lgpd-retention.md`, então há precedente interno para tratar retenção explicitamente.

### 3.6 Erro e "não sei"

Padrões consolidados:

- **Refusal behavior**: deixar o modelo dizer "não sei" quando não há evidência. *"The single most valuable behavior an AI agent can have is knowing when to stop."*
- **Threshold de confiança** com escalonamento — um caso real citado subiu o corte de 0.6 para 0.75 ([Fini](https://www.usefini.com/guides/ai-support-platforms-accuracy-hallucination-guardrails), [Lorikeet](https://www.lorikeetcx.ai/articles/how-ai-support-prevents-hallucinations-regulated-2026)).
- **Guardrail de saída**: uma segunda camada inspeciona o rascunho antes de sair, conferindo contra política e contra a evidência recuperada.
- **Erro específico, não genérico**: a mensagem de erro precisa dizer o que houve e o que fazer.

---

## 4. Benchmark: plataformas de atendimento

### 4.1 Tabela comparativa

| Plataforma | IA responde ao cliente? | IA sugere ao agente? | Como o agente aceita/edita | Cita fonte? | Respostas prontas (macros) |
|---|---|---|---|---|---|
| **[Intercom Fin + Copilot](https://www.intercom.com/help/en/articles/8587194-how-to-use-copilot)** | Sim (Fin, autônomo) | Sim (Copilot, aba lateral) | "Add to composer", ou "Add to composer & modify" (More friendly / More formal / Rephrase / Translate); edita no composer antes de enviar | **Sim** — fontes listadas abaixo da resposta, resumo no hover, fonte interna marcada em amarelo | **Mantidas.** Copilot **sugere macros** no composer |
| **[Zendesk Agent Copilot](https://support.zendesk.com/hc/en-us/articles/7908817636378-About-agent-copilot)** | Sim (AI agents) | Sim (suggested first replies, auto assist, next actions) | Agente revisa antes de enviar; auto assist executa apenas **ações aprovadas pelo agente** | Sim (macros + artigos do help center) | **Mantidas e potencializadas.** Primeira resposta é gerada *"based on existing macros and help center articles"*; **macros sugeridas com indicador de confiança** |
| **[Freshdesk Freddy Copilot](https://www.eesel.ai/blog/freddy-ai-reply-suggester)** | Sim (AI Agent separado) | Sim (Reply Suggester) | Sugestão aparece como **ghost text cinza** no campo de resposta; ponto vermelho no botão Reply sinaliza que há sugestão. **Humano sempre envia** | **Sim** — cita os artigos-fonte para o agente validar | Mantidas |
| **[Crisp MagicReply](https://www.success.ai/ai-tools/crisp-magicreply)** | Não (é agent-assist) | Sim | Sugestão baseada em conversas anteriores | Não documentado | Mantidas |
| **[Tidio Lyro + Copilot](https://www.tidio.com/ai-agent/)** | **Sim** (Lyro resolve até ~70% sozinho) | Sim (Copilot, produto separado) | Copilot sugere ao agente; Lyro responde direto e faz handoff | Baseado em KB | Mantidas |
| **[Chatwoot Captain](https://www.chatwoot.com/hc/user-guide/en/categories/captain)** (upstream) | Sim (Captain Assistant, por inbox) | Sim (Copilot, aba lateral + dentro do editor desde 02/2026) | Aba Copilot: botão **"Use this"** insere na janela de mensagem. No editor: reply suggestions, improve, change tone, fix grammar, summarize, ask copilot | Parcial (usa documentos, mas atribuição menos explícita que Intercom) | Mantidas (canned responses do Chatwoot seguem existindo) |

### 4.2 Modelo mental: são dois produtos, não um

Fica claro no benchmark que todos separam:

- **IA autônoma** (Fin, Lyro, Zendesk AI agents, Captain Assistant) → atua **antes** do humano, resolve ou qualifica, faz handoff.
- **Copiloto** (Copilot, Freddy, MagicReply, Captain Copilot) → atua **junto** do humano, nunca envia sozinho.

O que compartilham é a base de conhecimento e as ferramentas. `[opinião minha]` A reescrita do Captain deve assumir isso explicitamente na arquitetura: mesma base, mesmas tools, duas superfícies com contratos de UX diferentes. Misturar os dois numa interface só é a origem de metade da confusão que os usuários relatam.

### 4.3 A trajetória do próprio Chatwoot (relevante — é o upstream)

| Data | Mudança | Fonte |
|---|---|---|
| 20/02/2026 | **Captain dentro do editor de resposta.** *"Captain is now built into the reply box. You no longer need to switch to a separate panel to get AI help. It works where you're already typing."* Ações: reply suggestions, improve, change tone (professional/casual/direct/friendly), fix grammar, summarize, ask copilot. Substituiu a integração antiga com OpenAI por backend próprio. Permite **refinar antes de inserir** ("deixa mais curto") | [Chatwoot](https://www.chatwoot.com/blog/captain-inside-the-reply-editor/) |
| 03/04/2026 | **Custom Tools** — chamadas a APIs externas durante a conversa. Também: auto-resolve de mensagens sem intenção, e *"Improved hand-off behavior: We refined the hand-off prompt so Captain is less likely to escalate"* | [Chatwoot](https://www.chatwoot.com/blog/captain-custom-tools) |
| 01/06/2026 | Captain Documents mantidos atualizados automaticamente | [Chatwoot changelog](https://www.chatwoot.com/changelog) |

Críticas documentadas ao Captain upstream ([eesel](https://www.eesel.ai/blog/chatwoot-captain)):

1. **Fontes limitadas** — help center, conversas passadas e PDFs. O conhecimento vivo está em Google Docs/Confluence/Slack.
2. **Sem teste antes de ligar** — há playground de instruções, mas *"não há uma forma robusta de simular seu desempenho contra milhares de suas perguntas reais"*; na prática *"você basicamente tem que ligar o interruptor e cruzar os dedos"*.
3. **Preço por resposta** com estouro caro (add-on de US$ 200/mês até 10.000 respostas).

`[opinião minha]` O item 2 é o mais aproveitável: um **modo de avaliação offline** (rodar N perguntas reais históricas contra a configuração nova e comparar com o que o agente humano respondeu) é diferencial competitivo e é barato de construir sobre dados que já existem no banco. Já existe base para isso no repo (eval nativo do Captain deployado na frota em 08/07).

### 4.4 Respostas prontas → IA *(decisão já tomada; esta seção vira registro de risco)*

> **Status:** o Walisson decidiu **aposentar** as respostas prontas — a IA escreve do zero e o
> acervo atual vira base de conhecimento. Ele escolheu a opção mais ousada ciente do risco.
> Mantenho o material abaixo **não para rediscutir**, mas porque ele nomeia exatamente quais
> riscos a decisão assume e, portanto, o que a implementação precisa mitigar.
>
> **O que mitigar, dado que a decisão está tomada:**
> 1. **Latência** — canned response era 0ms. Toda saudação/confirmação agora custa segundos.
>    Mitigação: cache de respostas frequentes, TTFT agressivo (§5.1), e streaming real (§2).
> 2. **Literalidade jurídica** — texto de política/prazo/valor precisa sair exato.
>    Mitigação: esses trechos vêm de fonte determinística (documento/API), nunca gerados livremente.
> 3. **Migração do acervo** — o acervo de respostas prontas precisa entrar como base de
>    conhecimento **antes** de desligar o atalho, senão a IA perde a fonte junto com o atalho.

**Ninguém do benchmark eliminou as respostas prontas. Todos fundiram com a IA.** O padrão convergente é:

1. A IA **escolhe** o template certo (Zendesk: macros sugeridas **com nível de confiança**; Intercom: Copilot sugere macros no composer).
2. A IA **preenche** o template com os dados reais daquele cliente/pedido (via tools).
3. A IA **reescreve** tom e forma sob demanda do agente.

Os argumentos a favor de matar o template puro, com números — todos de fonte comercial (vendedor de IA), então tratar como **indicativo, não como dado científico** ([eesel](https://www.eesel.ai/blog/canned-responses)):

- 30–60 segundos por ticket só procurando o template certo.
- ~30% de escolha errada de canned response.
- 61% dos times têm backlog de macros e artigos desatualizados.

E o argumento a favor de **manter**, esse com pesquisa de verdade por trás — NN/g, diretriz 18 de atendimento: *"a lot of canned responses raise suspicion and make people believe that the agent is a bot"*; e diretriz 19: quando é resposta pronta, ela precisa ser **instantânea**, porque o cliente percebe quando demora ([NN/g, chat UX](https://www.nngroup.com/articles/chat-ux/)).

`[opinião minha] — resposta direta ao pedido do Walisson:`

Trocar resposta pronta por IA é a direção certa, **mas não como substituição de uma por outra.** O que quebra:

- **Latência.** Canned response é instantânea (0ms, atalho `/`). Geração de IA leva segundos. Numa saudação ou num "vou verificar e já volto", a IA é objetivamente **pior** — mais lenta, mais cara, e sem ganho nenhum de qualidade. A diretriz 19 da NN/g diz que resposta comum precisa ser instantânea.
- **Previsibilidade jurídica.** Texto de política, prazo, garantia, valor e cancelamento tem que ser **literal e auditável**. É exatamente onde a alucinação custa caro (§5.3, caso Air Canada).
- **Confiança do agente.** Se a IA erra o template três vezes, o agente volta pro `/` e nunca mais olha.

O desenho que eu recomendo:

| Tipo de resposta | Quem resolve |
|---|---|
| Saudação, "um momento", encerramento, texto de política/prazo/valor | **Canned response literal**, instantânea, atalho `/` mantido |
| Escolher **qual** canned response cabe aqui | **IA**, sugerindo top-3 com indicador de confiança (padrão Zendesk) |
| Preencher variáveis com dados reais (pedido, prazo, nome) | **IA + tools** |
| Resposta específica que nenhum template cobre | **IA gerando do zero, com citação de fonte** |
| Ajustar tom / encurtar / traduzir o que já está escrito | **IA sobre a seleção** (§1.9) |

Assim a resposta pronta deixa de ser um texto que o agente caça e vira um **bloco que a IA monta**. O agente ganha velocidade sem perder o literal onde o literal importa. E — ponto operacional — a biblioteca de canned responses vira dado de treino/recuperação da IA em vez de virar dívida morta.

### 4.5 Adoção: o que a pesquisa diz que mata o copiloto

- *"Agents will learn to ignore Copilot suggestions within the first week, killing adoption permanently"* se a qualidade não estiver lá ([Assembled](https://www.assembled.com/page/contact-center-ai-copilot)).
- Bloqueadores principais, em ordem: **qualidade da base de conhecimento** (o número um), encaixe no fluxo de trabalho, **baixa transparência de fonte**, governança ausente. *"Knowledge base quality is the single most important prerequisite."*
- *"Top-down AI deployments without agent input fail consistently."* Incluir agentes de frente no piloto e no feedback.

Ganhos reportados (todos de fonte comercial — tratar como ordem de grandeza): −38% de AHT num case ([CustomerScience](https://customerscience.com.au/customer-experience-2/ai-copilot-support-agents/)); +14–15% de issues resolvidos por hora num deployment randomizado com 5.000+ agentes; Intercom afirma +31% de conversas fechadas por dia com Copilot ([Intercom](https://www.intercom.com/helpdesk/copilot)).

---

## 5. Riscos e limites

### 5.1 Latência — quanto o agente tolera

Os limiares clássicos de resposta ainda valem: **0,1s** parece instantâneo; **1s** mantém o fluxo de pensamento; **10s** perde a atenção ([Redis](https://redis.io/blog/ttft-meaning/)).

Para chat streamado, as metas praticadas:

| TTFT (time to first token) | Percepção |
|---|---|
| < 300ms (P99) | fluido, o usuário já começa a ler |
| < 500ms | responsivo, ninguém registra a espera |
| 500ms – 1s | aceitável **se houver indicador de carregamento claro** |
| > 3s | streaming não salva — tela em branco e depois um jorro |

Ponto crucial: *"streaming only masks latency **after** the first token arrives"*. Streaming não conserta TTFT ruim.

`[opinião minha]` No atendimento o orçamento é mais apertado que no ChatGPT, porque há um cliente do outro lado esperando o agente. A regra prática que eu adotaria: **se o Captain não começar a escrever em ~1s, o agente vai desistir e digitar sozinho.** Isso empurra decisões de arquitetura: prompt caching (§5.2), recuperação de contexto enxuta, modelo mais rápido para as ações mecânicas (corrigir gramática, mudar tom) e modelo mais forte só para gerar resposta do zero.

### 5.2 Custo por conversa

Ordens de grandeza ([Inference.net](https://inference.net/content/llm-api-pricing-comparison/), [DevToolLab](https://devtoollab.com/blog/prompt-caching-guide)):

- Conversa de suporte típica: 5–10 turnos, 500–2.000 tokens de contexto acumulado por turno → **10.000–30.000 tokens de entrada por conversa**.
- Pipeline RAG típico: 5–10 chunks de ~500 tokens + query + system prompt → 5.000–10.000 tokens de entrada por consulta.
- **Prompt caching é a otimização de maior retorno**: 80–90% de redução no custo do contexto repetido. Exemplo citado: system prompt + documentos de 8k tokens repetidos a cada mensagem custam ~US$ 24 por milhão de mensagens sem cache e ~US$ 0,30 com cache.

Referência de mercado para precificação ao cliente final: Fin cobra **US$ 0,99 por outcome** (resolução, handoff de procedure ou desqualificação), com base de US$ 49/mês incluindo 50 resoluções; Zendesk fica em ~US$ 1,50 por resolução automatizada em plano comprometido, ~US$ 2,00 pay-as-you-go ([Featurebase](https://www.featurebase.app/blog/fin-ai-pricing), [Macha](https://www.getmacha.com/blog/intercom-fin-vs-zendesk-ai-pricing)).

`[opinião minha]` O copiloto tem economia diferente da IA autônoma: ele é chamado **muitas vezes por conversa** (sugerir, melhorar, mudar tom, resumir) e cada chamada é curta. O risco de custo aqui não é a resposta cara, é o volume de chamadas triviais. Duas defesas: cache agressivo do system prompt + contexto da conversa, e roteamento de modelo por ação (gramática e tom não precisam do modelo topo de linha).

### 5.3 Alucinação em contexto de suporte

**Precedente jurídico:** *Moffatt v. Air Canada*, 2024 BCCRT 149 (Civil Resolution Tribunal, Colúmbia Britânica, fev/2024). O chatbot informou que a tarifa de luto poderia ser pedida retroativamente; a companhia negou depois. O tribunal caracterizou como **negligent misrepresentation** e condenou a Air Canada a CAD 812,02. A defesa — de que o chatbot seria entidade legal responsável por si — foi rejeitada com a frase que virou citação: *"In effect, Air Canada suggests the chatbot is a separate legal entity that is responsible for its own actions. This is a remarkable submission."* ([ABA](https://www.americanbar.org/groups/business_law/resources/business-law-today/2024-february/bc-tribunal-confirms-companies-remain-liable-information-provided-ai-chatbot/), [Forbes](https://www.forbes.com/sites/marisagarcia/2024/02/19/what-air-canada-lost-in-remarkable-lying-ai-chatbot-case/), [Pinsent Masons](https://www.pinsentmasons.com/out-law/news/air-canada-chatbot-case-highlights-ai-liability-risks))

O princípio estabelecido: **a empresa é responsável pelo que sua IA diz**, independentemente de intenção ou de o modelo ter preenchido uma lacuna de conhecimento.

Camadas de defesa recomendadas (§3.6): grounding estrito em fontes aprovadas, dados numéricos vindos de API determinística (nunca do modelo), guardrail de saída que regenera resposta fora de política, threshold de confiança com escalonamento, e QA post-facto.

`[opinião minha]` No modo copiloto o risco é estruturalmente menor — há um humano entre a IA e o cliente. Mas isso só vale se **verificar for mais rápido que reescrever**. Se a citação de fonte for ruim, o agente aprova no olho e o humano vira carimbo. É por isso que §3.1 (fonte inline, clicável, com preview) não é enfeite: é o que faz o human-in-the-loop funcionar de verdade.

### 5.4 Quando a IA erra na frente do cliente

`[opinião minha]`, ancorado nos padrões acima:

1. **Rastreabilidade obrigatória.** Registrar qual sugestão foi gerada, quais fontes usou, se o agente editou ou mandou como veio. Sem isso não há pós-mortem possível, e o caso Air Canada mostra que pós-mortem pode virar peça jurídica.
2. **Marcar mensagem enviada com origem de IA** internamente (não para o cliente) — permite medir taxa de erro por template/fonte.
3. **Caminho rápido de correção**: o agente que percebe o erro precisa conseguir corrigir e sinalizar a fonte errada em um clique. É o loop que o Intercom fecha com Suggestions, aprendendo com o que foi rejeitado ([Intercom](https://www.intercom.com/help/en/articles/11394959-use-ai-powered-content-suggestions-to-improve-fin)).
4. **Nunca deixar a IA falar de valor, prazo, garantia ou política sem fonte determinística.** Isso é regra dura, não preferência.

### 5.5 Riscos específicos desta reescrita

| Risco | Por quê | Mitigação |
|---|---|---|
| Ligar SSE e derrubar o dashboard | Puma com 5 threads (§2.7) | Dimensionar `WEB_CONCURRENCY`/`RAILS_MAX_THREADS` **antes**; considerar processo dedicado |
| Usar ActionCable para chunks | ordem não garantida (§2.3) | SSE; ActionCable só para eventos discretos |
| Copiar o vazio do ChatGPT | agente sob pressão não explora (§1.1) | tela inicial com ações contextuais, não convite em branco |
| Matar canned responses | latência e literalidade jurídica (§4.4) | fundir, não substituir |
| Mostrar "raciocínio" como prova | explicações são post-hoc (§3.2) | citação de fonte é a prova; thinking fica colapsado |
| Auto-scroll agressivo | desorienta na leitura (§1.5) | modelo de 3 estados + botão "ir para o fim" |
| Anunciar cada token em `aria-live` | enxurrada para leitor de tela (§1.10) | batch ou anúncio único ao final |

---

## 6. Fronteira: copiloto × agentes de IA (mapeamento no código)

Tudo nesta seção foi lido no repo em 28/07/2026, branch `homologacao`. Cada afirmação traz
`caminho:linha`. Classificação: **[COPILOTO]** alvo da reescrita · **[AGENTES-IA]** não tocar ·
**[COMPARTILHADO]** cuidado redobrado.

### 6.1 Quantos copilotos existem? Quatro caminhos, três motores

Esta é a resposta à pergunta 4 do coordenador: **não são versões da mesma coisa, e nenhum está
totalmente morto.**

| # | Superfície (front) | Rota | Serviço backend | Motor / chave de LLM | Usa `Assistant`? | Estado |
|---|---|---|---|---|---|---|
| **A** | `components-next/copilot/CopilotPanel.vue`, montado por `components/copilot/CopilotContainer.vue:342`, montado em `routes/dashboard/Dashboard.vue:205` | `captain/copilot_threads` + `copilot_messages` (`config/routes.rb:77-78`) | `Captain::Copilot::ResponseJob` → `Captain::Copilot::ChatService` | RubyLLM via `Llm::BaseAiService`; **chave do Captain** (conta) | **SIM — forte** | **VIVO** quando a flag `ai_assistant_v2` está **OFF** |
| **B** | `components/widgets/conversation/CopilotPanel.vue` | `conversations/:id/copilot_chat` (`config/routes.rb:242`) | `Copilot::ChatService` (`app/services/copilot/chat_service.rb`) | OpenAI direto (`ruby-openai`), `gpt-4o-mini`, **chave própria** | **NÃO** | **MORTO no front, VIVO na API** |
| **C** | ghost text no `ReplyBox.vue:2316,2953` | `conversations/:id/ghost_suggestion` | `Copilot::GhostSuggestionService` | OpenAI direto, `max_tokens: 80`, **chave própria** | **NÃO** | **VIVO** |
| **D** | ações inline do editor (`useCopilotReply` → `useCaptain`) **e** `components-next/ai-assistant/AIAssistantPanel.vue` | `captain/tasks/{rewrite,summarize,reply_suggestion,label_suggestion,follow_up,sentiment_analysis}` (`config/routes.rb:86`) | `Captain::{Rewrite,Summary,ReplySuggestion,…}Service` + `Enterprise::Captain::BaseTaskService` | Captain task services | **`reply_suggestion` SIM** (RAG); os outros não | **VIVO** |

**Sobre o B (`copilot_chat`):** o componente que o consumia foi removido — há inclusive o
comentário `// CopilotPanel.vue removido — CopilotContainer (Dashboard.vue) já renderiza` em
`components/widgets/conversation/ConversationBox.vue:4`, e nenhum arquivo importa
`widgets/conversation/CopilotPanel.vue`. **Mas as três rotas (`create`/`show`/`destroy`)
continuam expostas e funcionais**, com prompt em pt-BR hardcoded e chave de API própria.
`[opinião minha]` É código morto com superfície de API viva — candidato natural a remoção na
reescrita, mas **verifique antes se alguma automação/integração externa chama esse endpoint**,
porque ele responde 200 hoje.

**Sobre o D e o painel v2:** `AIAssistantPanel.vue` importa `useCaptain`
(`components-next/ai-assistant/AIAssistantPanel.vue:16`) e **não** importa nada de
`copilotThreads`/`copilotMessages`. O `Dashboard.vue:200-205` faz o mutex explícito:

```
<AIAssistantPanel v-if="aiAssistantFlag" ... />
<CopilotContainer v-else />
```

A flag resolve por `sessionStorage` → `localStorage` → feature flag de servidor `ai_assistant_v2`
→ **default OFF** (`components-next/ai-assistant/composables/useAIAssistantFlag.js:26-38`).
Nota do próprio código: os overrides de cliente têm precedência *"e.g. flag bit position is past
the bigint column capacity in the current schema"* — que é o problema de bitmask cheio já conhecido.

`[opinião minha]` **Isso é a descoberta mais importante para o plano de reescrita.** O caminho v2
já existente troca um motor com 33 tools + thread persistida + RAG por um motor de tasks sem
tools e sem thread. Se a reescrita partir do v2 achando que é "o novo copiloto", ela herda uma
regressão de capacidade que ninguém decidiu conscientemente. A pergunta a levar ao Walisson é:
**a tela nova deve ter tools ou não?** Se sim, o motor único da fase 1+2 tem que ser o A, não o D.

### 6.2 O vínculo `CopilotThread → Captain::Assistant`

**[COMPARTILHADO — o ponto de contato principal]**

```ruby
# enterprise/app/models/copilot_thread.rb:23
belongs_to :assistant, class_name: 'Captain::Assistant'
```

- `db/schema.rb:1010` — `assistant_id` é `integer`, **nullable no banco**, mas o `belongs_to`
  **é obrigatório no Rails** (validação de presença por padrão). Divergência banco↔model:
  registros antigos podem ter `assistant_id` nulo e **falhariam ao salvar** hoje.
- `enterprise/app/controllers/api/v1/accounts/captain/copilot_threads_controller.rb:51`:
  ```ruby
  Current.account.captain_assistants.find(copilot_thread_params[:assistant_id])
  ```
  Usa **`find`, não `find_by`** → `RecordNotFound` (500/404) se o `assistant_id` vier errado ou
  se o assistente tiver sido apagado. **O front é obrigado a escolher um assistente para abrir
  qualquer thread de copiloto.**

**Consequência direta:** apagar um agente de IA quebra o copiloto para as threads que apontavam
para ele. `[opinião minha]` Isso já é um bug latente hoje, independente da reescrita.

### 6.3 Para que exatamente o copiloto usa o assistente?

Resposta à pergunta 1 do coordenador. São **cinco usos distintos**, todos em
`enterprise/app/services/captain/copilot/chat_service.rb`:

| # | Uso | Linha | Classificação |
|---|---|---|---|
| 1 | **Persona/prompt** — `Captain::Llm::SystemPromptsService.copilot_response_generator(@assistant.config['product_name'], tools_summary, @assistant.config)` — o **config inteiro** do agente de IA alimenta o system prompt do copiloto | `:114-118` | **[COMPARTILHADO]** |
| 2 | **Conta** — `super(account: assistant.account)`; o assistente é quem define a conta, e daí a chave de LLM | `:7,9-10` | **[COMPARTILHADO]** |
| 3 | **Tools** — as 33 tools nativas recebem o assistente no construtor: `klass.new(@assistant, user: @user)`; as custom tools também: `custom_tool.tool(@assistant)` | `:99,102-103` | **[COMPARTILHADO]** |
| 4 | **RAG / conhecimento** — `Captain::Tools::SearchDocumentationService` faz `assistant.responses.approved.search(...)`, ou seja lê as **FAQs do agente de IA** (`enterprise/app/services/captain/tools/search_documentation_service.rb:16`) | `:64` | **[COMPARTILHADO — leitura]** |
| 5 | **Temperatura** — `@assistant&.config&.[]('temperature')` (`enterprise/app/helpers/captain/chat_helper.rb:99`) | — | **[COMPARTILHADO]** |

O **modelo** não vem do assistente diretamente aqui — vem de `Llm::BaseAiService` (`@model`),
mas a chave de API é a do Captain da conta (erro `Llm::Config::MissingAccountApiKeyError` tratado
em `enterprise/app/jobs/captain/copilot/response_job.rb:25`).

Em resumo: **o copiloto consome o assistente como persona + conhecimento + contexto de tools.**
Não é um sistema separado que por acaso referencia o assistente; ele é construído em cima dele.

**Fora do motor A**, há mais um ponto de contato:
`enterprise/lib/enterprise/captain/reply_suggestion_service.rb:21` resolve o assistente por
`conversation&.assignee_agent_bot&.captain_assistant || conversation&.inbox&.captain_assistants&.first`
e monta `Captain::Tools::SearchReplyDocumentationService`. Ou seja, **a sugestão de resposta do
editor depende do vínculo inbox↔assistente dos agentes de IA**. Se ninguém tiver assistente na
inbox, a sugestão perde o RAG silenciosamente (cai no `super` sem tool).

### 6.4 A cota compartilhada — o risco de produção nº 1

**[COMPARTILHADO — crítico]**

`account.increment_response_usage` é chamado por **quatro** lugares:

| Chamador | Caminho:linha | Quem é |
|---|---|---|
| Copiloto (motor A) | `enterprise/app/services/captain/copilot/chat_service.rb:31` | **[COPILOTO]** |
| Tasks (motor D) | `enterprise/lib/enterprise/captain/base_task_service.rb:30` | **[COPILOTO]** |
| Atendimento automático ao cliente | `enterprise/app/jobs/captain/conversation/response_builder_job.rb:62` | **[AGENTES-IA]** |
| Transcrição de áudio | `enterprise/app/services/messages/audio_transcription_service.rb:112` | outro |

E o **bloqueio** por cota atinge os dois lados:

```ruby
# enterprise/lib/enterprise/captain/base_task_service.rb:3
return { error: I18n.t('captain.copilot_limit'), error_code: 429 } unless responses_available?
```
```ruby
# enterprise/app/controllers/.../copilot_threads_controller.rb:36-43
if Current.account.usage_limits[:captain][:responses][:current_available].positive?
  copilot_message.enqueue_response_job(...)
else
  # cria mensagem "captain.copilot_limit" em vez de responder
end
```

**Consequência:** o copiloto e o atendimento ao cliente bebem do mesmo balde. Uma reescrita que
aumente o uso do copiloto (streaming, mais chamadas por conversa, mais tools) **consome cota que
hoje sustenta o atendimento automático em produção**.

`[opinião minha]` Isso precisa de decisão explícita antes de a fase 1 subir, e há três saídas:
(a) medir o consumo atual por conta e dimensionar o limite antes; (b) separar os contadores —
cota de copiloto ≠ cota de atendimento; (c) instrumentar alerta quando o copiloto passar de X%
do consumo. A opção (b) é a correta a médio prazo, mas **mexe em código compartilhado** — então
para a fase 1 eu faria (a) + (c), que não tocam na zona proibida.

### 6.5 ⚠️ O copiloto escreve no atendimento real (contradiz a premissa)

**[COMPARTILHADO — o achado mais sensível]**

Resposta à pergunta 3 do coordenador, com uma correção importante ao enunciado: **o copiloto não
escreve nas tabelas `captain_*` dos agentes de IA** — o grep não encontrou nenhuma escrita em
`captain_assistant_logs`, `captain_tool_calls` ou `captain_documents` a partir de
`enterprise/app/services/captain/copilot/`, `enterprise/app/jobs/captain/copilot/` ou
`app/services/copilot/`. Isso é boa notícia.

**Mas ele escreve em coisa pior: nas tabelas de produção do atendimento.** Das 33 tools em
`enterprise/app/services/captain/copilot/chat_service.rb:63-96`, **12 têm efeito colateral real**:

| Tool | O que faz |
|---|---|
| `SendMessageService` | **envia mensagem ao cliente** — `param :private ... (default: false)`, executa `Messages::MessageBuilder.new(nil, conversation, params).perform` |
| `SendTemplateService` | envia template (WhatsApp) |
| `ResolveConversationService` | resolve a conversa |
| `AssignConversationService` | atribui a agente |
| `TransferToInboxService` | transfere de caixa |
| `SnoozeConversationService` | adia |
| `ChangeStatusService` / `ChangePriorityService` | muda status/prioridade |
| `AddLabelService` / `RemoveLabelService` | mexe em labels |
| `UpdateContactService` / `SetCustomAttributesService` / `AddNoteToContactService` | edita o contato |

O único portão do envio é a permissão do usuário:

```ruby
# enterprise/app/services/captain/tools/copilot/send_message_service.rb
def active?
  user_has_permission('conversation_manage')
end
```

**Não há aprovação humana da mensagem.** Se o LLM decidir chamar `send_message`, a mensagem sai
para o cliente. A premissa "o copiloto NÃO fala com o cliente: ele sugere, o humano aprova" é,
hoje, **falsa no código**.

`[opinião minha]` Esse é o item que eu levaria ao Walisson antes de qualquer linha de UI. Duas
leituras possíveis, e ele precisa escolher:
1. **É bug/risco** → a reescrita deve remover `SendMessageService`/`SendTemplateService` do
   conjunto de tools do copiloto, ou forçá-las a `private: true` (nota interna), ou colocá-las
   atrás de confirmação explícita na UI.
2. **É feature usada** → então a premissa precisa ser revista, e a UI precisa mostrar
   claramente "isto vai sair para o cliente" antes de executar.

Vale checar em produção se alguma conta já usa (buscar mensagens criadas com `sender` nulo via
`MessageBuilder` a partir de tool call). Não fiz essa consulta — está fora do meu escopo e não
toco em base de cliente.

**Uma escrita adicional, do motor B:** `copilot_chat` persiste o histórico dentro da própria
conversa —
`@conversation.additional_attributes['copilot_history'] = new_history; @conversation.save!`
(`app/controllers/api/v1/accounts/conversations/copilot_chats_controller.rb:50-51`, e o `destroy`
em `:26-28`). Isso grava na tabela `conversations`, que é produção do atendimento, e é
suscetível a race condition com outras escritas em `additional_attributes`.

### 6.6 Dá para trocar interface e motor mantendo o vínculo? Onde doeria?

Resposta à pergunta 2: **sim, dá — o vínculo é de leitura e de composição, não de escrita.**
Nada do que o copiloto faz altera o estado dos agentes de IA. Mas doeria em cinco pontos:

| # | Onde doeria | Por quê | Como reduzir a dor |
|---|---|---|---|
| 1 | **Escolha do assistente** | `belongs_to` obrigatório + `find` sem fallback (§6.2) | a UI nova precisa continuar mandando `assistant_id`; adicionar fallback (`find_by` + assistente default da conta) é mudança pequena e **no lado do copiloto**, não no dos agentes |
| 2 | **System prompt** | vem de `SystemPromptsService.copilot_response_generator`, que lê `@assistant.config` inteiro (§6.3) | **não editar** `SystemPromptsService` nem o config do assistente. Se a reescrita precisa de prompt novo, criar um método/serviço **novo** só do copiloto e deixar o antigo intacto |
| 3 | **Cota** | balde único (§6.4) | medir e dimensionar antes; instrumentar |
| 4 | **Infra de chat compartilhada** | `Llm::BaseAiService`, `Captain::ChatHelper`, `Captain::ChatResponseHelper`, `Captain::ChatGenerationRecorder` servem copiloto **e** assistente | qualquer mudança aqui (ex.: adicionar streaming) atinge os dois. **Streaming precisa entrar por baixo sem alterar o contrato atual** — ou por um caminho paralelo só do copiloto |
| 5 | **Formato de resposta** | `build_chat` força `response_format: { type: 'json_object' }` (`chat_helper.rb:27`) e `build_response` faz `JSON.parse` (`chat_response_helper.rb:9,19`) | **streaming token a token é incompatível com "espera o JSON fechar"**. Ou o copiloto ganha um caminho que streama texto puro, ou é preciso parse incremental de JSON (§2 cita `partial-json-parser` para isso). Este é o ponto técnico mais espinhoso da reescrita |

**Sobre o ponto 5 — detalhe que muda o plano:** hoje a resposta do copiloto só existe depois que
o JSON inteiro chega e é parseado. Isso explica por que o front usa máquina-de-escrever local
(§2.1): não há como streamar. Para ter streaming real **sem tocar no assistente**, o caminho
menos invasivo é dar ao copiloto um fluxo próprio de geração (texto puro streamado + tool calls
sinalizadas à parte), deixando `ChatHelper` como está para o assistente.

### 6.7 Inventário classificado

**[COPILOTO] — alvo da reescrita, mexer à vontade**

- `enterprise/app/models/copilot_thread.rb`, `copilot_message.rb` (tabelas `copilot_threads`, `copilot_messages` — exclusivas)
- `enterprise/app/services/captain/copilot/chat_service.rb`
- `enterprise/app/jobs/captain/copilot/response_job.rb`
- `enterprise/app/controllers/api/v1/accounts/captain/copilot_threads_controller.rb` (+ messages)
- `app/services/copilot/{chat_service,ghost_suggestion_service,language_detector_service,openai_settings}.rb`
- `app/controllers/api/v1/accounts/conversations/{copilot_chats,ghost_suggestions}_controller.rb`
- `app/controllers/api/v1/accounts/captain/tasks_controller.rb`
- `app/javascript/dashboard/components/copilot/`, `components-next/copilot/`, `components-next/ai-assistant/`
- `app/javascript/dashboard/store/captain/{copilotMessages,copilotThreads}.js`
- `app/javascript/dashboard/api/captain/{copilotMessages,copilotThreads,tasks}.js`
- `app/javascript/dashboard/composables/{useCopilotReply,useCaptain}.js`
- `config/routes.rb:77-78` (copilot_threads/messages), `:86` (tasks), `:242` (copilot_chat, ghost_suggestion)
- `components/widgets/conversation/CopilotPanel.vue` **(morto — candidato a remoção)**

**[AGENTES-IA] — não tocar**

- `Captain::Assistant` e seu `config`; `captain_assistants`
- `captain_assistant_responses` (FAQs), `captain_documents`, `captain_assistant_logs`, `captain_scenarios`
- `enterprise/app/jobs/captain/conversation/response_builder_job.rb` (atendimento automático)
- Avaliação de conversa, handoff, auto-resolve
- `Captain::Llm::SystemPromptsService` **na parte do assistente**

**[COMPARTILHADO] — cuidado redobrado, mudança exige decisão explícita**

| Peça | Caminho:linha | Risco se mexer |
|---|---|---|
| Cota de respostas | `plan_usage_and_limits.rb:18` + 4 chamadores | derruba atendimento em produção |
| `Llm::BaseAiService` | base dos dois | quebra assistente |
| `Captain::ChatHelper` + `ChatResponseHelper` + `ChatGenerationRecorder` | `enterprise/app/helpers/captain/` | quebra assistente |
| `SystemPromptsService.copilot_response_generator` | lê `assistant.config` | muda comportamento cruzado |
| As 33 `Captain::Tools::Copilot::*` + `SearchDocumentationService` | recebem `@assistant` | 12 delas escrevem em produção (§6.5) |
| `captain_custom_tools` | `chat_service.rb:102` | tools do cliente (ex.: Vista da Tozi) |
| `conversations.additional_attributes` | `copilot_chats_controller.rb:50` | grava na conversa real |
| Chave de LLM | Captain (conta) vs `settings['openai_api_key']`/ENV | **dois esquemas de chave diferentes** |

### 6.8 Perguntas que a reescrita precisa responder antes de começar

`[opinião minha]` — são decisões do Walisson, não minhas:

1. **O copiloto pode agir no atendimento (enviar, resolver, atribuir) ou só sugerir?** (§6.5) — muda o conjunto de tools inteiro.
2. **A tela nova terá tools?** Se sim, o motor único é o A (não o D do painel v2 atual). (§6.1)
3. **Cota separada ou compartilhada?** (§6.4)
4. **O que fazer com o motor B (`copilot_chat`) e o C (ghost)?** Absorver no motor único, ou manter o ghost como caminho barato/rápido separado? `[opinião minha]` o ghost tem razão de existir separado: é `max_tokens: 80` com cache de 5 min — é a única coisa no sistema que chega perto de ser instantânea, e ela **substitui bem parte do papel da resposta pronta** que vai ser aposentada (§4.4).

---

## 7. Fontes

**Anatomia de UI e design**
- [Setproduct — Designing AI chat interfaces: anatomy, patterns, pitfalls](https://www.setproduct.com/blog/ai-chat-interface-ui-design)
- [925studios — ChatGPT Design Breakdown](https://www.925studios.co/blog/chatgpt-interface-design-breakdown)
- [OpenAI Developers — Apps SDK UI guidelines](https://developers.openai.com/apps-sdk/concepts/ui-guidelines)
- [thefrontkit — AI Chat UI Best Practices](https://thefrontkit.com/blogs/ai-chat-ui-best-practices)
- [Coursera — ChatGPT keyboard shortcuts](https://www.coursera.org/articles/chatgpt-keyboard-shortcuts) · [fastshortcuts](https://fastshortcuts.com/shortcuts/chatgpt/)

**Pesquisa de UX (NN/g e acadêmica)**
- [NN/g — Accordion Editing and Apple Picking](https://www.nngroup.com/articles/accordion-editing-apple-picking/) (8 participantes, set/2023)
- [NN/g — Less Chat, More Answer](https://www.nngroup.com/articles/less-chat-more-answer/) (9 participantes, 8 chatbots)
- [NN/g — Explainable AI in Chat Interfaces](https://www.nngroup.com/articles/explainable-ai/)
- [NN/g — 10 Guidelines for Designing Your Site's AI Chatbots](https://www.nngroup.com/articles/ai-chatbots-design-guidelines/)
- [NN/g — The User Experience of Customer-Service Chat: 20 Guidelines](https://www.nngroup.com/articles/chat-ux/)
- [arXiv — UX Research on Conversational Human-AI Interaction (literature review, ACM DL)](https://arxiv.org/pdf/2202.09895)

**Streaming — transporte e implementação**
- [Evil Martians — AnyCable, Rails, and the pitfalls of LLM-streaming](https://evilmartians.com/chronicles/anycable-rails-and-the-pitfalls-of-llm-streaming)
- [Ably — Rails ActionCable: the good and the bad](https://ably.com/blog/rails-actioncable-the-good-and-the-bad)
- [Ably — Resumable token streaming: why AI streams break on reconnect](https://ably.com/blog/token-streaming-for-ai-ux)
- [Ably — AI chat stream resumption: when Redis is enough](https://ably.com/blog/ai-chat-stream-resumption)
- [Vercel AI SDK — Chatbot Resume Streams](https://ai-sdk.dev/docs/ai-sdk-ui/chatbot-resume-streams) · [zirkelc/ai-resumable-stream](https://github.com/zirkelc/ai-resumable-stream) · [LibreChat](https://www.librechat.ai/docs/features/resumable_streams)
- [Anthropic — Streaming Messages (SSE, tipos de evento)](https://docs.anthropic.com/en/api/messages-streaming)
- [Aha! Engineering — Streaming LLM Responses with Rails: SSE vs Turbo Streams](https://www.aha.io/engineering/articles/streaming-llm-responses-rails-sse-turbo-streams) ([repo](https://github.com/aha-app/chat_app))
- [Hivenet — Streaming for LLM Apps: SSE vs WebSockets](https://www.hivenet.com/post/llm-streaming-sse-websockets) · [BuildMVPFast](https://www.buildmvpfast.com/blog/streaming-llm-responses-sse-vs-websockets-2026) · [GetStream](https://getstream.io/blog/websocket-sse/)
- [puma#1009 — SSE, persistent connections and concurrency](https://github.com/puma/puma/issues/1009) · [mooreniemi — Rails SSE is for discrete push events](https://mooreniemi.github.io/rails/web/2016/09/04/rails-sse.html)
- [The Prompt Bench — Streaming UI Patterns That Don't Break](https://thepromptbench.com/ai-product-ux/streaming-ui-patterns-that-dont-break/)
- [vercel/streamdown #473 — fenced code blocks during streaming](https://github.com/vercel/streamdown/issues/473) · [HF chat-ui parseIncompleteMarkdown](https://huggingface.co/spaces/mishig/chat-ui/blob/700a2240da17049333f7f4adbec7357ea0d4f7da/src/lib/utils/parseIncompleteMarkdown.ts) · [markstream-vue](https://markstream-vue-docs.simonhe.me/guide/ai-chat-streaming)

**Latência**
- [Redis — TTFT Meaning](https://redis.io/blog/ttft-meaning/) · [Redis — How to Improve LLM UX](https://redis.io/blog/how-to-improve-llm-ux-speed-latency-and-caching/)
- [TianPan — TTFT Is the Only Latency Metric Your Users Actually Feel](https://tianpan.co/blog/2026-04-16-streaming-ttft-latency-perception)

**Acessibilidade**
- [W3C WAI — ARIA23: role=log](https://www.w3.org/WAI/WCAG21/Techniques/aria/ARIA23) · [A11Y Collective — ARIA Live Regions](https://www.a11y-collective.com/blog/aria-live/) · [Sara Soueidan — Accessible notifications with ARIA Live Regions](https://www.sarasoueidan.com/blog/accessible-notifications-with-aria-live-regions-part-1/)

**Plataformas de atendimento**
- Intercom: [How to use Copilot](https://www.intercom.com/help/en/articles/8587194-how-to-use-copilot) · [AI features in the Inbox](https://www.intercom.com/help/en/articles/6955446-ai-features-available-in-the-inbox) · [Content suggestions](https://www.intercom.com/help/en/articles/11394959-use-ai-powered-content-suggestions-to-improve-fin) · [Copilot (produto)](https://www.intercom.com/helpdesk/copilot)
- Zendesk: [About agent copilot](https://support.zendesk.com/hc/en-us/articles/7908817636378-About-agent-copilot) · [Getting started with Copilot add-on](https://support.zendesk.com/hc/en-us/articles/5608652527386-Getting-started-with-AI-features-in-the-Zendesk-Copilot-add-on) · [2025 recap](https://support.zendesk.com/hc/en-us/articles/10140103140122-2025-recap-What-s-new-in-Zendesk)
- Freshdesk: [Freddy AI Copilot (suporte oficial)](https://support.freshdesk.com/support/solutions/folders/50000001060) · [Reply Suggester (guia)](https://www.eesel.ai/blog/freddy-ai-reply-suggester)
- Crisp: [MagicReply](https://www.success.ai/ai-tools/crisp-magicreply)
- Tidio: [Lyro](https://www.tidio.com/ai-agent/) · [Lyro (help center)](https://help.tidio.com/hc/en-us/articles/9003475527196-Lyro-the-conversational-AI-agent)
- Chatwoot: [Captain (user guide)](https://www.chatwoot.com/hc/user-guide/en/categories/captain) · [How to use Captain Copilot](https://www.chatwoot.com/hc/user-guide/articles/1738110272-how-to-use-captain-copilot) · [Captain Inside the Reply Editor (20/02/2026)](https://www.chatwoot.com/blog/captain-inside-the-reply-editor/) · [Captain Custom Tools (03/04/2026)](https://www.chatwoot.com/blog/captain-custom-tools) · [Changelog](https://www.chatwoot.com/changelog) · [Crítica: an honest overview of Chatwoot Captain](https://www.eesel.ai/blog/chatwoot-captain)

**Canned responses vs IA** *(fontes comerciais — números indicativos)*
- [eesel — The end of canned responses](https://www.eesel.ai/blog/canned-responses) · [eesel — AI canned responses](https://www.eesel.ai/blog/ai-canned-responses-for-support) · [Alhena — The Macro Is Dead](https://alhena.ai/blog/ai-replace-canned-responses-macros/) · [Fabren — AI support macro review workflow](https://www.fabrenhq.com/blog/ai-support-macro-review-workflow)

**Adoção, custo e risco**
- [Assembled — Contact center AI copilot](https://www.assembled.com/page/contact-center-ai-copilot) · [CustomerScience — AI Copilot for Support Agents](https://customerscience.com.au/customer-experience-2/ai-copilot-support-agents/)
- [Featurebase — Fin AI pricing](https://www.featurebase.app/blog/fin-ai-pricing) · [Macha — Fin vs Zendesk AI pricing](https://www.getmacha.com/blog/intercom-fin-vs-zendesk-ai-pricing)
- [Inference.net — LLM API pricing comparison](https://inference.net/content/llm-api-pricing-comparison/) · [DevToolLab — Prompt caching guide](https://devtoollab.com/blog/prompt-caching-guide)
- [Fini — AI support platforms accuracy & guardrails](https://www.usefini.com/guides/ai-support-platforms-accuracy-hallucination-guardrails) · [Lorikeet — Hallucination prevention in regulated industries](https://www.lorikeetcx.ai/articles/how-ai-support-prevents-hallucinations-regulated-2026)
- Air Canada: [ABA — BC Tribunal confirms liability](https://www.americanbar.org/groups/business_law/resources/business-law-today/2024-february/bc-tribunal-confirms-companies-remain-liable-information-provided-ai-chatbot/) · [Forbes](https://www.forbes.com/sites/marisagarcia/2024/02/19/what-air-canada-lost-in-remarkable-lying-ai-chatbot-case/) · [Pinsent Masons](https://www.pinsentmasons.com/out-law/news/air-canada-chatbot-case-highlights-ai-liability-risks)

**Contexto interno consultado (leitura, sem alteração)** — branch `homologacao`, 28/07/2026

*Infra e streaming (§2)*
- `app/javascript/dashboard/composables/useCopilotReply.js` — ausência de streaming real, contrato de `AbortController` (linhas ~150-250, 355-370)
- `config/puma.rb` — `RAILS_MAX_THREADS` default 5, `WEB_CONCURRENCY` default 0
- `deployment/nginx_chatwoot.conf:45-51` — `proxy_buffering off`, `proxy_read_timeout 900s` no server block
- `config/routes.rb:77-78, 86, 242` — rotas dos quatro caminhos de copiloto

*Fronteira (§6)*
- `enterprise/app/models/copilot_thread.rb:23` — `belongs_to :assistant`; `copilot_message.rb` — enum e `enqueue_response_job`
- `db/schema.rb:1004-1014` — `copilot_threads.assistant_id` nullable no banco
- `enterprise/app/services/captain/copilot/chat_service.rb:7,31,63-96,99,102-103,114-118` — cota, 33 tools, system prompt
- `enterprise/app/jobs/captain/copilot/response_job.rb` — timeout 30s, fallbacks
- `enterprise/app/controllers/api/v1/accounts/captain/copilot_threads_controller.rb:36-43,51` — bloqueio por cota, `find` sem fallback
- `enterprise/app/helpers/captain/chat_helper.rb:27,52-54,99` — `response_format: json_object`, handlers de tool, temperatura
- `enterprise/app/helpers/captain/chat_response_helper.rb:9,19,45-58` — parse JSON, persistência de thinking
- `enterprise/app/services/captain/tools/copilot/send_message_service.rb` — envio outgoing ao cliente
- `enterprise/app/services/captain/tools/search_documentation_service.rb:16` — RAG em `assistant.responses.approved`
- `enterprise/lib/enterprise/captain/base_task_service.rb:3,30` — bloqueio 429 e incremento de cota
- `enterprise/lib/enterprise/captain/reply_suggestion_service.rb:21` — resolução do assistente por inbox/agent_bot
- `enterprise/app/models/enterprise/account/plan_usage_and_limits.rb:18` — `increment_response_usage`
- `app/services/copilot/{chat_service,ghost_suggestion_service,openai_settings}.rb` — motores B e C, chave própria
- `app/controllers/api/v1/accounts/conversations/{copilot_chats,ghost_suggestions}_controller.rb` — motor B escrevendo em `conversations.additional_attributes`
- `app/controllers/api/v1/accounts/captain/tasks_controller.rb` — motor D
- `app/javascript/dashboard/routes/dashboard/Dashboard.vue:200-205` — mutex v1/v2
- `app/javascript/dashboard/components-next/ai-assistant/composables/useAIAssistantFlag.js:26-38` — resolução da flag `ai_assistant_v2`
- `app/javascript/dashboard/components-next/ai-assistant/AIAssistantPanel.vue:16` — usa `useCaptain`, não `copilotThreads`
- `app/javascript/dashboard/components/widgets/conversation/ConversationBox.vue:4` — comentário do painel removido
- `app/javascript/dashboard/api/captain/tasks.js` — endpoints do motor D
