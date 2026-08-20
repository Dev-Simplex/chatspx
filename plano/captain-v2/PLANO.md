# Copiloto v2 — plano de arquitetura

> Pesquisa multi-agente · 28/07/2026 · 4 frentes · ~3.100 linhas de investigação
> Base: `P1-backend-hoje.md` · `P2-frontend-hoje.md` · `P3-auditoria-conversa.md` · `P4-benchmark-chat-ia.md`
> **Só planejamento. Nenhuma linha de código foi alterada.**

---

## 0. O escopo, na voz do Walisson

> "o captain que to falando é o chat de copiloto que o agente tem, temos agentes de ia que criamos
> no sistema que ta um pouco interligado **não vamos mexer nisso**. tome cuidado."

**Alvo:** o chat de copiloto que ajuda o agente humano.
**Zona proibida:** os agentes de IA que atendem o cliente (assistentes, cenários, base de
conhecimento, avaliação, handoff, auto-resolve).

### A interligação, localizada

```ruby
# enterprise/app/models/copilot_thread.rb:4
belongs_to :assistant, class_name: 'Captain::Assistant'
# db/schema.rb:1010 — copilot_threads.assistant_id
```

Toda thread de copiloto pertence a um Assistente. O copiloto **consome** o agente de IA como
persona e conhecimento. Esse vínculo é o contrato a preservar: a reescrita muda a interface e o
motor de chat, e mantém a leitura do assistente exatamente como é hoje.

---

## 1. O achado que muda a prioridade de tudo

**O copiloto não funciona hoje.** Não é lentidão nem UX ruim — está fora do ar.

```
P3, auditoria funcional:  "Copilot/IA inteiro (chave OpenAI inválida)"
GlitchTip issue 90, 19x:  RubyLLM::UnauthorizedError: Incorrect API key provided: sk-proj-****
```

Antes de discutir arquitetura, alguém precisa responder: **a chave da OpenAI está válida e quem
paga essa conta?** Todo o resto deste plano depende disso.

---

## 2. Estado atual, sem enfeite

### 2.1 Três camadas de IA empilhadas, competindo

| Camada | Onde | Estado |
|---|---|---|
| **Copilot V1** (painel lateral, thread no banco, resposta assíncrona) | `components/copilot/` + `components-next/copilot/` | **é o que o agente vê hoje** |
| **AI Assistant V2** (painel novo, quick prompts, markdown, copiar/aplicar/regenerar, Ctrl+J) | `components-next/ai-assistant/` — 3.083 linhas | **pronto, porém DESLIGADO por flag e com i18n quebrado** |
| **Ações inline no composer** (✨ polir / tom / resumir / sugerir) | `WootWriter/CopilotMenuBar.vue` + `useCopilotReply.js` | **vivo, é o caminho mais usado na prática** |

**O V2 já existe e está quebrado por um bug barato:** as 83 chamadas de tradução do
`AIAssistantPanel.vue` pedem `CONVERSATION.AI_ASSISTANT_PANEL.*`, mas as strings foram gravadas na
**raiz** do `conversation.json`. Ligando a flag hoje, o painel abre mostrando chave crua na tela.

### 2.2 Dívidas do backend que a reescrita herda se não olhar

1. **Dois motores de LLM coexistindo.** O V2 (gem `ai-agents`) e o V1
   (`Captain::Llm::AssistantChatService`). O V1 parecia morto, mas as ações de IA das Automações
   **chamam o V1 direto, sem checar a flag** (`app/services/flows/ai_actions.rb:85`) — está vivo por
   uma porta lateral.
2. **Prompt global com regra de um cliente específico.** Todo cliente do ChatSPX, de qualquer
   vertical, recebe "horário de Sinop/MT" e "dúvida sobre um imóvel" no system prompt
   (`enterprise/lib/captain/prompts/assistant.liquid:17,26`). É multi-tenancy quebrada no lugar mais
   caro possível. **Fora do escopo do copiloto — mas precisa virar chamado próprio.**
3. **Cenários 100% desligados.** Os 11 cenários da base estão `enabled = false`, e o prompt gasta o
   "Decision Framework" inteiro instruindo o LLM a usar handoffs que não existem em runtime.
4. **Config fantasma.** 6 dos 8 assistentes têm `media_pipeline` ligado no banco, e o serviço que
   leria isso não tem um único caller.
5. **2.884 linhas de telas de gestão órfãs** — registradas no router, acessíveis por URL, e **nada
   no app navega até elas**.

### 2.3 A tela de conversa, auditada de verdade (47 ações)

| | qtd |
|---|---:|
| ✅ funciona | 31 |
| ⚠️ funciona com problema | 5 |
| ❌ quebrada | 6 |
| 🚫 não testado | 5 |

O núcleo (enviar, nota, resolver, atribuir, rotular, anexar, citar, encaminhar) **está de pé**. O que
quebra é o que foi empilhado por cima:

- **busca na conversa** — só enxerga 3 meses; buscar "aguardando" numa conversa com 325 ocorrências
  devolve lista vazia
- **Copilot/IA** — chave inválida (§1)
- **traduzir** — integração ausente, falha em silêncio
- **favoritar mensagem** — função nunca existiu
- **abas CRM e SPX Dashboard** — domínio morto e 404
- **"Deixar pendente"** — devolve 422 porque a feature está desligada na inbox; o botão aparece
  mesmo assim (é a mesma validação que quebrava 9 specs, já corrigidos)

---

## 3. O que o mercado ensina (P4)

| Achado | Fonte | Consequência aqui |
|---|---|---|
| Streaming é percebido como **40–60% mais rápido** com o mesmo tempo total | TianPan | é o item de maior retorno perceptivo |
| **Não use ActionCable para streaming token a token** — é *at-most-once* e não numera mensagens; sem ordem garantida sob carga | Evil Martians, Ably | palavras embaralhadas na tela do agente. **Usar SSE** |
| A infra já está pronta: nginx com `proxy_buffering off` e `proxy_read_timeout 900s` | `deployment/nginx_chatwoot.conf:45-51` | **não precisa mexer em nginx**; ajustar Puma |
| Mostrar "cadeia de raciocínio" é **contraindicado** — explicações são racionalizações post-hoc | NN/g | mostrar **fonte**, não "pensamento" |
| Usuário quer resposta, não conversa; stream longo gera sobrecarga | NN/g | resposta curta e acionável > ensaio |
| **Ninguém matou canned responses** — Intercom, Zendesk e Freshdesk fundiram com IA | Zendesk docs | ver §4 |
| Adoção morre em 1 semana se a qualidade for ruim | Assembled | qualidade > quantidade de features |

---

## 4. Respostas prontas: a decisão e o que a pesquisa diz

**Decisão do Walisson:** aposentar totalmente. A IA escreve do zero; o acervo vira conhecimento.

**O que o mercado faz:** ninguém fez isso. Todos mantiveram o template e usaram a IA para escolher,
preencher e reescrever — o Zendesk inclusive mostra a macro sugerida com indicador de confiança.

**Por que, mesmo assim, a decisão se sustenta aqui:** existem **9 respostas prontas na base inteira**
(8 na Realizare, 1 na Simplex). O benchmark descreve empresas com centenas de macros, onde matar o
acervo destrói anos de curadoria. Aqui não há acervo a destruir.

> **Recomendação:** manter a decisão, com uma ressalva barata — migrar as 9 para a base de
> conhecimento antes de remover a tela, e não apagar a tabela na primeira fase. Se algum cliente
> novo chegar com acervo grande, o caminho de volta continua aberto.

---

## 5. A arquitetura proposta

### 5.1 Um motor, dois lugares

```
                    ┌───────────────────────────────┐
                    │   Motor de chat do copiloto   │
                    │  thread + streaming + tools   │
                    └───────────────┬───────────────┘
                       ┌────────────┴────────────┐
                       ▼                         ▼
          Copiloto na conversa           Tela própria de chat
          (contexto do cliente)          (assistente do time)
                 FASE 1                        FASE 3
```

O mesmo backend serve os dois. O que muda é o **contexto injetado**: na conversa, a IA recebe o
histórico do cliente; na tela própria, começa em branco.

### 5.2 Transporte: SSE

Endpoint dedicado de streaming, resposta `text/event-stream`, cancelável. **Não** ActionCable — a
garantia de ordem não existe e o sintoma (texto embaralhado) é visível para o agente.
O ActionCable continua onde já é bom: avisar que a thread mudou.

### 5.3 O que se aproveita

**Não começar do zero.** O `AIAssistantPanel` (V2) já tem painel, quick prompts, markdown,
copiar/aplicar/regenerar e atalho. Falta: consertar o i18n, trocar a chamada síncrona por streaming,
e persistir a thread.

| Aproveita | Reescreve | Aposenta |
|---|---|---|
| `components-next/ai-assistant/` (3.083 linhas) | camada de transporte (síncrono → SSE) | Copilot V1 (`components-next/copilot/`) |
| `copilot_thread` / `copilot_message` (modelo) | `Copilot::ChatService` | tela de respostas prontas |
| vínculo com `Captain::Assistant` | montagem de contexto | telas órfãs de `routes/dashboard/captain/` |
| ações inline do composer (o mais usado) | — | — |

---

## 6. Fases

### Fase 0 — destravar (dias)
Chave da OpenAI válida; corrigir o i18n do painel V2; ligar a flag em uma conta piloto.
**Entrega:** o copiloto volta a funcionar e o painel novo aparece. Sem arquitetura nova.

### Fase 1 — o chat de verdade (2–3 semanas)
Streaming SSE, thread persistida com histórico, parar/regenerar/editar, markdown com código
copiável, tratamento de erro honesto. Matar o Copilot V1.
**Entrega:** a experiência de ChatGPT dentro da conversa.

### Fase 2 — substituir as respostas prontas (1–2 semanas)
Sugestão automática ao abrir a conversa, com [Usar] [Refazer] [Editar]. Migrar as 9 respostas para
conhecimento. Remover a tela de gestão (sem apagar a tabela).
**Entrega:** o `/atalho` deixa de ser necessário.

### Fase 3 — tela própria (1–2 semanas)
Mesmo motor, seção nova no menu, histórico agrupado por data.
**Entrega:** o assistente do time, fora da conversa.

### Fase 4 — limpeza (contínuo)
Matar o motor V1 (depois de migrar `flows/ai_actions.rb:85`), remover telas órfãs, config fantasma,
e o prompt hardcoded de Sinop-MT.

**Nada disso exige tocar nos agentes de IA.**

---

## 7. A feature de impacto

O Walisson pediu "uma feature que traga impacto, para o bem". A pesquisa aponta uma, e ela não é
nenhuma das acima:

> **A IA ler a conversa e dizer ao agente o que fazer — antes de ele perguntar.**

Hoje o agente abre uma conversa parada há dois dias e precisa ler tudo para se situar. O copiloto
poderia entregar, na abertura: o que o cliente quer, o que já foi prometido, o que está pendente, e
a próxima ação sugerida. Sem clique.

É a diferença entre uma ferramenta que responde quando chamada e uma que **chega antes**. O material
para isso já existe no repo (episódios, avaliação de conversa) — hoje usado só para métrica.

---

## 8. Riscos

| Risco | Mitigação |
|---|---|
| Chave de LLM inválida/custo | resolver na Fase 0; medir custo por conversa antes de escalar |
| Qualidade ruim mata a adoção em 1 semana | piloto em 1 conta, medir uso real antes de ampliar |
| Reescrita do copiloto contaminar o atendimento | o vínculo com `Captain::Assistant` é só leitura; nenhuma escrita em tabela de agente |
| V1 vivo pela porta lateral das Automações | migrar `flows/ai_actions.rb:85` antes de matar o V1 |
| Perder o acervo de respostas prontas | migrar as 9 antes; não apagar a tabela |

---

## 9. O que precisa de decisão sua

1. **A chave da OpenAI** — válida? quem paga? tem teto de custo?
2. **Conta piloto** — qual cliente recebe primeiro?
3. **A feature do §7** entra no plano ou fica para depois?
4. O prompt hardcoded de Sinop-MT vira chamado separado? (afeta todos os clientes, fora do copiloto)
