# A1 — Backend: streaming SSE + thread persistida do copiloto

> Worker A1 · 28/07/2026 · VM 192.168.8.232 (homologação) · branch `homologacao`, working tree
> (nada commitado, conforme regra 2 do briefing).

---

## 1. O que mudou

### Arquivos novos

| Arquivo | O que é |
|---|---|
| `app/services/copilot/streaming_chat_service.rb` | motor de geração em streaming (RubyLLM), sem JSON e sem tools: texto markdown token a token |
| `app/services/copilot/thread_stream_service.rb` | orquestra a geração sobre a thread persistida: persiste, decide `finish_reason`, emite eventos |
| `app/services/copilot/sse_stream.rb` | escritor SSE: formato, `id:` incremental, heartbeat em thread própria, detecção de desconexão |
| `app/services/copilot/streaming_error.rb` | tradução da falha do provedor em **código estável**, com redaction de credencial no log |
| `app/services/copilot/stream_cancellation.rb` | sinal explícito de "parar", compartilhado entre processos via Redis |
| `enterprise/app/controllers/api/v1/accounts/captain/copilot_streams_controller.rb` | o endpoint (`ActionController::Live`), validações de pré-condição e lock por thread |
| `spec/support/copilot_llm_stubs.rb` | helper de spec: stub do RubyLLM (inclusive streaming) + parser de eventos SSE |
| `spec/services/copilot/*_spec.rb` (4 arquivos) | specs dos serviços |
| `spec/enterprise/controllers/api/v1/accounts/captain/copilot_streams_controller_spec.rb` | request spec do endpoint |

### Arquivos alterados (cirúrgico)

| Arquivo:linha | Mudança | Por quê |
|---|---|---|
| `config/routes.rb:60-65` | alias `POST copilot_threads/:copilot_thread_id/stream` | caminho literal do contrato C1 (sem `/captain`) |
| `config/routes.rb:82-84` | `resource :stream, controller: 'copilot_streams'` dentro de `copilot_threads` | rota canônica |
| `enterprise/app/models/copilot_thread.rb:37-44` | `order(created_at: :asc, id: :asc)` em `previous_history` | **ordem estável**: duas mensagens no mesmo instante empatavam em `created_at` |
| `enterprise/app/models/copilot_message.rb:61-68` | `finish_reason` entra na whitelist de `message` | permite marcar resposta interrompida sem migration |
| `.../captain/copilot_messages_controller.rb:12` | `order(created_at: :asc, id: :asc)` no index | mesma razão: histórico recuperável em ordem estável |
| `.../captain/copilot_threads_controller.rb:35-48,58-64` | aceita `skip_response: true` no create | **pedido do A4**: sem isso, criar a thread dispara o job legado E o stream → o agente vê **duas** respostas |

**Sem migration. Sem commit. Sem deploy/restart. Nenhuma escrita em tabela de agente de IA** — o
`belongs_to :assistant` é usado só para ler persona (`config['product_name']`, `temperature`) e
resolver a conta.

---

## 2. CONTRATO (é isto que o A4 consome — não adivinhe nada)

### Requisição

```
POST /api/v1/accounts/:account_id/captain/copilot_threads/:copilot_thread_id/stream
```

Alias equivalente (mesmo controller), caso o cliente já tenha sido escrito pelo caminho literal do briefing:

```
POST /api/v1/accounts/:account_id/copilot_threads/:copilot_thread_id/stream
```

E o **botão "parar"**, que o A4 já tem na tela:

```
DELETE /api/v1/accounts/:account_id/captain/copilot_threads/:copilot_thread_id/stream
→ 204 No Content
```

Chame **junto** com o `abort()` do fetch (não no lugar dele). Abortar o fetch sozinho também
cancela, mas a detecção depende do buffer do socket encher — medido contra a OpenAI real, o servidor
seguiu gerando **~4s** depois de o agente sair. O `DELETE` corta na próxima checagem (≤200ms) e para
de queimar token do cliente. Se a conexão ainda estiver de pé quando o corte acontecer, você recebe
`done` com `finish_reason: "cancelled"` e o `message_id` do parcial já gravado.

Headers:

```
api_access_token: <token do agente>      # ou access-token/client/uid do devise_token_auth
Content-Type: application/json
Accept: text/event-stream                # opcional; a resposta é sempre event-stream
```

Corpo (JSON):

```json
{ "message": "Resume a conversa para mim", "conversation_id": 1234, "regenerate": false }
```

| Campo | Obrigatório | Efeito |
|---|---|---|
| `message` | não* | pergunta nova do agente; é persistida como `copilot_message` do tipo `user` antes de gerar |
| `conversation_id` | não | `display_id` da conversa aberta; entra no prompt como transcrição (últimas 20 mensagens) |
| `regenerate` | não | descarta a última resposta do assistente e regera a partir da mesma pergunta ("refazer") |

\* `message` pode ser omitido em dois casos: `regenerate: true`, ou quando a última mensagem da
thread já é do agente (retomar geração perdida). Fora disso → `422 nothing_to_generate`.

⚠️ **`EventSource` do browser não serve** (só faz GET e não manda header de autenticação).
O cliente tem de usar `fetch` + `response.body.getReader()`.

### Resposta 200 — o stream

```
content-type: text/event-stream
cache-control: no-store
x-accel-buffering: no
last-modified: <httpdate>
```

Quatro eventos, sempre nesta gramática (`id:` incremental, um `data:` em linha única com JSON):

```
id: 1
event: start
data: {"thread_id":186,"user_message_id":202}

id: 2
event: token
data: {"delta":"Bom "}

id: 14
event: done
data: {"message_id":203,"finish_reason":"stop"}
```

```
id: 2
event: error
data: {"code":"unauthorized","message":"The AI provider rejected the credentials configured for this account."}

id: 3
event: done
data: {"message_id":null,"finish_reason":"error"}
```

Mais o comentário de keep-alive, a cada 10s de silêncio — **ignore, não é evento**:

```
: keep-alive
```

| Evento | Payload | Notas |
|---|---|---|
| `start` | `thread_id`, `user_message_id` (null se não veio `message`) | confirma que a geração começou |
| `token` | `delta` (pedaço de texto, markdown) | concatenar na ordem; nunca vem fora de ordem (uma conexão HTTP só) |
| `error` | `code`, `message` | **use o `code`** para escolher o texto; `message` é técnico, em inglês, para log |
| `done` | `message_id`, `finish_reason` | **sempre o último evento**; `message_id` é a `copilot_message` já gravada |

`finish_reason`: `stop` (terminou), `error` (falhou), `cancelled` (o agente saiu — nesse caso o
cliente já não está escutando; o parcial fica gravado).

**Códigos de `error`** (lista fechada hoje; trate desconhecido com texto genérico, não quebre):
`unauthorized` · `rate_limited` · `timeout` · `provider_down` · `payment_required` ·
`bad_request` · `not_configured` · `internal`.

### Erros que acontecem ANTES do stream abrir (HTTP + JSON, não SSE)

O cliente precisa checar `response.ok` antes de ler o corpo como stream.

| HTTP | Corpo | Quando |
|---|---|---|
| 401 | — | sem autenticação |
| 404 | — | a thread não existe ou é de outro agente |
| 422 | `{"code":"captain_api_key_missing"}` | a conta não tem chave de IA configurada |
| 422 | `{"code":"nothing_to_generate"}` | sem pergunta pendente e sem `message` |
| 429 | `{"code":"quota_exceeded"}` | cota de respostas do Captain esgotada |
| 409 | `{"code":"busy"}` + `Retry-After: 2` | já existe geração em curso nesta thread |

Regra: **pré-condição vira HTTP; falha depois da geração começar vira evento `error`.** O
vocabulário de `code` é o mesmo nos dois caminhos.

### Duas coisas que o A4 pediu no relato dele — respondidas

1. **Rota:** ele assumiu `POST .../captain/copilot_threads/:thread_id/stream`. **Está certa**, é a
   canônica. O alias sem `/captain` também responde; nada a mudar no front.
2. **`skip_response: true` no create da thread:** **implementado.**
   `POST /api/v1/accounts/:account_id/captain/copilot_threads` agora aceita `skip_response: true` e,
   com ele, **não** enfileira o `Captain::Copilot::ResponseJob` — a thread nasce só com a mensagem do
   agente e quem gera é o `/stream`. Sem o parâmetro, o comportamento antigo continua idêntico (dois
   specs cobrem os dois caminhos). Isso elimina o risco nº 2 da lista dele (resposta dobrada).

### ⚠️ Um ponto do cliente do A4 que precisa de ajuste: `Last-Event-ID`

O relato do A4 diz: *"se o servidor numera os frames (`id:`), mando `Last-Event-ID` e descarto os ids
já vistos"*. Eu **numero** — mas **não retomo**: este servidor não tem buffer server-side, então uma
reconexão é uma **geração nova**, com `id:` reiniciando em `1`. Se o cliente carregar o último id
visto entre conexões, ele vai **descartar os primeiros tokens da resposta nova**.

O que o front precisa fazer enquanto não existir retomada:
- **zerar o dedupe a cada nova conexão** (é o caminho que ele já tem para "servidor não numera");
- tratar `409 busy` na reconexão rápida: o lock só cai quando o servidor percebe a desconexão
  (~1s), então uma reconexão em 800ms tende a bater em 409. Mandei `Retry-After: 2` para isso;
- lembrar que, ao reconectar, o parcial da tentativa anterior **já está gravado** na thread com
  `finish_reason: "cancelled"` — recarregar o histórico é uma alternativa mais barata que regerar.

### Persistência (contrato C3, sem migration)

- pergunta → `copilot_messages` `message_type: user`, `message: {content}`;
- resposta → `copilot_messages` `message_type: assistant`, `message: {content, finish_reason}`;
- **a resposta é gravada ANTES do evento `done`** (provado por spec com sonda no `write`, e o
  `message_id` do `done` é o id real da linha). Recarregar a página no instante seguinte mostra a
  resposta.

---

## 3. Decisões técnicas (e o preço de cada uma)

### 3.1 `ActionController::Live` + SSE, geração na thread do request

Alternativas consideradas: (a) ActionCable, (b) Sidekiq escrevendo num Redis Stream lido pelo
endpoint SSE, (c) `ActionController::Live` gerando inline.

Escolhi **(c)**, por duas razões e com um custo assumido:

1. **Ordem.** Chunk fora de ordem é palavra embaralhada na cara do agente. SSE numa única conexão
   HTTP dá ordem de graça; ActionCable não numera mensagens e o P4 §2.3 documenta o embaralhamento
   sob carga. Isso elimina (a).
2. **A task pede cancelamento de verdade:** "se o cliente fecha a conexão, a geração para e nada
   fica pendurado". Com (b) o trabalho vive no Sidekiq e sobrevive ao cliente — é o oposto do
   pedido (e é o que o P4 §2.6 preferiria para "fechou a aba"). Registro a divergência: **a task
   venceu o benchmark**; quando quisermos "fechou a aba não cancela", o caminho é (b), e o desenho
   atual já está preparado (o motor recebe um `cancelled` injetável; trocar quem responde essa
   pergunta é a única mudança).

**Cancelamento tem dois caminhos, e o segundo nasceu do teste real.** Fechar a conexão cancela — mas
a detecção depende do buffer do socket encher, e tokens são pequenos: contra a OpenAI real o
servidor seguiu gerando **~4s** depois de o agente sumir. Isso é dinheiro do cliente. Por isso
existe `DELETE .../stream`, que grava um sinal no Redis consultado pela geração (com throttle de
200ms, para não virar uma ida à rede por palavra). O front chama os dois: `abort()` para parar de
renderizar, `DELETE` para parar de gerar.

**Preço, medido nesta VM (não é teoria):** com `RAILS_MAX_THREADS=5`, cinco streams simultâneos
seguram as cinco threads e o servidor **para de responder**:

```
== 5 streams presos nas 5 threads do Puma; agora uma requisicao comum ==
GET /api -> 000 em 10.002648s     (timeout de 10s do curl, sem resposta)
...30s depois, com os streams terminados:
apos os streams: GET /api -> 200 em 0.184074s
```

Ou seja, o P4 §2.7 está certo e o número é esse. **Antes de ligar isso para a frota** é preciso
subir `RAILS_MAX_THREADS`/`WEB_CONCURRENCY` (a thread do stream fica quase toda em I/O; o gargalo é
contagem, não CPU) — ou isolar o endpoint num processo Puma próprio. Sem esse ajuste, trocamos
latência ruim por indisponibilidade. **Isso não é mudança minha para fazer** (regra 3 do briefing):
fica registrado como pré-requisito de operação.

Mitigações que já estão no código, para o risco não depender só de configuração:
- teto de duração por geração (`COPILOT_STREAM_TIMEOUT_SECONDS`, default **120s**) — nenhuma thread
  fica presa indefinidamente;
- timeout de rede por requisição ao provedor (`COPILOT_STREAM_REQUEST_TIMEOUT_SECONDS`, default 60s)
  e `max_retries = 1` (retry de 401 só queima thread);
- heartbeat de 10s que **detecta cliente morto** e derruba a geração;
- lock por thread: uma geração por `copilot_thread` de cada vez.

`ActionController::Live` afeta **todas** as actions do controller (cada request numa thread), por
isso o endpoint mora num controller próprio, com uma action só — o resto do copiloto continua
síncrono.

**Vazamento de conexão do ActiveRecord:** verificado empiricamente — 7 streams sequenciais com pool
de 5 e mais 5 concorrentes, todos concluídos com `finish_reason=stop`, e o servidor voltou a
responder em 0,18s. Sem `ConnectionTimeoutError`, ou seja, o executor do Rails 7.1 devolve a
conexão da thread do Live (o `IsolatedExecutionState.share_with` do `Live#process` mantém o mesmo
contexto da thread pai). Não chamei `release_connection` manual justamente porque isso poderia
devolver ao pool uma conexão em uso.

### 3.2 Duas perguntas seguidas na mesma thread → 409, não fila

A segunda requisição na **mesma thread** é recusada com `409 busy` antes de abrir o stream (lock
Redis via `Redis::LockManager`, TTL = teto de duração + 30s).

Por quê não enfileirar nem cancelar a primeira: as duas gerações leem e escrevem o **mesmo
histórico**; rodando juntas, a segunda responderia sem enxergar a primeira e as duas respostas
entrariam intercaladas na thread. Enfileirar no servidor seria segurar uma segunda thread do Puma
esperando — exatamente o recurso escasso (§3.1). Cancelar a primeira automaticamente é decisão de
produto que pertence ao front: o agente vê o botão "parar". Então o backend recusa rápido e barato,
e o front decide (esperar, parar, ou abrir outra thread). Threads **diferentes** do mesmo agente
geram em paralelo sem restrição.

O TTL garante que um processo morto no meio não deixa a thread travada para sempre.

### 3.3 Erro é primeira classe

- **Código estável decidido no backend, texto decidido no front.** `Copilot::StreamingError` é a
  única fonte de códigos, usada tanto no evento SSE quanto nas respostas HTTP de pré-condição.
- **Nada do provedor chega ao cliente.** O payload do evento `error` é montado a partir de uma
  tabela local de mensagens; o corpo cru do provedor não é repassado.
- **No log tem contexto, não tem segredo:** `Rails.logger` recebe
  `outcome=... account_id=... copilot_thread_id=... user_id=... chars=... events=... duration_ms=...`
  mais `error_code`, `error_class` e a mensagem do provedor **redigida** (`sk-…` e `Bearer …` viram
  `[REDACTED]`, truncada em 300 chars). Exemplo real da rodada de prova:

```
[Copilot::Stream] outcome=error account_id=11160 copilot_thread_id=186 user_id=3454 chars=0
  events=1 duration_ms=990 error_code=unauthorized error_class=RubyLLM::BadRequestError
  error_message="Incorrect API key provided: [REDACTED]. You can find your API key at https://platform.openai.com."
```

- **Erro não suja o histórico.** Se a geração falhou sem produzir texto, **nada** é gravado como
  mensagem do assistente. O caminho antigo grava "ocorreu uma falha" como resposta — e isso depois
  volta como contexto para o modelo. Aqui a thread fica com a pergunta pendente, e o front oferece
  "tentar de novo" (que é literalmente a mesma chamada, sem `message`).
- **Cota:** só é consumida quando houve texto gerado (inclusive parcial cancelado — o token foi
  pago). Falha sem conteúdo não consome. Isso importa porque a cota é **compartilhada com os
  agentes de IA** (P4 §6.4).

#### Achado que só apareceu no teste ponta a ponta

O RubyLLM 1.9.2, **no caminho de streaming**, ignora o status HTTP do provedor:
`Providers::OpenAI::Streaming#parse_streaming_error` rebaixa tudo que não seja
`server_error`/`rate_limit_exceeded`/`insufficient_quota` para **400**. Resultado: um 401 de chave
revogada — o estado mais provável hoje — chegava como `RubyLLM::BadRequestError` e o agente leria
"requisição inválida" em vez de "credencial recusada". A primeira rodada do `curl` mostrou
exatamente isso (`{"code":"bad_request"}`).

Corrigido em `Copilot::StreamingError`: quando o código por classe é ambíguo (`bad_request` /
`internal`), a classificação é refinada pelo texto do provedor (que continua sem sair do backend).
Tem spec de regressão (`streaming_error_spec.rb`).

### 3.4 Sem tools nesta rodada, e por quê

O caminho antigo (`Captain::Copilot::ChatService`) tem 33 tools e responde **JSON**
(`{reasoning, content, reply_suggestion}`) — formato incompatível com streaming token a token, e o
loop de tools multiplica o tempo com a thread do Puma presa. O motor novo gera **texto markdown**
com persona do assistente e a transcrição da conversa no prompt (últimas 20 mensagens, autor
rotulado). O endpoint antigo continua no ar, intacto: nada foi removido.

O que isso significa na prática: nesta rodada o copiloto do streaming **não executa ações**
(resolver, atribuir, enviar mensagem) e **não faz RAG na base de conhecimento**. É uma perda de
capacidade em relação ao caminho antigo, consciente, e ela vem com um ganho de segurança relevante:
o `SendMessageService` (que hoje permite o copiloto falar com o cliente sem aprovação humana, P4
§6.5) não está no caminho novo.

---

## 4. Como testei

### 4.1 Specs (LLM stubado, nada bate na OpenAI)

```
bundle exec rspec spec/services/copilot/ \
  spec/enterprise/controllers/api/v1/accounts/captain/copilot_streams_controller_spec.rb
→ 47 examples, 0 failures
```

Cobrem: stream feliz (ordem dos deltas, `done` no fim), cancelamento no meio (parcial preservado
com `finish_reason=cancelled`, nenhum `done` para quem já saiu), 401 do provedor (código estável,
sem vazamento, sem sujar histórico, sem consumir cota), **persistência antes do `done`** (sonda que
consulta o banco no exato momento em que o evento é escrito), timeout de geração, `regenerate`,
histórico recuperável em ordem estável após várias gerações, e as seis pré-condições HTTP.

`spec/support/copilot_llm_stubs.rb` se auto-registra via `RSpec.configure` — **não** precisei
editar `spec/rails_helper.rb` (arquivo compartilhado com outros workers).

Sobre a armadilha do `MockRedis`/`EVAL` avisada na task: não fui atingido. Esta suíte usa Redis de
verdade e o lock usa `SET NX EX` (`Redis::LockManager`), não `EVAL`.

### 4.2 Prova ponta a ponta com emissor falso (sem OpenAI)

Montagem (tudo fora do repo, em `scratchpad/`, já derrubado e limpo ao fim):

- **emissor falso** em Ruby puro na `127.0.0.1:4599`, respondendo `POST /v1/chat/completions` no
  formato SSE da OpenAI: 12 chunks a cada 0,3s; modo `ERRO401` devolve HTTP 401 com credencial
  falsa no corpo; modo `LENTO` fica 25s calado antes do primeiro token;
- **Puma isolado** `RAILS_ENV=test PORT=3055` (banco de teste; homologação intocada);
- conta/usuário/assistente/thread semeados no banco de teste, `CAPTAIN_OPEN_AI_ENDPOINT` apontando
  para o emissor falso.

**Headers da resposta:**

```
HTTP/1.1 200 OK
content-type: text/event-stream
cache-control: no-store
x-accel-buffering: no
last-modified: Tue, 28 Jul 2026 18:24:16 GMT
Transfer-Encoding: chunked
```

**Caminho feliz** (`curl -N`, carimbo de horário por linha — repare no intervalo de ~0,3s):

```
18:24:16.652 | id: 1
18:24:16.658 | event: start
18:24:16.663 | data: {"thread_id":186,"user_message_id":202}
18:24:17.020 | id: 2
18:24:17.026 | event: token
18:24:17.031 | data: {"delta":"Bom "}
18:24:17.315 | event: token
18:24:17.324 | data: {"delta":"dia! "}
18:24:17.619 | data: {"delta":"Resumo "}
18:24:17.915 | data: {"delta":"da "}
18:24:18.218 | data: {"delta":"conversa: "}
18:24:18.524 | data: {"delta":"o "}
18:24:18.822 | data: {"delta":"cliente "}
18:24:19.122 | data: {"delta":"quer "}
18:24:19.419 | data: {"delta":"a "}
18:24:19.723 | data: {"delta":"segunda "}
18:24:20.019 | data: {"delta":"via "}
18:24:20.323 | data: {"delta":"do boleto."}
18:24:20.696 | id: 14
18:24:20.701 | event: done
18:24:20.705 | data: {"message_id":203,"finish_reason":"stop"}
```

**Cancelamento** (`curl --max-time 2`, o agente "fecha a aba" no meio):

```
18:24:41.421 | event: start
18:24:41.445 | event: token  data: {"delta":"Bom "}
18:24:41.751 | event: token  data: {"delta":"dia! "}
18:24:42.058 | event: token  data: {"delta":"Resumo "}
18:24:42.361 | event: token  data: {"delta":"da "}
(curl encerrado)

# log do emissor falso — a geração no PROVEDOR foi abortada:
[fake-openai] chunk 9/12 enviado
[fake-openai] !! CLIENTE (Rails) FECHOU A CONEXAO NO MEIO — geracao abortada

# log do Rails:
[Copilot::Stream] outcome=cancelled account_id=11160 copilot_thread_id=186 user_id=3454
  chars=44 events=9 duration_ms=2304

# e o parcial ficou gravado:
204 user:      {"content" => "Escreve um resumo longo"}
205 assistant: {"content" => "Bom dia! Resumo da conversa: o cliente quer ", "finish_reason" => "cancelled"}
```

Nota honesta: entre o cliente sumir e o Rails perceber passaram ~1,2s (chunks 5–9 ainda saíram do
provedor) — é o buffer de socket entre Puma e cliente. Não dá para zerar isso sem sondar o socket;
o efeito prático é pagar ~1s de tokens a mais no cancelamento.

**401 do provedor** (chave revogada, que é o estado real hoje):

```
18:28:51.526 | event: start
18:28:51.985 | event: error
18:28:51.990 | data: {"code":"unauthorized","message":"The AI provider rejected the credentials configured for this account."}
18:28:52.005 | event: done
18:28:52.009 | data: {"message_id":null,"finish_reason":"error"}
```

O corpo cru do provedor era
`Incorrect API key provided: sk-proj-FAKEKEY1234567890...` — **nada disso apareceu no stream**, e no
log a chave saiu como `[REDACTED]`.

**Heartbeat** (provedor calado 25s):

```
18:30:22.858 | event: start
18:30:32.839 | : keep-alive
18:30:42.842 | : keep-alive
18:30:47.862 | event: token  data: {"delta":"Bom "}
```

**Geração concorrente na mesma thread:**

```
HTTP/1.1 409 Conflict
{"code":"busy","message":"This copilot thread is already generating an answer."}
```

### 4.3 Validação contra a OpenAI REAL (chave liberada pelo coordenador, 28/07 ~18h50)

Com a chave válida instalada, refiz a prova ponta a ponta contra a API de verdade — `gpt-4.1-mini`,
**quatro chamadas ao todo**, sem loop. Nos specs nada mudou: continuam com o LLM stubado.

Montagem: mesmo Puma isolado `RAILS_ENV=test :3055`, conta semeada no banco de teste com uma
conversa real (cliente pedindo segunda via de boleto, pedido 44821) e a chave lida do `ENV` — nunca
impressa, nunca escrita em spec/fixture/relatório. **Tudo foi apagado ao final** (conta, hooks,
usuário); auditei o repo por `sk-…` depois: nada.

**1) Geração real, streaming token a token** (`conversation_id` no corpo, então o modelo enxergou a
transcrição):

```
18:50:11.754 | event: start   {"thread_id":371,"user_message_id":438}
18:50:18.443 | event: token   {"delta":"Proble"}
18:50:18.448 | event: token   {"delta":"ma"}
18:50:18.491 | event: token   {"delta":": a"}
18:50:18.536 | event: token   {"delta":" cliente"}
             ... 62 tokens, intervalos de 5–20ms ...
18:50:19.660 | event: token   {"delta":"."}
18:50:19.675 | event: done    {"message_id":439,"finish_reason":"stop"}
```

Resposta que o agente recebeu (montada dos deltas): *"Problema: a cliente não recebeu o boleto do
pedido 44821 e precisa pagar hoje. Próximo passo: verificar no sistema o status do envio do boleto e
reemitir/reenviar a segunda via imediatamente para o e‑mail cadastrado (ou gerar link de pagamento)
e confirmar aqui."* — usou o número do pedido que estava na conversa, ou seja, o contexto chegou.

TTFT de 6,7s na **primeira** chamada e **2,5s** na segunda (`{"delta":"ok"}` → `done`), com o
processo já aquecido: a diferença é autoload do Rails em `test`, não o provedor. Os 62 tokens
saíram em 1,2s (~50 tok/s), com intervalos de milissegundos entre eventos — **prova de que não há
buffer no nosso caminho**, porque um buffer entregaria tudo de uma vez.

**2) Botão "parar" durante geração real** (`DELETE .../stream` logo após o primeiro token):

```
DELETE /stream -> 204
...
id: 42
event: done
data: {"message_id":593,"finish_reason":"cancelled"}

[Copilot::Stream] outcome=cancelled account_id=… copilot_thread_id=371 chars=166 events=41
```

A pergunta pedia 15 itens com duas frases cada (facilmente >1.500 caracteres); a geração parou em
**166 caracteres**, o parcial foi gravado e o agente recebeu o `done` com o id dele. Ressalva
honesta: não meço com precisão o intervalo entre o `DELETE` e a parada, porque o `curl` redirecionado
para arquivo bufferiza a própria saída; o teto de projeto é 200ms (intervalo de checagem) + o chunk
em curso.

**3) 401 REAL da OpenAI** (troquei o hook da conta de teste para uma chave inválida — não custa nada
e é o cenário que mais importa):

```
event: error  {"code":"unauthorized","message":"The AI provider rejected the credentials configured for this account."}
event: done   {"message_id":null,"finish_reason":"error"}
```

Isto **confirma contra a API real** o achado que o emissor falso tinha levantado: a OpenAI respondeu
401, e o RubyLLM entregou `RubyLLM::BadRequestError`. Sem o refinamento por texto, o agente leria
"requisição inválida" quando o problema é a credencial. Com ele, sai `unauthorized`.

Detalhe de higiene que só apareceu aqui: a OpenAI devolve a chave **parcialmente mascarada** no
corpo do erro (`sk-proj-****…`), e meu redator não pegava esse formato (o `*` não estava na classe
do regex). Ajustado — agora vira `[REDACTED]` no log, com spec.

**O que continua sem validação real:** `rate_limited` e `provider_down`. Forçá-los exigiria martelar
a API (o coordenador pediu explicitamente para não rodar loop) ou derrubar a OpenAI. Ambos estão
cobertos por spec com erro injetado, e o `unauthorized` — que é o mesmo caminho de código — foi
provado contra a API real.

### 4.4 Suíte pré-existente dos arquivos tocados

```
bundle exec rspec spec/enterprise/models/copilot_thread_spec.rb spec/enterprise/models/copilot_message_spec.rb \
  spec/enterprise/controllers/api/v1/accounts/captain/copilot_{messages,threads}_controller_spec.rb \
  spec/enterprise/services/captain/copilot/chat_service_spec.rb \
  spec/enterprise/jobs/captain/copilot/response_job_spec.rb
→ 52 examples, 2 failures
```

As **2 falhas são pré-existentes** — são de i18n: os specs vieram do upstream esperando texto em
inglês, e a base SPX traduziu as chaves para pt-BR (`config/locales/pt_BR.yml:395,397`, commit
`9ec500e265`, de 22/07), enquanto contas novas nascem com locale pt-BR.

```
expected: "Message is required"                 got: "A mensagem é obrigatória"
expected: "You are out of Copilot credits..."   got: "Você está sem créditos de Copilot..."
```

Rodando o diretório inteiro do namespace `captain` (215 exemplos) aparecem mais duas falhas, também
alheias a esta task: `custom_tools_controller_spec.rb:43` (payload 2 ≠ 1) e
`documents_controller_spec.rb:229` (mesmo caso de i18n).

**Prova de que as quatro são pré-existentes:** rodei os mesmos quatro exemplos num worktree limpo do
`HEAD` (`ee87f5e799`), sem nenhuma linha minha — `4 examples, 4 failures`. O worktree foi removido
em seguida.

### 4.5 Rubocop

```
bundle exec rubocop app/services/copilot/ enterprise/app/controllers/api/v1/accounts/captain/ \
  enterprise/app/models/copilot_{thread,message}.rb config/routes.rb \
  spec/services/copilot/ spec/support/copilot_llm_stubs.rb \
  spec/enterprise/controllers/api/v1/accounts/captain/copilot_streams_controller_spec.rb
→ no offenses detected
```

---

## 5. O que ficou de fora (e por quê)

1. ~~Geração real contra a OpenAI~~ — **feito** depois que o coordenador liberou a chave válida:
   ver §4.3 (geração real com contexto da conversa, parar durante geração real, e 401 real). Segue
   sem validação real apenas `rate_limited` e `provider_down`, que exigiriam martelar a API.
2. **Tools e RAG no caminho novo** (§3.4). Decisão consciente de escopo; o caminho antigo continua
   funcionando.
3. **Retomada de stream (`Last-Event-ID`).** Já emito `id:` incremental em todo evento, que é o
   pré-requisito, mas não há buffer server-side para reatacar num offset. Se o agente perder a
   conexão no meio, a geração é cancelada e o parcial fica gravado (ele vê o texto ao recarregar,
   com `finish_reason=cancelled`).
4. **`WEB_CONCURRENCY`/`RAILS_MAX_THREADS` da frota.** Medi o problema (§3.1) mas não mudei
   configuração de servidor — não é minha alçada nesta rodada.
5. **i18n das mensagens de erro no backend.** Por decisão de contrato, o backend manda `code` +
   mensagem técnica em inglês; **quem escreve o texto que o agente lê é o front** (A4/A3), onde o
   i18n pt-BR já existe. Assim não disputei `config/locales/*.yml` com outro worker.

---

## 6. Riscos que o coordenador precisa pesar antes de ligar isso

| Risco | Gravidade | Mitigação |
|---|---|---|
| Threads do Puma: 5 streams = dashboard fora do ar (medido) | **alta** | subir `RAILS_MAX_THREADS`/`WEB_CONCURRENCY` ou isolar o endpoint antes de ligar na frota |
| Cota compartilhada com os agentes de IA: uso maior do copiloto pode esgotar e derrubar o atendimento | **alta** | já checo cota antes de abrir o stream (429) e só consumo quando há texto; a decisão de dimensionar a cota é de produto |
| `finish_reason` novo dentro do jsonb `message` | baixa | aditivo; o jbuilder devolve o `message` inteiro, front antigo ignora chave desconhecida |
| Alias de rota sem `/captain` | baixa | é o caminho literal do contrato C1; se o A4 usar a canônica, dá para remover a linha depois |
| Fechar a conexão leva segundos para propagar (medido: ~4s contra a OpenAI real) | média | resolvido pelo `DELETE .../stream` (≤200ms); **o A4 precisa chamá-lo junto do `abort()`** |
| Chave real usada na validação | — | ficou só no `ENV`; a conta de teste e o hook foram apagados, e auditei o repo por `sk-…` (nada) |
| Front deduplicando por `Last-Event-ID` entre conexões (não há retomada) | **média** | ajuste de uma linha no `useCopilotStream.js` do A4 — ver §2; sem isso, tokens iniciais somem depois de uma reconexão |
