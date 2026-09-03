# Auditoria WhatsApp Cloud API — Tarefa 2/3: código de roteamento de entrada + UI

**Escopo:** somente leitura. Nenhum arquivo de código foi alterado.
**Repo:** `/home/chatwoot/chatwoot` — branch de referência: `producao`.
**Caso:** Account 6 (Tozi), inbox 91 "TOZI FIXC" e inbox 99 "TOZI IMOVEIS MKT 1", ambas WhatsApp Cloud API, aparentemente no mesmo WABA. Sintoma relatado: cadastrar o webhook da 99 faz a 91 parar de receber.

> **Nota sobre numeração de linhas.** O working tree está na branch `homologacao`. Os arquivos Ruby/Vue citados são **byte-idênticos** entre `homologacao` e `producao` — exceto `config/routes.rb`, que tem WIP local não relacionado. Para `config/routes.rb` cito as linhas de **`producao`** e indico entre parênteses a linha equivalente no working tree.

---

## 1. Diagrama do fluxo de entrada

```
                    Meta (Cloud API)
                          │
                          │  POST https://<FRONTEND_URL>/webhooks/whatsapp/<NUMERO-DA-URL>
                          │  body: { object: "whatsapp_business_account",
                          │          entry:[{ changes:[{ value:{ metadata:{
                          │                     display_phone_number, phone_number_id }}}]}] }
                          ▼
  config/routes.rb:772 (worktree 780)
  post 'webhooks/whatsapp/:phone_number' -> webhooks/whatsapp#process_payload
                          │
                          ▼
  Webhooks::WhatsappController#process_payload   (whatsapp_controller.rb:4-13)
    ├─ inactive_whatsapp_number?  ← USA params[:phone_number] DA URL   (:23-32)
    │     └─ se o número DA URL estiver em GlobalConfig INACTIVE_WHATSAPP_NUMBERS
    │        => 422 e o payload MORRE AQUI (independente de quem o enviou)
    └─ Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)   (:11)
                          │   (params carrega tanto o :phone_number da URL quanto o payload)
                          ▼
  Webhooks::WhatsappEventsJob#perform            (whatsapp_events_job.rb:12-31)
    └─ find_channel_from_whatsapp_business_payload(params)               (:118-125)
         ├─ params[:object] == 'whatsapp_business_account'  ──► get_channel_from_wb_payload  (:127-133)
         │      phone_number = "+" + value.metadata.display_phone_number   (:128)
         │      channel      = Channel::Whatsapp.find_by(phone_number:)    (:130)
         │      return channel SOMENTE SE provider_config['phone_number_id'] == metadata.phone_number_id  (:132)
         │      ► senão retorna nil  (fall-through implícito, SEM fallback para a URL)
         └─ senão (payload não-Cloud) ──► find_channel_by_url_param  (:112-116)  ← aí sim usa a URL
                          │
                          ▼
    channel_is_inactive?(channel)                                        (:104-110)
      nil / reauthorization_required? / conta inativa  =>  Rails.logger.warn + return  (:15-18)
                          │
                          ▼
    process_events -> handle_message_events                              (:33-39, :83-90)
      provider == 'whatsapp_cloud' -> Whatsapp::IncomingMessageWhatsappCloudService
                                        .new(inbox: channel.inbox, params:)  (:86)
                          │
                          ▼
  Whatsapp::IncomingMessageWhatsappCloudService  (incoming_message_whatsapp_cloud_service.rb:7-9)
    processed_params = params[:entry][0]['changes'][0]['value']
    -> Whatsapp::IncomingMessageBaseService  ->  Contact / Conversation / Message
                          │
                          ▼
                    INBOX DE DESTINO
```

Ou seja: a URL só decide **se o payload é aceito** (guarda de número inativo) e **quem valida o GET de verificação**. Quem decide **a inbox** é o payload.

---

## 2. VEREDITO 1 — a resolução de inbox usa a URL ou o payload?

### **Usa o PAYLOAD.** A URL é ignorada para escolher a inbox em todo payload Cloud API.

Evidência primária — `app/jobs/webhooks/whatsapp_events_job.rb:118-133`:

```ruby
118  def find_channel_from_whatsapp_business_payload(params)
119    # for the case where facebook cloud api support multiple numbers for a single app
120    # https://github.com/chatwoot/chatwoot/issues/4712#issuecomment-1173838350
121    # we will give priority to the phone_number in the payload
122    return get_channel_from_wb_payload(params) if params[:object] == 'whatsapp_business_account'
123
124    find_channel_by_url_param(params)
125  end
126
127  def get_channel_from_wb_payload(wb_params)
128    phone_number = "+#{wb_params[:entry].first[:changes].first.dig(:value, :metadata, :display_phone_number)}"
129    phone_number_id = wb_params[:entry].first[:changes].first.dig(:value, :metadata, :phone_number_id)
130    channel = Channel::Whatsapp.find_by(phone_number: phone_number)
131    # validate to ensure the phone number id matches the whatsapp channel
132    return channel if channel && channel.provider_config['phone_number_id'] == phone_number_id
133  end
```

O comentário nas linhas 119-121 é explícito: o suporte a **vários números num mesmo app** foi o motivo original de priorizar o payload (issue upstream #4712, 2022).

Confirmação em teste — `spec/jobs/webhooks/whatsapp_events_job_spec.rb:113-137`: o spec monta um payload com `phone_number: channel.phone_number` na URL mas `metadata` de **outro** canal, e espera que o serviço seja instanciado com `inbox: other_channel.inbox`. O nome do teste é literalmente *"enqueue Whatsapp::IncomingMessageWhatsappCloudService based on the number in payload"*.

O `find_channel_by_url_param` (`:112-116`) só é alcançado quando `params[:object] != 'whatsapp_business_account'` — isto é, provider 360dialog/`default`, não Cloud API.

### Comportamento quando o `phone_number_id` do payload não corresponde

`get_channel_from_wb_payload` termina sem `else`: se o canal não é encontrado por `display_phone_number`, **ou** se é encontrado mas `provider_config['phone_number_id']` diverge, o método retorna `nil` (linha 132 é a última expressão; um `return channel if …` falso devolve `nil`). **Não há fallback para o `:phone_number` da URL.**

O `nil` então cai em `channel_is_inactive?` (`:104-110`), que retorna `true` para canal em branco, e o job encerra em `:15-18`:

```ruby
15  if channel_is_inactive?(channel)
16    Rails.logger.warn("Inactive WhatsApp channel: #{channel&.phone_number || "unknown - #{params[:phone_number]}"}")
17    return
18  end
```

Portanto, na divergência:
- **não** cria mensagem na inbox errada;
- **não** levanta erro, **não** vai para a fila morta, **não** notifica ninguém;
- registra **um único `warn`** — e o texto do log usa `params[:phone_number]`, ou seja, o número **da URL**, não o do payload. Isso é uma armadilha de diagnóstico: com uma URL compartilhada, todo descarte aparece no log com o nome do número **dono da URL**, mesmo quando o evento era do outro número.
- O HTTP para o Meta já respondeu `200` no controller (`whatsapp_controller.rb:12`) antes do job rodar, então o Meta **não** reenvia. A mensagem é perdida em silêncio.

Esse é o único ponto do caminho de entrada capaz de "sumir" com mensagens de uma inbox — e ele depende de `provider_config['phone_number_id']` e `phone_number` estarem corretos no registro, **não** de qual URL o Meta chamou.

### Riscos secundários na resolução (mesma função)

1. **Formato do telefone (linha 128).** O código faz `"+" + display_phone_number` e compara com `channel.phone_number` por igualdade exata. Se o Meta entregar `display_phone_number` formatado (`"+55 11 9…"`, com espaços/hífens) ou já com `+`, o `find_by` da linha 130 falha e o evento é descartado silenciosamente. Só uma inspeção de payload real fecha esse ponto (tarefa 1/3).
2. **Só o primeiro `entry`/`changes` (linhas 128-129).** O Meta pode agrupar vários `entry` — inclusive **de números diferentes do mesmo WABA** — num único POST. O job lê apenas `entry.first.changes.first` para escolher o canal e depois entrega o payload **inteiro** ao `IncomingMessageWhatsappCloudService`, que também só lê `entry[0].changes[0].value` (`incoming_message_whatsapp_cloud_service.rb:7-9`). Num POST agrupado, tudo além do primeiro bloco é ignorado. Esse risco **cresce** com dois números no mesmo WABA apontando para a mesma URL.
3. **`reauthorization_required?` (linha 106).** É uma flag em **Redis** (`app/models/concerns/reauthorizable.rb:19-21`), setada por `prompt_reauthorization!`. `Channel::Whatsapp#setup_webhooks` chama `prompt_reauthorization!` no `rescue` (`app/models/channel/whatsapp.rb:64-69`). Um canal com essa flag pendurada **descarta todo o inbound** e o único sinal é o mesmo `warn`. Vale checar no Redis o estado da inbox 91.

---

## 3. VEREDITO 2 — uma única URL de callback compartilhada funcionaria para os dois números?

### **Sim, funcionaria — para o tráfego de mensagens (POST) e para a verificação (GET), sem nenhuma mudança de código.**

**POST (mensagens).** Como a inbox vem do payload (`whatsapp_events_job.rb:122`), os dois números podem chegar pela mesma URL e cada evento é entregue à inbox correta. Esse é precisamente o cenário que o comentário `:119-121` diz suportar.

**GET (verificação do webhook).** `MetaTokenVerifyConcern#verify` (`app/controllers/concerns/meta_token_verify_concern.rb:5-13`) delega para `Webhooks::WhatsappController#valid_token?` (`whatsapp_controller.rb:17-21`):

```ruby
17  def valid_token?(token)
18    channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
19    whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
20    token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
21  end
```

Aqui **a URL manda**. Mas isso não quebra o compartilhamento, porque o override sempre envia **a URL e o token do mesmo canal**: `webhook_setup_service.rb:58-62` monta `callback_url` do canal (`:69-74`) e lê `provider_config['webhook_verify_token']` **do mesmo canal**. Cada canal tem seu token próprio, gerado em `app/models/channel/whatsapp.rb:29` + `:73-75` (`ensure_webhook_verify_token`), e o par (URL, token) é sempre coerente. Verificação passa.

Um cuidado a registrar: a verificação **só** funciona porque a URL e o token vêm juntos. Se alguém montar manualmente no App Dashboard do Meta uma URL do número A com o verify token do número B, `valid_token?` retorna `false` e o Meta rejeita a assinatura.

**As duas ressalvas reais da URL compartilhada** (ambas de configuração, não de código):

- **`INACTIVE_WHATSAPP_NUMBERS` passa a ser uma chave errada.** `inactive_whatsapp_number?` (`whatsapp_controller.rb:23-32`) compara o número **da URL** contra a lista do `GlobalConfig`. Com URL única: (a) se o número dono da URL estiver na lista, **os dois números são rejeitados com 422**; (b) o outro número, mesmo listado como inativo, passa a ser processado. **Esta é a única forma, dentro deste caminho de código, de "cadastrar o webhook da 99 derrubar a 91" de maneira total e imediata** — e é verificável só olhando o valor do `GlobalConfig` (tarefa 1/3). Recomendo checar isso primeiro.
- **A UI acusa incompatibilidade permanente** em pelo menos uma das duas inboxes — ver seção 5.

**Mudança mínima se quisermos URLs separadas de verdade** (o correto): ver seção 6.

---

## 4. Gatilhos que re-aplicam o override no WABA (risco de reincidência)

O override é **por WABA**, não por número — `app/services/whatsapp/facebook_api_client.rb:63-94`:

```ruby
63  def subscribe_waba_webhook(waba_id, callback_url, verify_token)
67    subscribe_app_to_waba(waba_id)                              # POST /<WABA_ID>/subscribed_apps
70    override_waba_callback(waba_id, callback_url, verify_token) # POST /<WABA_ID>/subscribed_apps
71  end
82  def override_waba_callback(waba_id, callback_url, verify_token)
84      "#{BASE_URI}/#{@api_version}/#{waba_id}/subscribed_apps",
86      body: { override_callback_uri: callback_url,            # <- URL do canal que disparou
88              subscribed_fields: %w[messages smb_message_echoes] }.to_json
```

e a URL é sempre a do **próprio número** — `app/services/whatsapp/webhook_setup_service.rb:69-74`:

```ruby
69  def build_callback_url
70    frontend_url = ENV.fetch('FRONTEND_URL', nil)
71    phone_number = @channel.phone_number
73    "#{frontend_url}/webhooks/whatsapp/#{phone_number}"
```

Logo, **qualquer** um dos gatilhos abaixo, disparado na inbox X, reescreve a URL do WABA inteiro para a URL de X:

| # | Gatilho | Arquivo:linha | Automático? | Observação |
|---|---|---|---|---|
| 1 | `after_commit :setup_webhooks, on: :create` | `app/models/channel/whatsapp.rb:37` (+`:92-96`, `:81-86`) | **Sim**, mas só na **criação** e só quando `provider == 'whatsapp_cloud'` **e** `provider_config['source'] != 'embedded_signup'` | Criar a inbox 99 manualmente já sobrescreve o WABA. **Não** há `after_update`/`after_save` equivalente: **editar e salvar** uma inbox existente **não** re-aplica o override. |
| 2 | `EmbeddedSignupService#perform -> channel.setup_webhooks` | `app/services/whatsapp/embedded_signup_service.rb:23` | **Sim**, sempre que o fluxo roda | Roda **tanto na criação quanto na REAUTORIZAÇÃO** (o comentário `:19-22` diz isso explicitamente). Endpoint: `POST /api/v1/accounts/:account_id/whatsapp/authorization` (`app/controllers/api/v1/accounts/whatsapp/authorizations_controller.rb:7-13`), com `inbox_id` = reauth (`:26-38`). **Reautorizar a 99 derruba a 91 de novo.** |
| 3 | Botão "Cadastrar Webhook" da UI | `app/controllers/api/v1/accounts/concerns/whatsapp_health_management.rb:27-34` -> `WebhookSetupService#register_callback` (`webhook_setup_service.rb:20-23`) | Não (clique), mas a UI **pede** o clique — seção 5 | Rota `POST .../inboxes/:id/register_webhook` (`config/routes.rb:387`, worktree 395). Exige admin (`:6`). |
| 4 | `before_destroy :teardown_webhooks` | `app/models/channel/whatsapp.rb:36`, `:88-90` -> `webhook_teardown_service.rb:33-40` | **Sim**, ao apagar a inbox | **Achado sério:** faz `DELETE /<WABA_ID>/subscribed_apps` (`facebook_api_client.rb:96-103`), que **dessubscreve o app do WABA inteiro** — derruba os **dois** números de uma vez, não só o apagado. Só dispara se `provider_config['source'] == 'embedded_signup'` (`webhook_teardown_service.rb:16-31`). Erros são engolidos (`:42-46`). |

**Não há** job agendado, cron ou rake que re-registre webhooks — a única varredura periódica que toca WhatsApp é `app/jobs/campaigns/whatsapp/dispatch_scheduler_job.rb:78`, e ela apenas **lê** o `HealthService`.

**Não há guarda nem aviso para dois canais no mesmo WABA.** A única unicidade é `phone_number` — `app/models/channel/whatsapp.rb:32` (`validates :phone_number, presence: true, uniqueness: true`) e o índice `index_channel_whatsapp_on_phone_number UNIQUE` em `db/schema.rb:769-779` (que é **global**, nem sequer escopado por conta). `business_account_id` é só uma chave dentro do `provider_config` jsonb: não é indexado, não é validado, não é checado em lugar nenhum antes de sobrescrever o webhook (grep por `business_account_id` em `app/` retorna apenas usos de leitura para montar URLs da Graph API). O `provider_config` aceita quantos canais quiserem repetir o mesmo `business_account_id`.

---

## 5. A UI do aviso — e por que ela vive em gangorra

**Componente:** `app/javascript/dashboard/routes/dashboard/settings/inbox/components/AccountHealth.vue`.

Como decide que há incompatibilidade (`:143-159`):

```js
147  const webhookUrl = computed(
149      props.healthData?.webhook_configuration?.whatsapp_business_account ||
150      props.healthData?.webhook_configuration?.application
151  );
153  const webhookConfigured = computed(() => !!webhookUrl.value);
155  const webhookUrlMismatch = computed(
157      webhookConfigured.value &&
158      webhookUrl.value !== props.healthData?.expected_webhook_url   // comparação de string EXATA
159  );
```

Render (`:258-289`): se `webhookConfigured && !webhookUrlMismatch` → pílula verde `WEBHOOK.CONFIGURED_SUCCESS`; senão pílula âmbar com `WEBHOOK.URL_MISMATCH` (pt_BR: **"Incompatibilidade na URL do webhook"**, `app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json:703`) ou `ACTION_REQUIRED`; e o botão `WEBHOOK.REGISTER_BUTTON` (pt_BR **"Cadastrar Webhook"**, `:699`) aparece sempre que `!webhookConfigured || webhookUrlMismatch` (`:277-288`).

**Endpoint do clique:** `handleRegisterWebhook` (`:161-163`) → emite `registerWebhook` → `Settings.vue:450-466` → `InboxHealthAPI.registerWebhook(inboxId)` (`app/javascript/dashboard/api/inboxHealth.js:13-15`) → `POST /api/v1/accounts/:account_id/inboxes/:id/register_webhook` (`config/routes.rb:387`, worktree 395) → `WhatsappHealthManagement#register_webhook` (`:27-34`) → `Whatsapp::WebhookSetupService#register_callback` → **o override do WABA inteiro** (gatilho 3 acima). Em seguida `Settings.vue:457` recarrega o health.

**Confirmado: com dois números no mesmo WABA, um deles fica permanentemente "incompatível".** Os dois lados da comparação da linha 158:

- **`expected_webhook_url`** — `app/services/whatsapp/health_service.rb:80` e `:89-94`:
  ```ruby
  89  def build_expected_webhook_url
  90    frontend_url = ENV.fetch('FRONTEND_URL', nil)
  93    "#{frontend_url}/webhooks/whatsapp/#{@channel.phone_number}"
  ```
  É **sempre a URL do próprio número** — mesma construção do `webhook_setup_service.rb:69-74`. Cada inbox espera ver a **sua** URL.
- **`webhook_configuration`** — vem cru da Graph API em `health_service.rb:23-38`, consultando `GET /<phone_number_id>?fields=…,webhook_configuration,…` (`:26-32`, campo listado em `:50`). Como o override foi aplicado **no WABA**, o campo `webhook_configuration.whatsapp_business_account` é o **mesmo para todos os números daquele WABA**: a URL do último canal que registrou.

Logo a comparação da linha 158 só pode dar `false` (verde) para **um** dos números — o que registrou por último. O outro exibe "Incompatibilidade na URL do webhook" + "Cadastrar Webhook".

**O ciclo vicioso:**

```
  91 registra  ->  WABA.override = .../webhooks/whatsapp/<91>
                   inbox 91: verde     |  inbox 99: "Incompatibilidade..." + botão
  admin abre a 99, vê o aviso, clica "Cadastrar Webhook"
                ->  WABA.override = .../webhooks/whatsapp/<99>
                   inbox 99: verde     |  inbox 91: "Incompatibilidade..." + botão
  admin abre a 91, vê o aviso, clica...   -> volta ao topo, para sempre
```

Nada no front, no `HealthService` ou no `WebhookSetupService` detecta que os dois canais dividem `business_account_id`, e nada avisa que registrar um vai desmarcar o outro. A UI apresenta como defeito a ser corrigido um estado que é **estruturalmente inevitável** com override por WABA — e cada "correção" produz o defeito no vizinho.

Vale registrar que, **do ponto de vista do recebimento de mensagens, esse aviso é um falso positivo**: como a entrega resolve pelo payload (seção 2), o número que aparece "incompatível" continua recebendo normalmente pela URL do outro. O aviso mede "a URL do WABA é igual à minha?", não "estou recebendo?". O dano do ciclo é operacional (o admin persegue um alarme que não fecha) e de risco: cada clique é uma escrita na configuração de produção do WABA.

---

## 6. Histórico (git) e divergência em relação ao upstream

**`app/services/whatsapp/facebook_api_client.rb`** (`git log --follow --oneline`):

```
c77d935e38 fix: Subscribe app to WABA before overriding webhook callback URL (#13279)
b686d14044 feat: Handle external echo messages from native apps (#13371)
fd28ed8d83 feat: add support to embedded whatsapp coexistence method (#12108)
8262123481 feat: Remove subscription on WhatsApp inbox delete (#11977)
61d10044a0 feat: Whatsapp embedded signup (#11612)
```

**`app/services/whatsapp/webhook_setup_service.rb`**:

```
a452ce9e84 feat(whatsapp): add webhook registration and status endpoints (#13551)
66cfef9298 feat: Add WhatsApp health monitoring and self-service registration completion (#12556)
fd28ed8d83 feat: add support to embedded whatsapp coexistence method (#12108)
61d10044a0 feat: Whatsapp embedded signup (#11612)
```

**Origem do `override_callback_uri`:** introduzido em **`61d10044a0` — "feat: Whatsapp embedded signup (#11612)"**, upstream, já no nível de WABA (`POST /<WABA_ID>/subscribed_apps`). A URL por número (`.../webhooks/whatsapp/<phone_number>`) nasceu no mesmo commit. **Os dois lados da inconsistência (URL por número × override por WABA) são de nascença** — não foram introduzidos por customização do fork.

**O commit que cita o issue 13097** é `c77d935e38` — "fix: Subscribe app to WABA before overriding webhook callback URL (#13279)", de Muhsin Keloth, 02/02/2026. Ele **não** criou o override: apenas **dividiu** a chamada em duas etapas, porque o Meta exige que o app esteja inscrito no WABA **antes** de aceitar um `override_callback_uri`, senão devolve *"Error 100: Before override the current callback uri, your app must be subscribed to receive messages for WhatsApp Business Account"*. Isso está preservado no comentário `facebook_api_client.rb:64-66`. Esse commit **manteve** o override no nível de WABA.

### Alterações locais do fork nesses arquivos: **nenhuma**

`git diff upstream/develop producao` retorna **vazio** para:
- `app/services/whatsapp/facebook_api_client.rb`
- `app/services/whatsapp/webhook_setup_service.rb`
- `app/services/whatsapp/health_service.rb`
- `app/controllers/webhooks/whatsapp_controller.rb`

Ou seja, **o comportamento auditado é 100% upstream**. O fork diverge em outros pontos do subsistema WhatsApp, nenhum deles no caminho de resolução de canal:
- `app/jobs/webhooks/whatsapp_events_job.rb` (+36 linhas): fila `:high` em vez de `:low` e mutex por `(inbox, contato)` para rajadas/álbuns. A lógica `find_channel_from_whatsapp_business_payload` / `get_channel_from_wb_payload` está **intacta**.
- `app/models/channel/whatsapp.rb` (+1): apenas `delegate :send_typing_indicator`. O diff maior é o fork estando **atrás** do upstream (voice calling, `business_management_token` etc. ainda não integrados). Consequência positiva para este caso: os gatilhos `enable_voice_calling!` / `disable_voice_calling!` do upstream — que também chamam `register_callback` e sobrescreveriam o WABA — **não existem** neste fork.
- Demais: normalização de telefone BR, `providers/whatsapp_cloud_service.rb`, `template_management_service.rb`, `incoming_message_base_service.rb`.

### Existe correção upstream — e não está mergeada

Há uma branch de PR no upstream que resolve exatamente este problema:

**`upstream/fix/whatsapp-phone-number-level-webhook` → commit `193b16becb`**
*"fix(whatsapp): override webhook callback at phone number level instead of WABA level"* — tds-1, 16/03/2026.

Estado verificado:
- `git merge-base --is-ancestor 193b16becb upstream/develop` → **NÃO** (PR aberto, não mergeado no upstream).
- `git merge-base --is-ancestor 193b16becb producao` → **NÃO** (não está no nosso fork).

O que o patch faz (`git show 193b16becb`):

```ruby
# facebook_api_client.rb
- def subscribe_waba_webhook(waba_id, callback_url, verify_token)
+ def subscribe_phone_number_webhook(waba_id, phone_number_id, callback_url, verify_token)
    subscribe_app_to_waba(waba_id)                      # etapa 1 continua igual
-   override_waba_callback(waba_id, callback_url, verify_token)
+   # Phone number level overrides take precedence over WABA level overrides,
+   # allowing multiple phone numbers on the same WABA to have different callback URLs
+   override_phone_number_callback(phone_number_id, callback_url, verify_token)

- POST /<WABA_ID>/subscribed_apps  { override_callback_uri, verify_token, subscribed_fields }
+ POST /<PHONE_NUMBER_ID>          { webhook_configuration: { override_callback_uri, verify_token } }

# teardown: DELETE /<WABA_ID>/subscribed_apps  ->  POST /<PHONE_NUMBER_ID> { webhook_configuration: { override_callback_uri: '' } }
```

Repare que ele também conserta o gatilho 4 da seção 4: o teardown deixa de dessubscrever o WABA inteiro e passa a limpar só o override daquele número.

### Mudança mínima recomendada

1. **Cherry-pick de `193b16becb`** (3 arquivos de produção + 3 de spec). É a mudança mínima e alinhada com o upstream. Efeitos: cada número passa a ter seu próprio `override_callback_uri`; o `expected_webhook_url` do `HealthService` volta a bater com o `webhook_configuration` de cada número, **encerrando a gangorra da UI sem tocar no front**; e apagar uma inbox deixa de derrubar a outra. Como os arquivos alvo estão idênticos ao upstream no nosso fork, o cherry-pick deve aplicar limpo — validar com `git cherry-pick -n` e rodar `spec/services/whatsapp/`.
   - Ponto de atenção ao revisar: o override por número **não** envia `subscribed_fields`; a assinatura de campos (`messages`, `smb_message_echoes`) continua vindo do `subscribe_app_to_waba` no nível do WABA/app. Confirmar no Meta que `smb_message_echoes` permanece assinado após a migração.
2. **Se não quisermos mexer em código agora**, o paliativo é aceitar **uma URL compartilhada** e não clicar mais em "Cadastrar Webhook": pela seção 3, o inbound dos dois números funciona. Antes disso, é obrigatório verificar `GlobalConfig INACTIVE_WHATSAPP_NUMBERS` — é o único mecanismo neste caminho de código capaz de matar os dois números de uma vez pela URL (`whatsapp_controller.rb:23-32`).
3. **Complementos de baixo custo** (não bloqueiam o item 1): incluir o `phone_number_id`/`display_phone_number` **do payload** na mensagem de descarte de `whatsapp_events_job.rb:16` (hoje só loga o número da URL, o que induz ao erro no diagnóstico), e uma validação/aviso ao criar um segundo canal com o mesmo `business_account_id` — hoje não existe nenhuma (seção 4).

---

## 7. Resumo dos vereditos

| Pergunta | Veredito | Evidência |
|---|---|---|
| A inbox é resolvida pela URL ou pelo payload? | **Pelo payload** (`display_phone_number` + validação de `phone_number_id`). A URL só é usada para provider não-Cloud. | `whatsapp_events_job.rb:118-133`; spec `:113-137` |
| Payload cujo `phone_number_id` não bate com a URL | Vai para a **inbox do payload**. Se não bate com **nenhum** canal → `nil` → descarte silencioso com um `warn` (que ainda por cima nomeia o número da URL). Nunca cria mensagem em inbox errada. | `whatsapp_events_job.rb:127-133`, `:104-110`, `:15-18` |
| O GET de verificação quebraria com URL compartilhada? | **Não.** Usa o token do canal da URL, e o override sempre envia URL+token do mesmo canal. | `meta_token_verify_concern.rb:5-13`; `whatsapp_controller.rb:17-21`; `webhook_setup_service.rb:58-74` |
| Uma URL única compartilhada funcionaria para os dois números? | **Sim, sem mudar código** — com duas ressalvas de configuração: `INACTIVE_WHATSAPP_NUMBERS` passa a agir sobre o número errado, e a UI acusa incompatibilidade permanente numa das inboxes. | seção 3 |
| Existe guarda para dois números no mesmo WABA? | **Não existe nenhuma.** Só unicidade global de `phone_number`. `business_account_id` não é validado nem indexado. | `channel/whatsapp.rb:32`; `db/schema.rb:769-779` |
| O aviso da UI vai ficar em gangorra? | **Sim, é inevitável** com override por WABA: `expected_webhook_url` é sempre a URL do próprio número, e `webhook_configuration` é comum ao WABA. | `health_service.rb:89-94`, `:80`; `AccountHealth.vue:147-159` |
| O fork alterou esses arquivos? | **Não.** `facebook_api_client.rb`, `webhook_setup_service.rb`, `health_service.rb` e `whatsapp_controller.rb` são idênticos a `upstream/develop`. | `git diff upstream/develop producao` |
| Mudança mínima | Cherry-pick de **`193b16becb`** (`upstream/fix/whatsapp-phone-number-level-webhook`) — override por `phone_number_id`. PR upstream **ainda não mergeado**. | seção 6 |

---

*Relatório gerado em auditoria somente leitura. Nenhum arquivo de código foi modificado.*
