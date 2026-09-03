# Onda 4 · Trilha SERVER-SIDE E CREDENCIAIS — relatório de execução

**Worktree:** `/home/chatwoot/chatwoot-o4-server-cred` · **Branch:** `o4-server-cred`
**Base:** `redesenho-integra` (`e0ae8e5759`) · **Data:** 18/08/2026

## Escopo realocado pelo coordenador

| Bloco | Estado | Razão |
|---|---|---|
| **5.03** contrato + registro server-side | **executado** | destravado: depende de 1.09, que já está na base |
| 5.02 credenciais com `encrypts` + OAuth | **não iniciado** | depende de **0.10** (infraestrutura, pendente por exigir sudo) |
| 5.11 fila server-side | **não iniciado** | depende de **5.02** |
| 5.12 modo sem PII | **não iniciado** | depende de 5.11 |

Nenhuma linha de 5.02, 5.11 ou 5.12 foi escrita. O que este bloco deixa pronto **para** elas está
declarado no §5 deste relatório.

---

## 0. Duas coisas achadas antes da primeira linha de código

### 0.1 O worktree e a branch não existiam

O spec nomeia `WORKTREE: /home/chatwoot/chatwoot-o4-server-cred` e `BRANCH: o4-server-cred`. Nenhum
dos dois existia — `git worktree list` mostrava 24 worktrees, e nenhum com esse nome; `git branch -a`
não tinha a branch. O que existia era `chatwoot-o4-resto` (branch `o4-resto`), apontando para o mesmo
commit de `redesenho-integra`.

Criei o worktree e a branch a partir de `redesenho-integra`, que é o que o spec pressupõe:

```
git worktree add -b o4-server-cred /home/chatwoot/chatwoot-o4-server-cred redesenho-integra
```

**Consequência para a instrução de `git merge redesenho-integra`:** ela ficou satisfeita por
construção — a branch nasce no mesmo commit, então não há merge a fazer nem conflito a resolver. Os
111 commits da base estão no `git log` desde o primeiro dia.

### 0.2 O conflito entre o aceite do bloco e a tabela §A.6, resolvido por escrito

O aceite de 5.03 no `PLANO-MESTRE` diz *"resolver uma conversa gera o evento com `event_id`"*. A
tabela mestre de eventos (§A.6 do plano 25) marca o evento #10, `chatspx_conversation_resolved`, com
**`event_id`: não**.

Não é contradição, e a diferença é a que a próxima trilha resolveria por conta própria se ficasse só
no código: **todo registro tem `event_id`** (é a chave de negócio: 5.14 acha o evento por ele, 5.05 o
devolve ao widget, 5.11 é idempotente por ele); a coluna da §A.6 diz **quais eventos propagam esse id
ao navegador**, para a Meta deduplicar o par (`event_id`, `event_name`) na janela de 48 h — e esses
são os eventos 3, 4, 5, 6, 9 e 11.

Está escrito no §4.1 do contrato, com a razão, para que nenhuma das duas pontas tenha de adivinhar.

---

## 1. Bloco 5.03 — o que foi entregue

### 1.1 O documento de contrato

`docs/tracking/contrato-de-eventos.md`, 219 linhas, **versionado no repositório** e não neste
relatório — porque quem vai consumi-lo (5.04, 5.05, 5.10, 5.11, 5.13 a 5.16) trabalha no repositório.
O que ele fixa:

- os **dois vocabulários** e o mapa 1:1 entre eles (arbitragem A9): `chatwoot:` para o evento de
  `window` que o site do cliente escuta, `chatspx_` para o evento de tracking que vai ao GA4 e à Meta;
- as **três regras de nome**, e cada uma é verificada em código: prefixo `chatspx_`, `snake_case`,
  **≤ 40 caracteres** (limite do GA4, não preferência nossa);
- a **tabela dos 12 eventos** com parâmetros, destinos, propagação de `event_id` e política de PII;
- **campo por campo** das duas tabelas: tipo, se aceita nulo, default e **o que acontece quando o
  campo chega ausente** — que é a coluna que a junção erra quando não está escrita;
- a **API que as outras trilhas chamam**, com exemplo executável;
- os **pontos abertos**, declarados em vez de resolvidos em silêncio (§6 do contrato).

### 1.2 O contrato de dados, em resumo

**`tracking_events`** — o fato, uma linha por ação do usuário:

| Campo | Tipo | Nulo | Default | Ausente ⇒ |
|---|---|:---:|---|---|
| `event_id` | string | não | — | **gerado** (UUID v4 do servidor) |
| `name` | string | não | — | erro de validação |
| `account_id` | bigint | não | — | erro |
| `inbox_id` / `conversation_id` / `contact_id` | bigint | **sim** | `nil` | fica `nil` |
| `occurred_at` | datetime | não | — | **`Time.current`** (é o instante do FATO) |
| `properties` | jsonb | não | `{}` | vira `{}` |
| `source` | enum | não | `server` | `server` (0) · `widget` (1) · `site` (2) |
| `dedup_key` | string | não | — | **derivada** de `nome:sujeito:occurred_at.to_i` |

**`tracking_deliveries`** — uma linha por (evento, destino): `destination` (6 valores: `data_layer`,
`meta_pixel`, `ga4_gtag`, `meta_capi`, `ga4_mp`, `google_ads`), `status` (`pending`, `sent`, `failed`,
`skipped`, `dead` — o último é a DLQ), `attempts`, `http_status`, `error_code`, `error_message`,
`field_names` (**nomes**, nunca valores), `emq`, `last_attempted_at`, `delivered_at`.

### 1.3 A API que 5.04, 5.05 e 5.16 vão chamar

```ruby
event = Tracking::EventRecorder.record!(
  name: 'chatspx_conversation_resolved',  # obrigatório, formato validado
  account: account,                       # obrigatório
  inbox: inbox, conversation: conversation, contact: contact,   # opcionais
  occurred_at: event.timestamp,           # opcional -> Time.current
  properties: { resolution: 'agent', duration_s: 428 },         # opcional -> {}
  source: :server,                        # opcional -> :server
  dedup_key: nil                          # opcional -> derivada do fato
)                                         # idempotente: mesmo fato -> MESMO registro

delivery = event.claim_delivery(:meta_capi)
return if delivery.nil?   # outro worker já assumiu — NÃO entregue
```

`record!` levanta `ActiveRecord::RecordInvalid` para nome fora do contrato ou conta ausente. **Não**
levanta por corrida: colisão de `dedup_key` devolve o registro existente.

### 1.4 As três travas, e o que cada uma impede

| Trava | Mecanismo | O que impede |
|---|---|---|
| único em `event_id` | índice do banco | dois registros com o mesmo id de negócio |
| único em (`account_id`, `name`, `dedup_key`) | índice do banco + `dedup_key` determinística | **o retry do job registrar o mesmo fato duas vezes** |
| único em (`tracking_event_id`, `destination`) | índice do banco + `claim_delivery` devolvendo `nil` | **entrega dupla ao mesmo destino** — é o aceite do bloco |

A segunda trava não estava no enunciado, e é ela que faz a terceira valer: sem idempotência do
**fato**, um retry criaria um evento novo, com `event_id` novo, e a entrega dupla passaria pelo índice
de (evento, destino) sem tocá-lo. O risco não é hipotético — `reporting_event_listener.rb:202-209`,
nesta base, documenta o mesmo: *"Sidekiq retries the dispatcher job and can insert the same raw event
again"*.

### 1.5 Onde as chaves estrangeiras apontam, e por quê

Segui a doutrina já escrita nesta base
(`20260723000000_cascade_conversation_deletion_for_orphan_blockers.rb`): coluna **NOT NULL** cujo
registro não existe sem o pai → `CASCADE`; coluna **nullable** de histórico de diagnóstico →
`SET NULL`.

| FK | ON DELETE | Razão |
|---|---|---|
| `tracking_events.account_id` | `CASCADE` | o evento não existe sem a conta |
| `tracking_events.inbox_id` | `SET NULL` | apagar inbox não pode apagar histórico de atribuição — **nem falhar por causa dele** |
| `tracking_events.conversation_id` | `SET NULL` | idem — é a cicatriz de `flow_runs`/`flow_step_logs`, que travavam `conversation.destroy!` |
| `tracking_events.contact_id` | `SET NULL` | idem |
| `tracking_deliveries.tracking_event_id` | `CASCADE` | a entrega não existe sem o evento (coluna NOT NULL) |

### 1.6 Nada foi disparado para serviço externo

Este bloco **não tem cliente HTTP**. Ele grava o fato e reserva a entrega; quem fala com Meta, Google
ou qualquer destino é o bloco 5.11, que não foi iniciado. Não há chamada de rede nos testes, nenhum
`test_event_code`, nenhum duble de API — porque não há API a dublar ainda. `TrackingDelivery` nasce
`pending` e permanece `pending`: um teste verifica explicitamente que o listener **não** cria entrega
nenhuma, para que ninguém confunda "registrado" com "entregue".

---

## 2. Verificação

Banco de teste **dedicado**: `chatwoot_test_o4cred`, criado só para esta trilha. Nenhum comando tocou
o banco de desenvolvimento ou de produção desta VM. `RAILS_ENV=test` em todos os comandos.

### 2.1 A suíte do bloco

| Arquivo | Exemplos | Falhas |
|---|---:|---:|
| `spec/models/tracking_event_spec.rb` | 28 | 0 |
| `spec/models/tracking_delivery_spec.rb` | 10 | 0 |
| `spec/services/tracking/event_recorder_spec.rb` | 11 | 0 |
| `spec/listeners/tracking_event_listener_spec.rb` | 11 | 0 |
| `spec/integration/tracking_conversation_resolved_spec.rb` | 2 | 0 |
| **Total** | **62** | **0** |

`bundle exec rubocop` nos onze arquivos do bloco: **0 ofensas**.

### 2.2 O vermelho, medido restaurando o estado antigo

O primeiro vermelho foi `0 examples, 0 failures, 4 errors` — constantes inexistentes. **Isso é
exatamente o falso-verde de que o coordenador avisou**: `0 examples` passa por verde num relatório
desatento. Por isso cada trava foi verificada de novo, **removendo do banco ou do código a peça que
ela protege**, com N > 0 exemplos rodando:

| Sabotagem | Como | Resultado |
|---|---|---|
| sem o índice único de (evento, destino) | `DROP INDEX index_tracking_deliveries_on_event_and_destination` | 21 exemplos, **3 falhas** |
| sem o índice único de dedup do fato | `DROP INDEX index_tracking_events_on_dedup` | 51 exemplos, **4 falhas** |
| FK de `conversation` sem `ON DELETE` | `ALTER TABLE ... ADD CONSTRAINT` sem cláusula | **1 falha**, com `ActiveRecord::InvalidForeignKey` — a cicatriz de `flow_runs` reproduzida |
| listener também no `SyncDispatcher` | uma linha em `sync_dispatcher.rb` | 11 exemplos, **1 falha** |

Cada sabotagem foi desfeita logo depois, e a suíte voltou a 62/0.

### 2.3 A migration roda do zero

`db:rollback STEP=2` seguido de `db:migrate`, e o `db/schema.rb` resultante é **byte a byte idêntico**
ao anterior — a migration não depende do estado em que o banco já estava, que é a condição para rodar
na frota. O diff do `schema.rb` são as duas tabelas e a linha de versão: **+46 linhas, nenhuma
reformatação**.

### 2.4 Regressão — comparação maçã com maçã

O listener novo entra no `AsyncDispatcher`, então passa a receber **todo** `conversation.resolved` do
sistema. O diretório onde uma regressão minha apareceria é `spec/listeners`, e ele foi rodado nos dois
estados (o WIP foi para o `git stash` para medir o baseline):

```
base   (sem o bloco) : 294 examples, 16 failures
branch (com o bloco) : 305 examples, 16 failures     <- os 11 a mais são os specs deste bloco
diff das listas de falha: IDÊNTICAS
```

Além disso, nos três arquivos que concentram falhas (`hook_listener`, `reporting_event_listener`,
`webhook_listener`): **77 exemplos / 11 falhas nos dois lados, listas idênticas**.

**As falhas pré-existentes da base**, para quem for integrar: `HookJob.perform_later` com assinatura
divergente entre spec e implementação (10 casos), `Status cannot be Pending — feature disabled for
this inbox` (4), e outras de job/SSRF/waveform. **Nenhuma das 75 falhas do run largo cita tracking** —
verificado por `grep -icE "tracking_event|TrackingEvent|chatspx"` → **0**.

### 2.5 Um falso positivo que investiguei em vez de reportar

Num run de 1297 exemplos, `installation_webhook_listener_spec.rb:18` falhou com
`PG::UniqueViolation` em `installation_configs`. Não é regressão: o arquivo passa **isolado**
(2 exemplos, 0 falhas) e **não** falha no run completo de `spec/listeners` nos dois estados. É
contaminação de banco entre specs dentro daquele run largo — outro exemplo criou o mesmo
`INSTALLATION_EVENTS_WEBHOOK_URL` e não limpou. Registrado porque um relatório que somasse essa falha
ao meu bloco teria acusado uma regressão inexistente.

---

## 3. Nota de infraestrutura: o gate de commit não rodava neste worktree

O worktree nasceu sem `node_modules` e sem `.husky/_/husky.sh`, então o hook de pré-commit **falhava
antes de verificar qualquer coisa** (`cannot open .husky/_/husky.sh`, depois
`npx canceled due to missing packages: lint-staged`).

Não usei `--no-verify`. Restaurei o `husky.sh` e liguei o `node_modules` de outro worktree, de modo
que o hook **rodasse de verdade** — e ele rodou: `check_vue_template_refs: 224 arquivos, problems=0`,
mais o rubocop nos arquivos Ruby. O `husky.sh` é arquivo **gerado** e ficou fora do commit (entrou por
acidente num primeiro commit e foi retirado antes de fechar).

**Para o coordenador:** qualquer worktree criado do zero terá o mesmo problema, e o sintoma é um hook
que falha por motivo que não tem nada a ver com o código. Vale `pnpm install` no provisionamento.

---

## 4. O que o próximo bloco encontra pronto

| Quem | O que já pode usar |
|---|---|
| **5.04** (eventos do widget) | `Tracking::EventRecorder.record!(source: :widget, ...)`; nomes validados pelo contrato; idempotência por `dedup_key` |
| **5.05** (`event_id` ao widget) | `event.event_id` existe em todo registro, gerado no servidor |
| **5.11** (fila server-side) | `event.claim_delivery(destino)` devolvendo `nil` para quem perdeu a corrida; `attempts`, `http_status`, `error_code`, `last_attempted_at` e o status `dead` para a DLQ |
| **5.12** (modo sem PII) | `field_names` guarda **nomes**, e recusa qualquer coisa que não seja lista rasa de strings |
| **5.13** (dedup) | o par (`event_id`, `event_name`) que a Meta exige, com o id nascido no servidor |
| **5.14** (auditoria) | índice BRIN em `occurred_at` para a varredura por período; `emq` e `field_names` por entrega |
| **5.16** (`track()` do site) | `source: :site` e nome livre desde que obedeça às três regras do contrato |

## 5. Pontos abertos, declarados

1. **`chatspx_csat_submitted` não existe.** O mapa da A9 o prevê, a tabela §A.6 não o define. O plano
   25 manda **não implementar antes de decidir**, para não nascer evento sem contrato. Fica para 5.15
   — o registro aceitaria o nome hoje; o que falta é decisão de produto (parâmetros, canais, PII).
2. **Retenção de 90 dias** (A12): o job de limpeza é de 5.14. Este bloco entrega só o índice que o
   torna viável. Apagar dado do cliente sem o painel que o mostra seria apagar às cegas.
3. **`resolution` do evento #10** responde "quem resolveu" com o único dado que o servidor tem sem
   inventar: `agent` quando há responsável, `bot` quando não há. Se o produto quiser distinguir
   "resolvido por automação" de "resolvido por IA", o campo aceita o valor — falta a fonte.

---

## 6. O que eu diria no `worker_done` — o canal foi revogado antes da entrega

`orca orchestration send --type worker_done` respondeu **`Dispatch ctx_a09f26032109 capability is
revoked`**. O relay aceitou o handshake; a capability deste dispatch é que já não vale. Como a regra
da task diz que **a entrega é o arquivo do relatório**, o conteúdo da mensagem fica aqui.

**Status: 5.03 concluído.** Commit local `031cfa1ae6` na branch `o4-server-cred`. Nada de push, PR,
deploy ou restart. 5.02, 5.11 e 5.12 não foram iniciados, conforme a realocação.

**O que foi entregue:** o documento de contrato (versionado no repositório, não só aqui), as duas
tabelas com os três índices únicos, os dois modelos, o serviço `Tracking::EventRecorder` que as outras
trilhas chamam, e o listener do primeiro fato server-side. **62 exemplos, 0 falhas**, incluindo um
teste de ponta a ponta que resolve a conversa **de verdade** e vê o evento nascer com `event_id`,
atravessando `Conversation` → `Dispatcher` → `EventDispatcherJob` → listener.

**Três coisas que precisam de decisão ou repasse:**

1. **O worktree e a branch não existiam.** Criei a partir de `redesenho-integra`, e o `git merge`
   pedido ficou satisfeito por construção. Se o coordenador esperava um worktree já provisionado,
   convém checar se outras trilhas da Onda 4 estão no mesmo estado.
2. **O gate de pré-commit não roda em worktree novo** (sem `node_modules`, sem `.husky/_/husky.sh`).
   Fiz o hook **funcionar** em vez de usar `--no-verify` — mas o próximo executor vai tropeçar nisso,
   e o sintoma é um hook que falha por motivo alheio ao código. Vale `pnpm install` no
   provisionamento.
3. **O conflito entre o aceite e a tabela §A.6 foi resolvido por escrito** (§0.2 e §4.1 do contrato):
   todo registro tem `event_id`; a coluna da tabela diz quais eventos **propagam** esse id ao
   navegador para a dedup da Meta. Se o produto discordar, o lugar de mudar é o documento — e aí 5.05
   e 5.13 mudam junto.

**A trava que acrescentei sem o enunciado pedir**, e a razão: o índice único de (evento, destino) só
protege se o **fato** for único. Sem idempotência do fato, um retry do job criaria evento novo com
`event_id` novo, e a entrega dupla passaria pelo índice sem tocá-lo. O índice único em
(`account_id`, `name`, `dedup_key`), com chave derivada do `occurred_at` do fato, fecha isso.

**Nada foi disparado para serviço externo.** Este bloco não tem cliente HTTP; há um teste que verifica
que o listener **não** cria entrega nenhuma.

---

# Segunda dispatch — blocos 5.19 e 5.20 (19/08/2026)

Base: `redesenho-integra` mergeado (137 commits). Banco de teste dedicado: `chatwoot_test_jwt`.
Bloqueados e não tocados: **5.02** e **5.11** (dependem de 0.10, infraestrutura com sudo), **5.12** e
**5.13** (dependem de 5.11).

## 7. Bloco 5.19 — JWT como formato adicional

### 7.1 Quem assina, e por que isso não mudou

O JWT é assinado pelo **servidor do cliente**, com o mesmo segredo do HMAC de hoje
(`channel_web_widgets.hmac_token`). O visitante não assina nada: ele carrega um token que recebeu
pronto. A ressalva herdada do 4.15 continua valendo integralmente — **em nenhum ponto deste desenho
o visitante precisa assinar**, e por isso a coleta de e-mail do pré-chat continua funcionando em
inbox estrita. Há um teste dedicado a isso (`o pre-chat anonimo, que o visitante nao tem como
assinar`), justamente para que um bloco futuro não feche essa porta sem perceber.

### 7.2 O que o JWT resolve que o HMAC não resolve

O HMAC prova **um** campo — `identifier` — e nada mais: e-mail, nome e telefone sempre chegaram sem
prova nenhuma. No JWT eles vão **dentro do payload assinado**, e por isso passam a ser atributos
autenticados. É por isso que ele é formato adicional e não substituto: o HMAC continua atendendo
quem já o usa, sem uma linha de mudança no comportamento dele.

### 7.3 Uma porta de decisão, não duas

`valid_hmac?` passou a aceitar **as duas provas**. Todo o resto continua sendo o caminho do 4.15 —
os estados `desativado` / `observado` / `obrigatorio` decidem o que fazer com a ausência de prova, e
não existe caminho por onde um token entre sem passar por lá.

Consequências verificadas em teste, uma por estado:

| Estado | JWT válido | JWT expirado |
|---|---|---|
| `desativado` | identifica e marca `hmac_verified` | **passa, anônimo, sem erro** |
| `observado` | identifica, marca verificado, **sai do relatório de não verificadas** | passa (contabilizado) |
| `obrigatorio` | identifica e passa | **mesma resposta que não mandar token nenhum** |

A última linha é a fronteira, e ela é do 4.15: este bloco **não inventa recusa própria nem permissão
própria**. Há um teste que compara os dois status lado a lado em vez de afirmar um número.

### 7.4 Três decisões de segurança

1. **`exp` é obrigatório** (`required_claims`). Sem validade, um token vazado vale para sempre.
2. **Algoritmo fixo em HS256.** Aceitar o algoritmo que o token declara é a armadilha clássica de
   JWT — o atacante escolhe `none` e assina o que quiser. Há um teste com `alg: none`.
3. **Allowlist fechada de atributos** (`email`, `name`, `phone_number`, `avatar_url`, e só escalares).
   Um `role` ou `account_id` no payload não vira atributo de contato.

E a regra de precedência: **o que prova vence o que afirma**. O corpo da requisição vem do navegador
e não é prova de nada; o payload do token foi assinado pelo servidor do cliente.

### 7.5 Um erro meu que os testes pegaram, e vale registrar

A primeira versão fazia `should_verify_hmac?` olhar a **presença** do token. Com isso, um token
expirado numa inbox `desativado` virava **401** — exatamente o erro que o aceite proíbe. A correção
foi olhar a **prova** (`identity_token_result.verified?`), e os dois exemplos que pegaram o defeito
continuam no arquivo.

### 7.6 O que ficou fora do 5.19, e por quê

O título do bloco cita **"credencial por callback"** (T-I3.7 do plano 25: o SDK recebe uma função que
resolve o token e a chama de novo a cada 401). **Não entregue.** Ele vive em `sdk/`, que é frente W,
e tem gate de peso próprio (bloco 0.5: teto de 15 KB gzip do `sdk.js`) — acrescentar código lá sem
medir o gate seria furar um número que o plano trata como não negociável.

O contrato para quem for implementar, para que a outra ponta não invente: a chave é
`chatwootSettings.identityTokenProvider`, uma função que devolve o token (ou uma Promise dele); o SDK
a chama no boot e **de novo** quando o backend responder que a identidade não foi aceita; o token vai
no mesmo parâmetro que este bloco já aceita, **`identity_token`**, em `PATCH /api/v1/widget/contact`
e em `PATCH /api/v1/widget/contact/set_user`.

## 8. Bloco 5.20 — mensagem proativa em uma chamada

### 8.1 A medição pedida: o que são as chamadas de hoje, e o que cada uma faz

O plano fala em **3** chamadas. **Medido nesta base, hoje são 2 ou 3**, e a diferença importa:

| # | Chamada de hoje | O que faz | Efeitos colaterais medidos |
|---|---|---|---|
| 1 | `GET /contacts/search?q=` | acha o contato por **`ILIKE %q%`** (parcial) | nenhum efeito de escrita; é leitura com paginação |
| 2 | `POST /conversations` | `ConversationBuilder` acha/cria a conversa | lock Redis por (inbox, contato); `conversation.created`; **`self_assign_creator_for_reply_gate`** (fork, `:212-218`); aceita `message` embutido e **já cria a mensagem na mesma transação** |
| 3 | `POST /conversations/:display_id/messages` | `Messages::MessageBuilder` cria a mensagem | `message.created` → ActionCable (é assim que o widget recebe em tempo real), webhooks, automações, notificações; supressões WAHA; `enforce_reply_assignment_gate` |

**Correção ao plano:** como a chamada 2 aceita `message`, quem já sabe o `contact_id` faz em **2**
chamadas, não 3. A terceira só é necessária para quem descobriu a conversa depois. Isto não muda a
conclusão do bloco — muda o número que se cita.

### 8.2 O que sobreviveu, e o que foi declarado morto

**Sobreviveu, por reúso e não por reimplementação:** `ConversationBuilder` continua sendo quem cria
conversa (com o mesmo lock), e `Messages::MessageBuilder` continua sendo quem cria mensagem. É de lá
que vem o `message.created`, e portanto o tempo real do aceite — não há um segundo caminho de
criação nem um broadcast próprio.

**Declarado morto neste caminho: `self_assign_creator_for_reply_gate`.** Ele atribui a conversa a
quem a criou quando a conta usa o gate de resposta. Existe para responsabilizar o **humano que
respondeu na tela**; num disparo de backend não há humano respondendo, e atribuir a conversa ao dono
do token de API poria na fila de uma pessoa algo que ela não escreveu. **Na rota de conversas ele
continua exatamente como estava** — a morte é só neste caminho, e está escrita no código.

**Mudou de propósito: a busca.** `contacts#search` usa `ILIKE` parcial porque serve a uma tela onde
alguém confere antes de agir. No disparo ninguém confere: a mensagem sai. Aqui a correspondência é
**exata**, e há um teste que recusa `maria@exemplo` quando o contato é `maria@exemplo.com.br`.

### 8.3 "Não abrir na fila" usa o mecanismo que o produto já tem

Por padrão a conversa nasce **`snoozed` com `snoozed_until: nil`**:

- fora da fila do atendimento, que é o que T-I6.2 pede;
- **volta sozinha quando o contato responde** — `message.rb:462` (`conversation.open! if
  conversation.snoozed?`) já faz isso para mensagem `incoming`;
- `snoozed_until: nil` faz o `TriggerScheduledItemsJob` nunca varrê-la (o filtro dele ignora `nil`,
  como o bloco de Flows já documentou): ela espera **a pessoa**, não o relógio.

Nenhum estado novo foi inventado. Com `create_conversation_without_contact_reply: true`, a conversa
nasce `open`, como antes.

### 8.4 Aceites, com o mecanismo de cada um

| Aceite | Mecanismo |
|---|---|
| uma chamada cria conversa + mensagem | `change(Conversation, :count).by(1).and change(Message, :count).by(1)` |
| **o visitante recebe no widget, em tempo real** | `have_enqueued_job(ActionCableBroadcastJob).with(array_including(contact_inbox.pubsub_token), 'message.created', anything)` — o broadcast endereçado **àquele** visitante, não um qualquer |
| não infla a fila | conversa nasce `snoozed`; e um segundo exemplo prova que ela **abre** quando o contato responde |
| contato verificado (T-I6.3) | 422 nomeando o motivo; `allow_unverified_contact: true` dispara assim mesmo |
| não reabre conversa encerrada nem duplica a aberta | reúso da conversa não resolvida mais recente |
| bot lê a própria conversa (T-I6.4) | `index` entra em `BOT_ACCESSIBLE_ENDPOINTS`, e um exemplo prova que o que **não** está na lista continua recusado |

### 8.5 Vermelho medido por sabotagem

| Sabotagem | Resultado |
|---|---|
| tirar `index` de `BOT_ACCESSIBLE_ENDPOINTS` | 3 exemplos, **1 falha** |
| conversa nascendo `open` (sem T-I6.2) | 17 exemplos, **1 falha** |
| remover a exigência de contato verificado | 17 exemplos, **1 falha** |
| trocar correspondência exata por `ILIKE` parcial | 17 exemplos, **1 falha** |

> Correção de medida: a sabotagem da busca parcial marcou **12 falhas** na primeira tentativa, mas
> aquele número era artefato — o `python3 -c` inline gerou Ruby com escape errado e o arquivo ficou
> sintaticamente torto. Refeita com `ruby -c` conferindo a sintaxe antes de rodar, o número real é
> **1**, e é o exemplo da correspondência exata.

## 9. Verificação dos dois blocos

Banco de teste **dedicado**: `chatwoot_test_jwt`. `RAILS_ENV=test` em todos os comandos; nenhum
comando tocou o banco de desenvolvimento ou de produção desta VM.

| Suíte | Exemplos | Falhas |
|---|---:|---:|
| `spec/services/widget/identity_token_service_spec.rb` (5.19) | 12 | 0 |
| `spec/requests/widget_identity_token_spec.rb` (5.19) | 13 | 0 |
| `spec/requests/api/v1/accounts/proactive_messages_spec.rb` (5.20) | 17 | 0 |
| `spec/controllers/concerns/bot_reads_own_conversation_spec.rb` (T-I6.4) | 3 | 0 |
| **Total** | **45** | **0** |

`bundle exec rubocop` nos arquivos dos dois blocos: **0 ofensas**.

**Regressão do 5.19:** 80 exemplos dos blocos 4.15 e 4.17 (enforcement nos três estados, pré-chat,
`Identity::EnforcementReport`, gate de origem de atributos) — **0 falhas**. É a suíte que mais
importa aqui, porque o 5.19 mexeu no `contacts_controller`, que é o coração do 4.15.

## 10. Sobre validar pelo IP da máquina

O aviso do coordenador (não validar por `127.0.0.1`, porque a safelist do `Rack::Attack` pula os
throttles) **vale para validação por HTTP real**. Os dois blocos foram verificados por request specs,
que não passam pelo middleware de throttle — então o risco que o aviso descreve não se aplica ao que
foi medido aqui, e **nenhuma afirmação deste relatório depende de uma requisição por `localhost`**.

O que **não** foi feito, e fica declarado: não subi servidor para exercitar `POST
/api/v1/accounts/:id/proactive_messages` pelo IP da máquina com throttle ativo. Se o coordenador
quiser essa verificação antes do deploy, ela é uma rota nova sob `Api::V1::Accounts::BaseController`
— o mesmo grupo de throttle das demais rotas de conta, e não um caminho novo de requisição.

## 11. O que fica pendente, e por quê

| Item | Estado | Razão |
|---|---|---|
| 5.19 — credencial por callback no SDK | **não entregue** | vive em `sdk/` (frente W) e tem gate de peso próprio (0.5). Contrato escrito no §7.6 para quem for fazer |
| 5.02, 5.11 | não iniciados | dependem de 0.10 (infra com sudo) |
| 5.12, 5.13 | não iniciados | dependem de 5.11 |

## 12. O que eu diria no `worker_done` desta dispatch — o canal segue indisponível

Tentativa de envio: **`No owning Orca client is connected to the relay`** (na dispatch anterior a
resposta foi `capability is revoked`). O handshake do relay funciona; não há coordenador do outro
lado. Pela regra da task — a entrega é o arquivo do relatório —, o conteúdo fica aqui.

**Status: 5.19 e 5.20 concluídos.** Dois commits locais na branch `o4-server-cred`:

- `a64acfb5c6` — 5.19, JWT como formato adicional
- `731a5c3fb9` — 5.20, proativa em uma chamada + bot lendo a própria conversa

Nenhum push, PR, deploy ou restart. **45 exemplos novos, 0 falhas.** Regressão medida maçã com maçã
nos dois blocos: 80 exemplos do 4.15/4.17 verdes no 5.19; 204 exemplos com **15 falhas antes e
depois, listas idênticas**, no 5.20.

**Três coisas que precisam da sua atenção:**

1. **A medição do plano para o 5.20 está desatualizada.** Ele diz 3 chamadas; nesta base são **2 ou
   3**, porque `POST /conversations` já aceita `message` embutido. A conclusão do bloco não muda — a
   redução de superfície continua valendo —, mas o número citado, sim.
2. **Um efeito colateral foi declarado morto, e é decisão de produto:**
   `self_assign_creator_for_reply_gate` não roda no disparo proativo. Se a intenção do gate for
   "toda conversa criada por alguém com token tem dono", isso precisa ser reaberto — e o lugar de
   reabrir é `Messages::ProactiveDispatchService`, com um teste que diga qual é o dono esperado.
3. **A "credencial por callback" do 5.19 não foi entregue**, porque vive em `sdk/` (frente W) e tem
   gate de peso próprio. O contrato para quem for fazer está no §7.6 — inclusive o nome do parâmetro
   que o backend **já aceita** hoje (`identity_token`), para que a outra ponta não invente um segundo.

**E uma coisa que não fiz:** não subi servidor para exercitar a rota nova pelo IP da máquina com
`Rack::Attack` ativo (§10). Nenhuma afirmação deste relatório depende de requisição por `localhost`,
mas essa verificação, se você a quiser antes do deploy, continua em aberto.
