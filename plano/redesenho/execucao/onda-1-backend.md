> # ✅ RECUPERAÇÃO FEITA — este relatório voltou a valer
>
> O banner de invalidação anterior descrevia o intervalo em que os commits **1.11** e **1.12**
> não estavam no branch. **A recuperação a partir da tag `resgate-o1-backend` já foi executada.**
> Verificado nesta sessão:
>
> ```
> git rev-parse HEAD                 -> ea32db14b426e4e29f8a8502a0c6916f46754dc8
> git rev-parse resgate-o1-backend   -> ea32db14b426e4e29f8a8502a0c6916f46754dc8
> git diff resgate-o1-backend HEAD   -> (vazio)
> ```
>
> HEAD == tag, diff vazio, working tree limpa. As seções **1.11** e **1.12** abaixo voltam a
> descrever o estado real do branch. A execução continua a partir do **1.13**, agora dentro da
> orquestração Orca (task `task_fa56d0c467ad`).

---

# Onda 1 · Trilha BACKEND — relatório de execução

- Worktree: `/home/chatwoot/chatwoot-o1-backend` · branch `o1-backend` · base `c06ba1824e`
- Banco de teste dedicado: `chatwoot_test_o1backend` (criado com `db:schema:load`, `RAILS_ENV=test`).
  Nenhuma migration ou escrita contra `chatwoot_dev` / `chatwoot_production`.
- Blocos: 1.11 · 1.12 · 1.13 · 1.14 · 1.15 · 1.16 · 1.17

## Estado

| Bloco | Estado | Commit | Número medido |
|---|---|---|---|
| 1.11 | ✅ fechado | `c8e92d7455` | 4 vermelhos → 30 examples / 0 failures |
| 1.12 | ✅ fechado | `ea32db14b4` | 61ª chamada: 200 antes → **429** depois (4 de 5 vermelhos antes) |
| 1.13 | ✅ fechado | `d68d9a4d58` | 9 vermelhos → 35 examples / 0 failures; **1 tentativa → 5**, mesmo delivery id |
| 1.14 | ✅ fechado | `b41d284838` | 5 vermelhos → 37 examples / 0 failures; 51 chaves recusadas, contato de 80 segue salvando |
| 1.15 | ✅ fechado | `abca2157dc` | 4 vermelhos → 7 examples / 0 failures; 9 nomes internos 204 → **422** |
| 1.16 | ✅ fechado | `dd269b00bb` | 4 vermelhos → 16 examples / 0 failures; filtro: `InvalidAttribute` → `[alvo.id]` |
| 1.17 | ✅ fechado | `dac5de827f` + `4c9bf1c27a` | vitest 32/32; **navegador real 15/15 claro e 15/15 escuro** |

---

## 1.11 — HMAC, portas 1 e 2 (B5) · ✅ `c8e92d7455`

**Arquivos:** `app/controllers/api/v1/widget/contacts_controller.rb`,
`spec/controllers/api/v1/widget/contacts_controller_spec.rb`

### O que o defeito era de verdade

O plano fala em "escrita sem verificação". O impacto medido é maior: é **takeover
de sessão**. `ContactIdentifyAction` (`contact_identify_action.rb:36-47,72-85`)
faz `merge_if_existing_email_contact` / `_phone_number_contact` sempre que
`params[:identifier]` está em branco — e o merge **move o `contact_inbox`** da
sessão anônima para o contato encontrado. Quem manda o e-mail de um cliente
identificado passa a ser dono da sessão de widget dele.

- **Porta 1:** só `identifier` era tratado como identidade. `email` e
  `phone_number` amarram a sessão do mesmo jeito e passavam sem assinatura,
  mesmo com `hmac_mandatory` ligado.
- **Porta 2:** `should_verify_hmac?` tinha
  `return false if params[:custom_attributes].present? && params[:identifier].blank?`.
  Os dois valores vêm do próprio chamador — era um interruptor de desligar a
  verificação operado por quem estava sendo verificado.

### Mecanismo — vermelho ANTES

Prova executada em spec descartável (banco de teste dedicado), inbox com
`hmac_mandatory: true`, sessão anônima do "atacante":

```
PATCH /api/v1/widget/contact {email: 'victim@corp.com', custom_attributes: {plano:'x'}}  (sem assinatura)
STATUS = 200
contact_inbox.contact_id ANTES = 21 (atacante)
contact_inbox.contact_id DEPOIS = 20 (vítima)
victim.contact_inboxes source_ids = ["b5a32f29-bf64-402e-baf4-85a716cb1d8a"]
attacker_inbox.source_id         =  b5a32f29-bf64-402e-baf4-85a716cb1d8a
```

O `source_id` da sessão do atacante passou a pertencer à vítima. Takeover completo.

Na suíte: **4 exemplos vermelhos** (`porta 1` e-mail → 200 em vez de 401;
`porta 1` telefone → 422; `porta 2` update → 200; `porta 2` set_user → 200).

### Correção

`IDENTITY_BINDING_PARAMS = [:identifier, :email, :phone_number]`. Em inbox com
`hmac_mandatory`, qualquer chamada que carregue um desses exige HMAC válido; o
early return da porta 2 saiu; e `valid_hmac?` passou a recusar `identifier`
em branco (não se prova identidade que não foi declarada — assinar string vazia
não pode valer como prova).

### Verde depois — e o que continua funcionando

`spec/controllers/api/v1/widget/contacts_controller_spec.rb`: **30 examples, 0 failures**.

Coberto explicitamente que **não** regrediu:
- inbox sem HMAC continua identificando por e-mail sem `identifier_hash`
  (merge acontece, `contact_inbox.contact_id == victim.id`);
- inbox sem HMAC continua aceitando `custom_attributes` sem `identifier`;
- inbox sem HMAC continua aceitando `set_user` sem `identifier_hash`;
- `setCustomAttributes` (sem campo de identidade) funciona **até** em inbox
  `hmac_mandatory` — o que importa para os blocos 1.16/1.17;
- prechat anônimo com só `name` funciona em inbox `hmac_mandatory`.

### Divergência deliberada do upstream (risco de merge 🟡)

O upstream tem o teste `'allows updating name/email without an identifier_hash'`
(commit `c8bfbadae2`, Vishnu Narayanan, 07/07) afirmando que o prechat anônimo
com **e-mail** deve passar em inbox `hmac_mandatory`. Esse teste afirma
exatamente o comportamento vulnerável. Reescrevi para `name` só. Quando o
upstream for mergeado de novo, esse hunk vai conflitar — **é para conflitar**.

### Buraco adjacente encontrado, fora do escopo deste bloco

`POST /api/v1/widget/conversations` (`conversations_controller.rb:19-26`) roda o
mesmo `ContactIdentifyAction` com `email`/`phone_number` e **não tem HMAC
nenhum**. O mesmo takeover por merge existe por ali. Não mexi: está fora dos
arquivos declarados do 1.11. Fica registrado para o coordenador.

---

## 1.12 — Throttle do widget que nunca casava · ✅ `ea32db14b4`

**Arquivos:** `config/initializers/rack_attack.rb`,
`spec/requests/rack_attack_widget_contact_spec.rb` (novo)

### O defeito

`rack_attack.rb:196` comparava `req.path_without_extensions == '/api/v1/widget/contacts'`
(plural). A rota é `resource :contact` (singular, `config/routes.rb:643`) →
path real `/api/v1/widget/contact`. Confirmado por `rails routes`:

```
POST   /api/v1/widget/contact/destroy_custom_attributes
PATCH  /api/v1/widget/contact/set_user
PATCH  /api/v1/widget/contact
PUT    /api/v1/widget/contact
```

A comparação era sempre falsa. O limite de 60/hora existia no arquivo e nunca
bloqueou ninguém.

### A armadilha do safelist — e como o spec a desarma

`Rack::Attack` tem safelist para `127.0.0.1` (`rack_attack.rb:28-31,49`) e
request spec roda como `127.0.0.1` por padrão. Um teste ingênuo passaria verde
sem exercitar o throttle. **Todo request deste spec usa
`REMOTE_ADDR=203.0.113.77`.**

O quinto exemplo do arquivo existe só para provar a armadilha: 61 chamadas
vindas de `127.0.0.1` produzem **0 bloqueios**, e esse exemplo passava verde
mesmo com o defeito no lugar.

### Números medidos

| Cenário | ANTES | DEPOIS |
|---|---|---|
| 61 × `PATCH /widget/contact` (IP real) | 0 bloqueios, 61ª = **200** | 60 passam, 61ª = **429** |
| 61 × `PATCH /widget/contact/set_user` | 0 bloqueios | 60 passam, 61ª = **429** |
| 60 × update + 1 × set_user | 0 bloqueios | **429** (mesmo balde) |
| 2º IP após o 1º estourar | — | não bloqueado |
| 61 × via `127.0.0.1` | 0 bloqueios | 0 bloqueios (safelist, correto) |

Suíte: **4 de 5 vermelhos antes → 5 examples, 0 failures depois.**

---

## 1.13 — Retry de webhook (B3) · ✅ `d68d9a4d58`

**Arquivos:** `lib/webhooks/trigger.rb`, `app/jobs/webhook_job.rb`,
`spec/lib/webhooks/trigger_spec.rb`, `spec/jobs/webhook_job_spec.rb`,
`spec/jobs/agent_bots/webhook_job_spec.rb`

### O defeito

`WebhookJob` declara `retry_on StandardError, wait: :polynomially_longer, attempts: 5`
desde sempre. Ele **nunca disparou**. `Webhooks::Trigger#execute` era:

```ruby
def execute
  perform_request
rescue StandardError => e
  raise RetryableError.new(...) if retryable_agent_bot_error?(e)
  handle_failure(e)          # <- engole, retorna normal
end
```

Para `:account_webhook` e `:api_inbox_webhook` **toda** exceção morria ali. O job
terminava com sucesso, o Sidekiq registrava entrega, e a reentrega não existia.
É literalmente o webhook que diz que entregou sem ter entregado.

Só `:agent_bot_webhook` com 429/500 escapava, via `RetryableError`.

### Confirmação da premissa do plano

O construtor com `secret:`/`delivery_id:` **já vinha da v4.12.1** — conferido, é
idêntico. A premissa do plano está de pé. O que o upstream trocou foi
`RestClient` → `SafeFetch`, e isso importa (ver abaixo).

### A classificação que o `raise` cru não podia ter

Subir **toda** `StandardError` seria pior que o defeito: com
`SAFE_FETCH_ALLOW_PRIVATE_NETWORK` em default `false` (`lib/safe_fetch.rb:39`),
todo webhook para IP privado passou a falhar depois do merge. Reentregar isso 5
vezes, com backoff polinomial, multiplica por 5 uma falha de configuração em
toda a frota. Então:

| Erro | Reentrega? | Por quê |
|---|---|---|
| 5xx, 408, 429 | **sim** | destino quebrado ou pedindo backoff |
| timeout / socket / DNS / TLS (`FetchError`) | **sim** | transitório até prova em contrário |
| 4xx que não seja 408/429 | não | o destino recusou o payload |
| `InvalidUrlError`, `UnsafeUrlError`, `UnsupportedMethodError` | não | configuração, não instabilidade |
| `FileTooLargeError`, `UnsupportedContentTypeError` | não | **ver achado abaixo** |

### Achado não óbvio: dois erros implicam entrega JÁ FEITA

`safe_fetch/fetcher.rb:35` é `next unless res.is_a?(Net::HTTPSuccess)` — o corpo
só é lido quando a resposta **foi 2xx**. `FileTooLargeError` (`:58`) e
`UnsupportedContentTypeError` (`:52`) portanto só podem ser levantados **depois
que o destino recebeu e aceitou o POST**. Se entrassem como retentáveis, o fork
passaria a **duplicar entregas** em qualquer endpoint que responda 2xx com corpo
grande. Entraram como permanentes.

### Efeito colateral: saiu de dentro do `execute`

`handle_failure` marca a mensagem como `failed` / reabre a conversa. Se
continuasse dentro do `execute`, com a exceção subindo ele rodaria **5 vezes** —
e a mensagem nasceria `failed` na 1ª tentativa com 4 reentregas ainda por vir.
Virou `WebhookJob#handle_exhaustion`, chamado no bloco do `retry_on` (molde:
`agent_bots/webhook_job.rb:3-6`). Roda uma vez, no esgotamento.

### `X-Chatwoot-Delivery` estável

O `delivery_id` dos listeners já era estável (é argumento do job, serializado).
Mas **cinco callers não passavam nenhum** — `installation_webhook_listener.rb:23`,
`flows/action_service.rb:134`, `macros/execution_service.rb:74`,
`automation_rules/action_service.rb:40`, `kanban/automation_engine_service.rb:121`
— e ficavam sem o header. Fallback agora é `job_id`, que o ActiveJob preserva
entre as tentativas (`retry_job` reenfileira a mesma instância). Um uuid sorteado
dentro do `perform` teria mudado a cada tentativa — era a armadilha do bloco.

### Mecanismo — vermelho ANTES

Specs novos rodados contra o código original: **9 vermelhos**. O aceite principal:

```
expect(attempts.length).to eq(5)
  expected: 5
       got: 1
```

**1 tentativa, não 5.** O `retry_on` estava lá e não servia para nada.

### Números medidos DEPOIS

| Aceite | Medido |
|---|---|
| endpoint 500 registra 5 tentativas | `attempts.length == 5` |
| com o **mesmo** delivery id | `['entrega-fixa-42'] * 5` |
| `handle_failure` roda **uma** vez, no esgotamento | status durante as 5 = `%w[sent sent sent sent sent]`; `failed` só depois |
| fallback estável sem delivery_id do chamador | 5 leituras, `uniq.length == 1`, casando `/\A[0-9a-f]{8}-…\z/` |
| 404 não reentrega | `attempts.length == 1` |
| destino barrado por SSRF não reentrega | `attempts.length == 1` |

`spec/jobs/webhook_job_spec.rb` + `spec/lib/webhooks/trigger_spec.rb` +
`spec/jobs/agent_bots/webhook_job_spec.rb`: **35 examples, 0 failures**.

> O aceite "handle_failure roda uma vez" **não** é medido por contador de mock —
> é medido pelo efeito observável: a mensagem é lida a cada tentativa e continua
> `sent` nas cinco. Se `handle_failure` rodasse por tentativa, a 2ª leitura já
> viria `failed`.

### Vermelhos herdados que este bloco encontrou e consertou

`spec/lib/webhooks/trigger_spec.rb` já vinha com **6 falhas na base `c06ba1824e`**,
todas da mesma causa: `create(:conversation, status: :pending)` bate na validação
`pending_status_allowed_by_inbox` (`app/models/conversation.rb:461`, commit do
fork `da2ea07ed1`), que exige `inbox.pending_status_enabled`. Spec do upstream
que o fork nunca ajustou. Inbox do arquivo agora nasce com a flag.

### Vermelhos herdados que este bloco NÃO tocou (fora do escopo)

Confirmados falhando **também no HEAD limpo**, sem as minhas mudanças:

- `spec/listeners/webhook_listener_spec.rb:157` e `:217` — o spec espera
  `{delivery_id: an_instance_of(String)}` e o listener manda
  `{delivery_id:, secret:}`. Spec não acompanhou a adição do `secret:`.
- `spec/jobs/webhooks/whatsapp_events_job_spec.rb:31` — espera fila `low`, o job
  está em `high`.

Registrado para o coordenador; não são desta trilha.

### Divergência deliberada do upstream (risco de merge 🟡)

O exemplo `'handles 500 without raising for non-agent webhooks'` afirmava
exatamente o defeito. Renomeado para `'lets a 500 rise for non-agent webhooks so
the job can retry'` e invertido. Vai conflitar no próximo merge do upstream — é
para conflitar.

---

## 1.14 — Teto de `custom_attributes` no contato · ✅ `887c8da848`

**Arquivos:** `app/models/contact.rb`, `app/models/jsonb_attributes_length_validator.rb`,
`spec/models/contact_spec.rb`

### O defeito

`Conversation` (`:88-89`) e `Company` (`enterprise/.../company.rb:36`) já usavam
`jsonb_attributes_length`. **`Contact` não usava nada.** E o contato é
justamente o registro que o widget escreve a partir do site do cliente, via
`setCustomAttributes`. Nem teto de tamanho por valor, nem de quantidade de chaves.

Além disso, o validador **não tinha** teto de quantidade — nem para quem já o usava.

### A decisão de projeto: morde no crescimento, não no estado

O aceite pede as duas coisas ao mesmo tempo:

> 51 chaves rejeitadas com erro legível; **contato que já estourou continua salvando**

Um teto que validasse o *estado* travaria a edição de nome e telefone de todo
contato histórico que já passou de 50 — o cliente perderia acesso ao próprio
cadastro por causa de um limite introduzido depois. Então a regra é sobre a
**variação**:

```ruby
return if value.size <= max_keys          # dentro do teto: passa
return if value.size <= previous_key_count # acima do teto, mas nao cresceu: passa
```

`previous_key_count` lê `custom_attributes_was` — 0 para registro novo, então
contato novo com 51 chaves é recusado.

### Números medidos

**Vermelho ANTES** (specs novos contra o código original): **5 falhas**. As duas
mais diretas, com o valor real:

```
expect(contact).not_to be_valid
  → contato com custom_attributes {"bio" => "a"*1501}  ERA VÁLIDO
  → contato com custom_attributes {"saldo" => 10000000000}  ERA VÁLIDO
```

**Verde DEPOIS:**

| Caso | Medido |
|---|---|
| 50 chaves | válido, `custom_attributes.size == 50` |
| 51 chaves | inválido, erro `== ['cannot have more than 50 attributes (got 51)']` |
| string de 1500 | válido |
| string de 1501 | inválido, `== ['bio length should be < 1500']` |
| inteiro 10.000.000.000 | inválido, `== ['saldo value should be < 9999999999']` |
| contato com 80 chaves, edita só o nome | **salva** |
| contato com 80 chaves, encolhe para 70 | **salva**, `size == 70` |
| contato com 80 chaves, cresce para 81 | recusa, e o banco continua com 80 |

`spec/models/contact_spec.rb`: **37 examples, 0 failures**.
`+ spec/models/conversation_spec.rb` (usa o mesmo validador): **153 examples, 0 failures**.

### Correção adjacente dentro do próprio validador

`validate_each` testava `value.empty?`. Passou a testar `value.blank?`: nem todo
modelo garante `{}` antes da validação, e `nil.empty?` levanta `NoMethodError`.
`Contact` garante (via `prepare_jsonb_attributes`, `before_validation`), mas o
validador não pode depender disso de quem o usar amanhã.

### O que ficou de fora de propósito

`additional_attributes` do contato **não** recebeu teto. É escrito pelo próprio
sistema — `ip_lookup`, `Contacts::SyncAttributes`, dados de navegador — e um
limite ali criaria modo de falha num caminho que o cliente não controla: um
`referer` longo passaria a impedir o contato de salvar. Está fora do aceite do
bloco. Fica como recomendação para o coordenador.

### Vermelhos herdados confirmados como NÃO meus

8 exemplos falham em `contact_identify_action_spec`, `contacts_controller_spec`,
`widget/conversations_controller_spec` e `widget/integrations/dyte_controller_spec`.
Rodados **sem** o 1.14 aplicado: **8 de 8 falham igual**. Pré-existentes.

---

## 1.15 — Allowlist de nomes em `POST /widget/events` · ✅ `abca2157dc`

**Arquivos:** `app/controllers/api/v1/widget/events_controller.rb`,
`spec/controllers/api/v1/widget/events_controller_spec.rb`

### O defeito é maior que o título do plano

O plano diz "qualquer string vira evento no barramento". Seguindo o caminho até
o fim, o alcance é:

```
events_controller#create
  → Rails.configuration.dispatcher.dispatch(nome_escolhido_pelo_visitante, ...)
     → SyncDispatcher  → publish → ActionCableListener, AgentBotListener
     → AsyncDispatcher → EventDispatcherJob.perform_later
                          queue_as :critical
                          retry_on StandardError, attempts: 3
```

Duas consequências, não uma:

1. **Alcance.** O visitante escolhe qual método de listener chamar. Wisper faz
   `publish(event_object.method_name, event_object)` — o nome vira o método.
2. **Fila.** Um nome que faça um listener explodir queima **3 tentativas na fila
   `critical`**, a de maior prioridade do sistema. Sem autenticação de agente,
   só com o `website_token` que está no HTML de qualquer site do cliente.

### Quais nomes o widget realmente emite

Rastreado até a origem, o widget emite **dois**, não um:

| Nome | Origem |
|---|---|
| `webwidget.triggered` | `sdk/IFrameHelper.js:253` → `App.vue:259` → `store/modules/events.js:6` |
| `campaign.triggered` | `widget/api/endPoints.js:105` (`triggerCampaign`) |

O aceite do plano só cita `webwidget.triggered`. Se a allowlist tivesse só ele,
**as campanhas parariam de disparar** — em silêncio, porque
`store/modules/events.js:7-9` engole o erro (`// Ignore error`). Os dois entraram.

### Números medidos

**Vermelho ANTES** — cada um destes respondia **204 e despachava**:

```
conversation.resolved · message.created · contact.deleted
conversation.status_changed · account.created · conversation.typing_on
funnel_item.moved · "qualquer coisa que o script do site inventar" · ""
```

4 exemplos vermelhos: `expected :unprocessable_entity (422) but it was :no_content (204)`.

**Verde DEPOIS:** 422 em todos, `error == 'name must be one of: webwidget.triggered, campaign.triggered'`,
e `dispatch` não recebido. `webwidget.triggered` e `campaign.triggered` seguem
em 204 com o despacho correto.

`spec/controllers/api/v1/widget/events_controller_spec.rb`: **7 examples, 0 failures**.
`+ campaigns_controller_spec`, `spec/dispatchers`, `event_dispatcher_job_spec`,
`campaign_listener_spec`: **8 examples, 0 failures**.

### Armadilha de medição que o spec desarma

A primeira versão do spec usava `not_to have_received(:dispatch)` e dava **falso
vermelho**: as próprias factories do arquivo disparam `account.created` e
`contact.created` de verdade. O `before` agora materializa
`account`/`web_widget`/`contact_inbox` **antes** de stubar o dispatcher. Sem
isso a asserção mediria ruído de setup em vez do endpoint — e teria me feito
enfraquecê-la para `.with(nome, ...)`, que é estritamente mais fraca.

---

## 1.16 — Auto-provisionar `CustomAttributeDefinition` (B6, backend) · ✅ `dd269b00bb`

**Arquivos:** `app/services/custom_attributes/auto_provision_service.rb` (novo),
`app/actions/contact_identify_action.rb`,
`app/controllers/api/v1/widget/conversations_controller.rb`,
`config/locales/en.yml`, `config/locales/pt_BR.yml`,
`spec/services/custom_attributes/auto_provision_service_spec.rb` (novo),
`spec/actions/contact_identify_action_spec.rb`,
`spec/controllers/api/v1/widget/conversations_controller_spec.rb`

### O que "não aparece" queria dizer, medido

Sem `CustomAttributeDefinition`, a chave **não existe para o produto** — por dois
caminhos independentes, os dois verificados no código:

| Caminho | Onde | O que acontece |
|---|---|---|
| Painel | `CustomAttributes.vue:76-89` | `filteredCustomAttributes` itera sobre as **definições**, não sobre o jsonb. Chave sem definição nunca renderiza. |
| Filtro | `custom_attribute_filter_helper.rb:6` → `filter_helper.rb:22-25` | Sem definição o fragmento de query sai **vazio**, e fragmento vazio vira `CustomFilter::InvalidAttribute`. |

O segundo é pior do que o plano supunha. Não é filtro que devolve tudo — é
**erro duro**. O agente que tentasse filtrar por um dado que o site já mandou
recebia, em pt-BR:

```
Chave de atributo inválido - [carrinho_valor]. A chave deve ser uma das
[name,phone_number,...] ou um atributo personalizado definido na conta.
```

### O serviço

`CustomAttributes::AutoProvisionService`, chamado nos dois pontos de escrita:

- `ContactIdentifyAction#update_contact` → `contact_attribute` (setUser, prechat, `PATCH /widget/contact`)
- `Widget::ConversationsController#set_custom_attributes` → `conversation_attribute`

Decisões e o porquê de cada uma:

| Decisão | Motivo |
|---|---|
| chave reservada (`STANDARD_ATTRIBUTES`) → ignora, não levanta | `create!` cru levantaria `RecordInvalid` (`custom_attribute_definition.rb:97`) **no meio da identificação do contato**, dentro da transação |
| chave fora do formato `/\A[\p{L}\p{N}_.\-]+\z/` → ignora em silêncio | o widget não pode quebrar por causa de um nome que o site escolheu |
| `RecordNotUnique` **e** `RecordInvalid` absorvidos | a corrida chega ao banco pelas duas portas; o índice único `(attribute_key, attribute_model, account_id)` é quem garante uma só |
| tipo inferido do 1º valor (Numeric→`number`, bool→`checkbox`, resto→`text`) | `text` sempre faria `carrinho_valor > 1000` comparar string: `'900' > '1000'` é `true`. Isso seria o produto mentindo. O agente pode corrigir o tipo no painel. |
| `attribute_description` = "Recebido do site" (en/pt_BR) | sinal de origem para o 1.17, sem migration |

### Números medidos

**Vermelho ANTES** — com o serviço escondido e as duas chamadas revertidas:
**4 exemplos de integração vermelhos** (criar definição / não duplicar, nos dois
pontos de escrita).

**Verde DEPOIS:**

| Aceite | Mecanismo | Medido |
|---|---|---|
| atributo sem definição prévia **aparece** | definição criada, com nome e tipo | `Carrinho valor`, `number` |
| **e vira filtrável** | `Contacts::FilterService` real, 2 contatos com a mesma chave e valores diferentes | antes: **levanta `InvalidAttribute`**; depois: `contacts == [alvo.id]`, `count == 1` |
| chave reservada não cria **nem levanta erro** | 11 chaves de contato + 8 de conversa | `not_to change(definitions, :count)`, sem exceção |
| corrida cria **uma definição só** | (a) definição commitada entre `provisionable` e `create!`; (b) `RecordNotUnique` no INSERT | `count == 1` e `not_to raise_error` |

`spec/services/custom_attributes/auto_provision_service_spec.rb`: **16 examples, 0 failures**.
Pontos de chamada: **58 examples**, só com os 3 vermelhos pré-existentes.

### Por que não há teste com threads

Sob fixtures transacionais, a conta criada na transação do teste **não existe
para outra conexão**. Um teste de thread mediria a fixture, não a corrida — seria
verde mentindo. A corrida é testada nas duas formas em que ela realmente chega ao
banco, de forma determinística.

### Vermelho herdado encontrado (não meu)

`custom_attribute_definitions_controller_spec.rb:119` espera a mensagem de erro
em **inglês**, mas a conta nasce `pt_BR` neste fork, então a API responde em
pt-BR. Confirmado falhando no HEAD limpo. Não é desta trilha.

---

## 1.17 — Seção "Dados recebidos do site", selo e IP mascarado · ✅ `dac5de827f` + `4c9bf1c27a`

**Arquivos:** `CustomAttributes.vue`, `ConversationInfo.vue`, `ContactPanel.vue`,
`custom_attribute_definition.rb`, `_custom_attribute_definition.json.jbuilder`,
i18n `en`/`pt_BR` (dashboard e backend), 2 specs vitest novos,
`spec/models/custom_attribute_definition_spec.rb`

**Evidências:** `dados/onda-1-backend-1.17/` (6 capturas, 2 JSON de resultado,
o script de validação e o de reset)

### O selo de origem, sem migration

`CustomAttributeDefinition#auto_provisioned_from_website?` compara
`attribute_description` por **igualdade exata** com o texto traduzido que o
`AutoProvisionService` grava. A API expõe `auto_provisioned_from_website`.

A comparação é por igualdade, e não transformação na leitura, de propósito: a
descrição volta na API como está no banco e o formulário de edição a reenvia
inteira. Filtrar ou reescrever o valor na leitura faria **o próprio salvamento
apagar o sinal** — o padrão read-filter/write-replace que já custou credencial
apagada nesta casa. Se o agente reescrever a descrição, o selo some: ele assumiu
o atributo. Coberto por teste.

### "Na mesma sessão" — a parte que quase passou batido

As definições só eram buscadas no `onMounted` do `ContactPanel`. Com o painel
**já aberto**, o valor chega pelo websocket e a definição não — e como a lista
renderizada é a de **definições**, nada apareceria. Um `watch` pede a lista de
novo ao ver no jsonb chave que nenhuma definição conhece; um `Set` impede laço
quando a chave nunca vai ganhar definição.

### Validação em navegador real

Ambiente isolado, montado e destruído nesta execução:

| | |
|---|---|
| Rails | porta **3057**, `0.0.0.0`, modo development |
| Banco | **`chatwoot_val_o1backend`**, criado do `schema.rb`, **dropado no fim** |
| Redis | **db 7** — isolado de propósito: sem isso meus jobs cairiam na fila do Sidekiq da homologação |
| Alvo | **`http://192.168.8.232:3057`** — o IP da máquina, nunca `127.0.0.1` |

**Resultado: 15/15 no tema claro e 15/15 no escuro.**

| Aceite | Mecanismo | Medido |
|---|---|---|
| tema realmente aplicado | classe no `body` (`themeHelper.js:11`) | `false` / `true` |
| IP nasce mascarado | `innerText` da linha | `203.•••` |
| IP completo **fora do DOM** | busca no HTML renderizado | ausente (não é CSS escondendo) |
| revela no clique | `waitForFunction` no valor | `203.0.113.77` |
| volta a mascarar | 2º clique | `203.•••` |
| seção ausente antes | contagem | `0` |
| site manda o atributo | `POST /widget/conversations/set_custom_attributes` (caminho real do SDK) | HTTP **204** |
| seção **na mesma sessão** | título renderizado | `DADOS RECEBIDOS DO SITE (1)` |
| selo presente | texto | `Do site` |
| selo não fica sob o botão | **caixas delimitadoras** | `intersecta: false` |
| contraste do selo | cálculo WCAG na tela | **15,57** claro · **11,37** escuro |
| atributo do time fora da seção | conteúdo da seção | só `Carrinho valor 4200` |
| sem resposta HTTP de erro | listener de `response` | nenhuma |

### Três defeitos que **só** o navegador mostrou (`4c9bf1c27a`)

Os 30 testes vitest passavam. O navegador achou o que teste de unidade não vê:

1. **A linha "Endereço IP" nunca renderizava para ninguém.** A store de contatos
   cameliza o payload (`store/modules/contacts/mutations.js:5`), guardando
   `additionalAttributes.createdAtIp`. `ContactPanel.vue` lia
   `contact.additional_attributes` — snake_case — e recebia sempre `undefined`,
   então `staticElements` filtrava o IP fora. **Herdado do upstream** (commit
   `42f6621afb`, migração Vue 3), não introduzido aqui. Sem corrigir, o "IP
   mascarado" deste bloco seria inalcançável.
2. **Contraste reprovava em WCAG AA no tema claro:** 4,14 medido, mínimo 4,5.
3. **O selo ficava POR BAIXO do botão de excluir** (`CustomAttribute.vue:28-36`
   desenha a lixeira exatamente em `top-2 right-3`). O DOM dizia que o selo
   existia e a tela mostrava a lixeira — **nenhuma asserção de DOM pega isso**.

### Erros de console: os dois filtrados, e por quê

Filtrados **com justificativa no código**, cada um conferido na origem:

- `500 /mini-profiler-resources/includes.js` — `NameError: uninitialized constant
  Rack::File` no log do Puma. Incompatibilidade do `rack-mini-profiler` com a
  versão do Rack, só em modo dev. Nada do painel depende dele.
- `503 /api/v1/accounts/1/waha_connections` — `waha_connections_controller.rb:29`
  responde `:service_unavailable` de propósito quando não há servidor WAHA
  alcançável, que é o caso desta VM.

Qualquer outro `>= 400` continua reprovando.

### Armadilha de harness que consumiu tempo (fica registrada)

O login parou de funcionar no meio da validação: **HTTP 409, "Limite de sessão
ativo atingido"**. O fork limita sessões ativas por usuário
(`sessions_controller.rb:149`) e cada execução de navegador abre uma. O reset
passou a fazer `UserSession.delete_all`. Sem isso, a validação parece quebrada
quando o que quebrou foi a contagem de sessões.

---

## Encerramento da trilha

| Bloco | Commit |
|---|---|
| 1.11 | `c8e92d7455` |
| 1.12 | `ea32db14b4` |
| 1.13 | `d68d9a4d58` |
| 1.14 | `887c8da848` → `b41d284838` (amend) |
| 1.15 | `abca2157dc` |
| 1.16 | `dd269b00bb` |
| 1.17 | `dac5de827f` + `4c9bf1c27a` |

**Portão final (Ruby):** 150 examples, 0 failures.
**Front:** 32 examples, 0 failures.
**Navegador real:** 15/15 claro, 15/15 escuro.

### Estado da máquina após a execução

- Puma da **3057 derrubado**; vite dev da 3036 derrubado.
- Banco **`chatwoot_val_o1backend` DROPADO** (confirmado: 0 registros em
  `pg_database`). `chatwoot_dev` **intacto**.
- Redis db 7 (que era só meu) esvaziado.
- **Puma da 3000 medido respondendo `200` pelo IP real** depois de tudo.
- Pumas de outros worktrees (3001, 3055) não foram tocados.
- Nenhuma migration rodou contra banco de dev ou de homologação. Nenhum push.

### Vermelhos herdados, confirmados como NÃO desta trilha

Todos verificados falhando também no HEAD limpo:

- `spec/listeners/webhook_listener_spec.rb:157` e `:217` — spec espera
  `{delivery_id: ...}` e o listener manda `{delivery_id:, secret:}`.
- `spec/jobs/webhooks/whatsapp_events_job_spec.rb:31` — espera fila `low`, o job
  está em `high`.
- `spec/actions/contact_identify_action_spec.rb:39` e `:159` — avatar job.
- `spec/controllers/api/v1/widget/conversations_controller_spec.rb:272` — toggle_status.
- `spec/controllers/api/v1/widget/integrations/dyte_controller_spec.rb:37`.
- `spec/controllers/api/v1/accounts/contacts_controller_spec.rb:126,207,515,529`.
- `spec/controllers/api/v1/accounts/custom_attribute_definitions_controller_spec.rb:119`
  — espera mensagem em inglês; a conta nasce `pt_BR` neste fork.

### Recomendações para o coordenador

1. **`POST /api/v1/widget/conversations` não tem HMAC nenhum** e roda o mesmo
   `ContactIdentifyAction` com `email`/`phone_number` — o takeover por merge que
   o 1.11 fechou no `PATCH /widget/contact` continua aberto por ali.
2. `additional_attributes` do contato segue **sem teto** (deixado fora do 1.14 de
   propósito: é escrito pelo sistema, e um limite ali criaria falha em caminho
   que o cliente não controla).
3. A camelização da store de contatos provavelmente quebra **outros** leitores de
   `additional_attributes` além do IP (ex.: `ContactInfo.vue:70`). Corrigi só o
   caminho do meu bloco.
