# 03 — Semântica da Meta Graph API + upstream Chatwoot

**Auditoria:** WhatsApp Cloud API — duas inboxes, a segunda derruba a primeira
**Tarefa:** 3 de 3 — pesquisa documental (somente leitura)
**Data:** 30/07/2026
**Escopo executado:** nenhuma chamada de escrita à Graph API foi feita. Nenhuma credencial usada. Somente doc oficial da Meta, GitHub do Chatwoot e leitura de código (fork local + `upstream/develop` via `git fetch`, read-only).

> **Correção sobre a tarefa 2** (`02-codigo-roteamento.md`): lá o fix upstream aparece como *"PR não mergeado"*, com base no commit `193b16becb` da branch. Após `git fetch upstream`, confirma-se que **foi mergeado** — squash `7c7459b734` em `develop` (25/06/2026), presente nas tags **v4.16.0, v4.16.1, v4.16.2**. O `193b16becb` é apenas o commit original da branch do PR (`upstream/fix/whatsapp-phone-number-level-webhook`).

**Convenção de marcação:**
- **[FATO]** — afirmação sustentada por documentação oficial citada, ou por código-fonte que eu li diretamente (com caminho/commit).
- **[INFERÊNCIA]** — dedução minha a partir dos fatos. Pode estar errada.
- **[AMBÍGUO]** — a doc não responde, ou responde de forma incompleta. Não chutei.

---

## Resumo executivo

1. O `override_callback_uri` em `POST /<WABA_ID>/subscribed_apps` é **escopo WABA** — vale para o WABA inteiro, e o app tem **um único** slot de override por WABA. Por isso a segunda inbox derruba a primeira: as duas escrevem no mesmo slot.
2. **Existe mecanismo nativo por número**: `POST /<BUSINESS_PHONE_NUMBER_ID>` com `webhook_configuration.override_callback_uri` + `verify_token`. A precedência de roteamento da Meta é **número → WABA → app**, então dois números do mesmo WABA podem apontar para URLs diferentes.
3. A doc da Meta favorece duas saídas legítimas: override por número (partners que querem endpoint único por cliente) ou uma URL só com roteamento por `metadata.phone_number_id`. O upstream do Chatwoot já escolheu a primeira: **PR #13817, merged em 25/06/2026, released em v4.16.0** — e este fork (base 4.12.1) **não contém** esse fix.

---

## Q1 — Granularidade do `override_callback_uri`

### É escopo WABA

**[FATO]** A Meta expõe **dois** níveis de override, não um. A página *Webhook overrides* descreve a cadeia de resolução:

> "When a supported field triggers a webhook, the system first checks if your app has designated an alternate callback URL for the business phone number associated with the event. If the business phone number has an alternate callback URL, the system sends the webhook there. If the phone number has no alternate, the system checks if the WABA associated with the number has an alternate callback URL. If the WABA has an alternate callback URL, the system sends the webhook there. If the WABA also has no alternate, the webhook falls back to your app's callback URL."

Fonte: https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/

Ou seja, a precedência é: **phone number override → WABA override → callback URL do app (App Dashboard)**.

**[FATO]** O endpoint que o código atual do fork usa — `POST /<WABA_ID>/subscribed_apps` com `override_callback_uri` — é o override de **nível WABA**. Exemplo literal da doc:

```bash
curl -X POST 'https://graph.facebook.com/v25.0/102290129340398/subscribed_apps' \
-H 'Authorization: Bearer EAAJi...' \
-H 'Content-Type: application/json' \
-d '{"override_callback_uri":"https://my-waba-alternate-callback.com/webhook","verify_token":"myvoiceismypassport?"}'
```

Fonte: https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/

**[FATO]** Não existe qualquer parâmetro de número nesse endpoint. O path é o WABA ID e o body só aceita `override_callback_uri`, `verify_token` e `subscribed_fields`. Referência da Subscribed Apps API: https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/whatsapp-business-account/subscribed-apps-api

### Dois overrides diferentes no mesmo WABA?

**Resposta: não, para o mesmo app. [INFERÊNCIA forte, sustentada por 3 evidências]**

**[FATO]** O `GET /<WABA_ID>/subscribed_apps` retorna um **array de apps inscritos**, e cada objeto `SubscribedApp` tem **um único** campo `override_callback_uri` (junto de `whatsapp_business_api_data` com `id`, `name`, `link`). A estrutura é *um override por app inscrito*, não uma lista.
Fonte: https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/whatsapp-business-account/subscribed-apps-api

**[INFERÊNCIA]** Como a chave é (WABA, app) e o campo é escalar, o segundo `POST` do **mesmo app** sobrescreve o valor do primeiro. Não existe forma de guardar duas URLs para o mesmo par (WABA, app). Dois overrides distintos no mesmo WABA só existiriam com **dois apps Meta diferentes** inscritos no mesmo WABA — cada um com seu próprio `SubscribedApp` e seu próprio override.

**[AMBÍGUO]** A doc **não afirma textualmente** "um novo POST substitui o override anterior". O que ela afirma explicitamente é o caso de remoção:

> "Subscribing without post body parameters removes the alternate callback URL from the WABA"

Fonte: https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/

**[FATO — evidência independente]** O próprio Chatwoot documenta o comportamento de sobrescrita na descrição do PR que corrigiu isso: *"Move WhatsApp webhook callback override from WABA level to phone number level, allowing multiple phone numbers on the same WABA to have independent callback URLs."* (PR #13817, commit `7c7459b7341166a845a9a5700e43a918e2d181f3`). Se não houvesse sobrescrita, o fix não teria razão de existir.

> **Consequência direta para o caso auditado:** duas inboxes no mesmo WABA, com o app ChatSPX registrando `override_callback_uri` diferente por inbox (`/webhooks/whatsapp/<numero>`), competem pelo mesmo slot. A última a registrar vence e passa a receber **os webhooks de todos os números do WABA** — inclusive os do número da primeira inbox, que chegam na URL da segunda. A primeira inbox para de receber. Isso reproduz exatamente o sintoma relatado. **[INFERÊNCIA]**

---

## Q2 — Existe override por número? **SIM**

**[FATO]** A Meta oferece override no nível do número via WhatsApp Business Phone Number API:

**Endpoint:** `POST /<BUSINESS_PHONE_NUMBER_ID>`

**Body:**
```json
{
  "webhook_configuration": {
    "override_callback_uri": "<PHONE_ALT_CALLBACK_URL>",
    "verify_token": "<PHONE_ALT_CALLBACK_URL_TOKEN>"
  }
}
```

Fonte: https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/

**[FATO] Leitura (verificação):** `GET /<BUSINESS_PHONE_NUMBER_ID>?fields=webhook_configuration` — retorna os três níveis de uma vez:

```json
{
  "webhook_configuration": {
    "phone_number": "https://my-phone-alternate-callback.com/webhook",
    "whatsapp_business_account": "https://my-waba-alternate-callback.com/webhook",
    "application": "https://my-production-callback.com/webhook"
  },
  "id": "106540352242922"
}
```

Este GET é a forma canônica de **diagnosticar** o problema sem escrever nada: ele mostra se o número está caindo no override do WABA (o slot disputado) ou no dele próprio.
Fonte: https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/

**[FATO] Remoção:** POST no phone number ID com `override_callback_uri` em string vazia (`""`) dentro de `webhook_configuration`. (Para o WABA, a remoção é o POST sem body.)
Fonte: idem.

### Limitações documentadas do mecanismo de override (valem para ambos os níveis)

**[FATO]** Campos que **suportam** override: `messages`, `message_echoes`, `calls`, `consumer_profile`, `messaging_handovers`, `group_lifecycle_update`, `group_participants_update`, `group_settings_update`, `group_status_update`, `smb_message_echoes`, `smb_app_state_sync`, `history`, `account_settings_update`.

**[FATO]** Campos que **NÃO** suportam override: webhooks de template (`message_template_status_update`, `message_template_quality_update`, `message_template_components_update`, `template_category_update`) e webhooks de nível de conta (`account_update`, `account_review_update`, `account_alerts`) — esses sempre vão para a callback URL do app.

**[FATO]** URL do override: **máximo 200 caracteres**, tanto no nível WABA quanto no nível número.

**[FATO]** Pré-requisito: *"Before setting an alternate callback URL, make sure your app is subscribed to webhooks on the WABA"* — exatamente o que o PR #13279 do Chatwoot passou a fazer (subscribe primeiro, override depois), e que gera o erro `OAuthException 100 — "Before override the current callback uri, your app must be subscribed to receive messages for WhatsApp Business Account"` quando ignorado.

Fonte de todos os itens acima: https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/

**[AMBÍGUO]** A doc não indica a partir de qual versão da Graph API o `webhook_configuration` por número está disponível, nem quais permissões/escopos exatos são exigidos (presumivelmente `whatsapp_business_management`, mas a página não diz). O fork usa `WHATSAPP_API_VERSION` default **v22.0** (`app/services/whatsapp/facebook_api_client.rb:7`) enquanto os exemplos da doc estão em v25.0; o upstream mantém o mesmo default v22.0 já usando o endpoint por número, o que sugere compatibilidade — mas **isso é inferência**, e a verificação barata é o `GET ...?fields=webhook_configuration` acima.

---

## Q3 — Formato do payload: uma URL só consegue distinguir o número? **SIM**

**[FATO]** Todo webhook da Cloud API sob o objeto `whatsapp_business_account` carrega, em `entry[].changes[].value.metadata`:

- **`display_phone_number`** — *"The phone number associated with the business account, presented in a user-readable format"*
- **`phone_number_id`** — *"A unique identifier for the phone number used by the business to send and receive messages"*

E **`entry[].id`** é o **WABA ID** que originou o evento.

Fonte: https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components/

**[FATO]** O `metadata` aparece tanto nos webhooks de mensagem recebida (array `messages`) quanto nos de status (array `statuses`) — a mesma estrutura `value.metadata` em ambos.

**[FATO — código]** O Chatwoot (e este fork) já usa exatamente isso para rotear: `app/jobs/webhooks/whatsapp_events_job.rb:118-133` prioriza o payload sobre a URL:

```ruby
def find_channel_from_whatsapp_business_payload(params)
  # for the case where facebook cloud api support multiple numbers for a single app
  return get_channel_from_wb_payload(params) if params[:object] == 'whatsapp_business_account'
  find_channel_by_url_param(params)
end

def get_channel_from_wb_payload(wb_params)
  phone_number = "+#{...dig(:value, :metadata, :display_phone_number)}"
  phone_number_id = ...dig(:value, :metadata, :phone_number_id)
  channel = Channel::Whatsapp.find_by(phone_number: phone_number)
  return channel if channel && channel.provider_config['phone_number_id'] == phone_number_id
end
```

**[INFERÊNCIA]** Ressalva relevante: os webhooks de template e de conta (que não suportam override, ver Q2) **não trazem** `metadata` de número — não há como roteá-los por número, nem por URL. Eles sempre vão para a callback do app. Qualquer arquitetura precisa contar com isso.

**[FATO — código]** Cuidado adicional com o casamento por `display_phone_number`: a Meta pode entregar o número em variante local (o upstream cita Brasil omitindo o 9 do celular e Argentina com dígito extra). O upstream resolveu isso no PR #13709, criando `app/services/whatsapp/webhook_channel_finder_service.rb`, que tenta os dígitos crus e depois um normalizador por país, **aceitando apenas o candidato cujo `phone_number_id` bate**. Este fork **não tem** esse serviço — o match dele é literal (`find_by(phone_number: "+#{digits}")`), e é justamente o caso brasileiro que a normalização cobre.

---

## Q4 — Arquitetura recomendada pela Meta para vários números no mesmo WABA

**[FATO] Padrão da plataforma:** sem override, tudo cai numa URL só. A doc de *Managing Webhooks* (Solution Providers) diz: *"You must individually subscribe to every WABA for which you want to receive webhooks"*, e que todas as notificações vão *"to the app's callback URL specified in the Webhooks product panel"*. O roteamento é responsabilidade do seu servidor, usando os campos de contexto do payload (`waba_id`, `display_phone_number`, `phone_number_id`).
Fonte: https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/manage-webhooks

**[FATO] Exceção prevista pela própria Meta:** override existe explicitamente para o cenário de BSP/partner com endpoints distintos por cliente:

> "An alternate endpoint can be useful for testing purposes, or if you are a partner and wish to use unique webhook endpoints for each of your onboarded customers."

Fonte: https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks/

**[INFERÊNCIA]** Logo, a Meta suporta **as duas** arquiteturas como cidadãs de primeira classe:
- **URL única + roteamento por `phone_number_id`** — o caminho "padrão", mais simples, sem estado na Meta;
- **Override por número** — o caminho "partner", quando cada número precisa de destino próprio.

O que **não** é suportado é o que o código atual do fork faz: usar o override de **WABA** como se fosse por número. Esse é o bug de premissa.

---

## Q5 — Dois WABAs diferentes

**[FATO]** Cada WABA tem seu próprio slot de override — a cadeia de resolução é avaliada *"for the WABA associated with the number"*. WABAs são objetos distintos; a subscrição é feita individualmente por WABA (*"You must individually subscribe to every WABA…"*).
Fontes: https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/ · https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/manage-webhooks

**[INFERÊNCIA]** Portanto: **sim**, com os dois números em WABAs diferentes, cada WABA pode ter seu `override_callback_uri` independente, e um **não** sobrescreve o outro. O mesmo app Meta inscrito nos dois WABAs mantém um `SubscribedApp` (com override próprio) em cada um. Não encontrei na doc nenhum mecanismo que faça a inscrição em um WABA invalidar a de outro.

**[FATO] Limites conhecidos:**
- Um portfólio de negócios (Meta Business Account) começa limitado a **20 WABAs**.
- Um portfólio começa com **2 números** registrados, ampliável até **20**.
Fonte: https://developers.facebook.com/documentation/business-messaging/whatsapp/whatsapp-business-accounts

**[AMBÍGUO]** **Não há limite documentado de WABAs por app.** A doc de manage-webhooks descreve o modelo multi-WABA como o normal para BSPs (que operam centenas de WABAs), mas nenhuma página que li declara um teto explícito. Não vou chutar um número.

**[FATO — sinal de campo, não doc]** A issue #7404 do Chatwoot (*"Single Facebook App Multiple Whatsapp Numbers Fails after 4 numbers"*) sugere que existem limites práticos/operacionais ao empilhar números num mesmo app. Não confirmei a causa raiz dessa issue; registro como pista, não como fato de plataforma.

---

## Q6 — Verify token: o que quebra com URL compartilhada

### Como a verificação funciona

**[FATO]** A Meta valida o endpoint com um GET:

```
GET <CALLBACK_URL>?hub.mode=subscribe&hub.challenge=<HUB.CHALLENGE>&hub.verify_token=<HUB.VERIFY_TOKEN>
```

Você deve *"compare the `hub.verify_token` value in the request to the verification string you have stored on your server"* e, se bater, *"respond with HTTP status 200 and the `hub.challenge` value"*. Se não bater, responder *"a 400-level HTTP status code, or anything other than status 200"*.
Fontes: https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/create-webhook-endpoint · https://developers.facebook.com/docs/graph-api/webhooks/getting-started/

**[FATO]** `hub.mode` é sempre `subscribe`; `hub.challenge` é um int que deve ser devolvido; `hub.verify_token` é a string que você definiu.

**[AMBÍGUO]** A doc de webhooks **do App Dashboard** diz que a verificação ocorre *"Anytime you set or edit the Callback URL field or the Verify token field in the App Dashboard"*. A página de *Webhook overrides* pede `verify_token` no POST do override, mas **não descreve explicitamente** o handshake GET para a URL alternativa nem o que acontece se ele falhar. **[INFERÊNCIA]** O `verify_token` no body só faz sentido se a Meta validar o endpoint alternativo do mesmo modo — e é assim que o Chatwoot implementa (a rota `GET /webhooks/whatsapp/:phone_number` existe justamente para isso) — mas a doc não fecha essa afirmação.

### Como o ChatSPX valida hoje

**[FATO — código do fork]**
- Rotas (`config/routes.rb:779-780`): `GET`/`POST` `webhooks/whatsapp/:phone_number`.
- `app/controllers/webhooks/whatsapp_controller.rb:17-21`:
```ruby
def valid_token?(token)
  channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
  whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
  token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
end
```
- `app/controllers/concerns/meta_token_verify_concern.rb`: se `valid_token?` falha → **401** `{"error":"Error; wrong verify token"}`; se passa → devolve `hub.challenge`.

Ou seja: **o canal é resolvido pelo `:phone_number` da URL**, e só então o token é comparado. O token é *por canal*, não global.

### Os dois cenários perguntados

**Cenário A — mesma URL, verify_tokens diferentes.** **[INFERÊNCIA a partir do código + doc]**
A URL compartilhada contém o `phone_number` de **uma** das inboxes. O lookup sempre encontra **aquele** canal, logo só o `webhook_verify_token` **daquele** canal é aceito. Quando a segunda inbox tentar registrar um override apontando para essa URL com o token **dela**, a verificação retorna **401** e o registro falha (ou a URL fica marcada como não verificada). Quebra na verificação, não no tráfego.

**Cenário B — mesma URL, mesmo verify_token.** **[INFERÊNCIA]**
A verificação passa (o canal do path valida o token) e o tráfego funciona, porque o roteamento real do Chatwoot/ChatSPX é feito **pelo payload** (`metadata.phone_number_id` + `display_phone_number`), não pelo path — `whatsapp_events_job.rb:118-133`. O `:phone_number` da URL vira só fallback para payloads que não são `whatsapp_business_account`.
Ressalvas: (i) `inactive_whatsapp_number?` no controller filtra pelo `params[:phone_number]` da URL, então uma URL compartilhada faz o bloqueio de números inativos valer pelo número da URL, não pelo número real do evento; (ii) compartilhar o mesmo token entre inboxes de clientes distintos reduz o isolamento — quem souber o token de uma inbox consegue completar o handshake da outra; (iii) o fork **não** tem o `verify_meta_signature!` que o upstream já aplica no `process_payload` (`app/controllers/webhooks/whatsapp_controller.rb` upstream), então hoje a autenticidade do POST não é checada por assinatura — o que torna o token compartilhado ainda menos confortável.

---

## Q7 — Upstream Chatwoot: existe fix oficial? **SIM, e o fork não tem**

### O fix

| # | Título | Estado | Data | Link |
|---|--------|--------|------|------|
| **PR #13817** | **fix(whatsapp): override webhook at phone number level** | **MERGED** | aberto 16/03/2026, merged **25/06/2026**, milestone **v4.16.0** | https://github.com/chatwoot/chatwoot/pull/13817 |

**[FATO]** Commit: `7c7459b7341166a845a9a5700e43a918e2d181f3` — *"fix(whatsapp): override webhook at phone number level (#13817)"*, Tanmay Deep Sharma, Thu Jun 25 14:49:09 2026. Descrição do PR: *"Move WhatsApp webhook callback override from WABA level to phone number level, allowing multiple phone numbers on the same WABA to have independent callback URLs."* Plano de teste do próprio PR: *"Connect a second phone number on the same WABA — both should receive messages independently"*.

Arquivos tocados: `app/services/whatsapp/facebook_api_client.rb`, `webhook_setup_service.rb`, `webhook_teardown_service.rb`, `reauthorization_service.rb`, `AccountHealth.vue` + specs.

**[FATO]** Presente nas tags **v4.16.0, v4.16.1, v4.16.2** (verificado com `git tag --contains 7c7459b734`).

**[FATO]** O que o código passou a fazer (`git show upstream/develop:app/services/whatsapp/facebook_api_client.rb`):

```ruby
def subscribe_phone_number_webhook(waba_id, phone_number_id, callback_url, verify_token, subscribed_fields: nil)
  # Subscribe app to WABA first — Meta requires it before any callback override (issue #13097).
  subscribe_app_to_waba(waba_id, subscribed_fields: subscribed_fields || WEBHOOK_DEFAULT_FIELDS)
  # Phone-level override takes precedence over WABA-level, so numbers on one WABA can route to different URLs.
  override_phone_number_callback(phone_number_id, callback_url, verify_token)
end

def override_phone_number_callback(phone_number_id, callback_url, verify_token)
  HTTParty.post("#{BASE_URI}/#{@api_version}/#{phone_number_id}",
    headers: request_headers,
    body: { webhook_configuration: { override_callback_uri: callback_url, verify_token: verify_token } }.to_json)
end

def clear_phone_number_callback_override(phone_number_id)   # limpa com string vazia
def unsubscribe_app_from_waba(waba_id)                      # DELETE só quando é a última inbox do WABA
```

Detalhes de comportamento que vieram junto **[FATO]**:
- `subscribed_fields` continua sendo **WABA-wide**; o `WebhookSetupService` upstream calcula `calls_enabled_on_waba?` olhando as inboxes irmãs do mesmo WABA para não derrubar `calls` de um irmão ao reconfigurar outro.
- O `WebhookTeardownService` upstream limpa **só o override daquele número** e só faz `DELETE /subscribed_apps` quando é a última inbox do WABA (e só para `source == 'embedded_signup'`).

### Estado deste fork

**[FATO]** `git merge-base --is-ancestor 7c7459b734 HEAD` → **não contém**. A base do fork em relação ao upstream é `7144d55334 — Bump version to 4.12.1` (25/03/2026); `config/app.yml` local diz `version: '4.12.1'`. O `app/services/whatsapp/facebook_api_client.rb` local ainda implementa `subscribe_waba_webhook` → `override_waba_callback` (POST em `/<WABA_ID>/subscribed_apps`), ou seja, **exatamente o comportamento que o PR #13817 removeu**.

### Histórico correlato no upstream

| # | Título | Estado | Data | Relevância | Link |
|---|--------|--------|------|-----------|------|
| PR #13279 | fix: Subscribe app to WABA before overriding webhook callback URL | MERGED | 02/02/2026 | É o que o fork tem hoje: corrige o `OAuthException 100`, mas mantém o override no nível WABA | https://github.com/chatwoot/chatwoot/pull/13279 |
| Issue #13097 | Chatwoot is not receiving messages from WhatsApp Business Cloud | CLOSED | 17/12/2025 | Citada no comentário do código do fork; resolvida pelo PR #13278/#13279 (subscribe antes do override) | https://github.com/chatwoot/chatwoot/issues/13097 |
| Discussion #13497 | Using multiple WhatsApp numbers from the same WABA with a single webhook | ANSWERED | 09/02/2026 | Mantenedor (@viniciustrndd): *"each inbox created through embedded signup within Chatwoot will have the override-callback-url updated automatically"*, apontando para o PR #13279. Comentário de follow-up (@lucasevss) levanta exatamente a dúvida da sobrescrita — sem resposta na thread | https://github.com/orgs/chatwoot/discussions/13497 |
| Issue #10663 | WhatsApp Cloud Inbox cannot reuse endpoint | CLOSED as not planned | 09/01/2025 | Relata o sintoma: duas inboxes geram duas URLs e a Meta só aceita um endpoint por app | https://github.com/chatwoot/chatwoot/issues/10663 |
| Issue #11882 | One Webhook in Whatsapp oficial API to multiples numbers in the same portfolio | CLOSED | 04/07/2025 | Testou tokens iguais e diferentes com URL única: só um número recebia. Sem resposta de mantenedor | https://github.com/chatwoot/chatwoot/issues/11882 |
| Issue #13426 | Multi-tenant support for WhatsApp Embedded in Chatwoot | CLOSED (feature-request) | 03/02/2026 | Pede roteamento interno por `phone_number_id` (como já existe para Instagram/Messenger via `page_id`/`ig_id`) | https://github.com/chatwoot/chatwoot/issues/13426 |
| Issue #14079 | WhatsApp Embedded Signup documentation unclear for multi-phone-number setup and webhook behavior | **OPEN** | 16/04/2026 | Doc segue sem explicar o caso multi-número; aberta mesmo depois do fix | https://github.com/chatwoot/chatwoot/issues/14079 |
| Issue #13154 | WhatsApp Embedded Signup fails with multiple errors on self-hosted installations | **OPEN** | 26/12/2025 | Cataloga o `OAuthException 100` do override e campos não inscritos | https://github.com/chatwoot/chatwoot/issues/13154 |
| Issue #13219 | WhatsApp Cloud API: Incoming messages not delivered (webhook verified, no events received) | CLOSED | 10/01/2026 | Sintoma compatível com override sequestrado; causa raiz não registrada na issue | https://github.com/chatwoot/chatwoot/issues/13219 |
| Issue #12488 | Whatsapp embedded signup obtain the webhook url and verify token for messages event | CLOSED | 22/09/2025 | Onde aparece a mensagem literal da Meta: *"Before override the current callback uri, your app must be subscribed…"* | https://github.com/chatwoot/chatwoot/issues/12488 |
| Discussion #14132 | Unable to Verify Callback URL & Verify Token (self-hosted) | — | 22/04/2026 | Confirma a mecânica do 401: o `:phone_number` da URL precisa bater com o do canal **antes** da comparação do token | https://github.com/orgs/chatwoot/discussions/14132 |
| PR #13709 | fix: normalize phone numbers during whatsapp channel lookup | MERGED | — | Cria o `WebhookChannelFinderService` (dígitos crus + normalização por país, validando `phone_number_id`) — ausente neste fork | https://github.com/chatwoot/chatwoot/pull/13709 |

**Conclusão de Q7 [FATO]:** existe fix oficial, é o PR #13817, está em v4.16.0+, e este fork está três minor releases atrás dele. Não é preciso inventar workaround — é preciso portar.

---

## OPÇÕES DE CORREÇÃO

### (c) Override nativo por número — **RECOMENDADA**

Portar o PR #13817: trocar `POST /<WABA_ID>/subscribed_apps {override_callback_uri}` por `POST /<PHONE_NUMBER_ID> {webhook_configuration:{override_callback_uri, verify_token}}`, mantendo o `subscribe_app_to_waba` como passo 1 e ajustando o teardown para limpar só o override do número (e só desinscrever o app quando for a última inbox do WABA).

- **Prós:** é o mecanismo que a Meta desenhou para isso **[FATO: precedência número → WABA → app]**; cada inbox mantém sua URL e seu `verify_token` (isolamento preservado); é o caminho oficial do upstream, então some o débito de divergência e ganha-se os specs prontos; funciona igual em WABA único ou múltiplo; teardown limpo por inbox.
- **Contras:** exige código (≈5 arquivos + specs); `subscribed_fields` continua WABA-wide, então a lógica de `calls_enabled_on_waba?` precisa vir junto ou uma inbox sem voz derruba `calls` da irmã **[FATO: comentário e código do upstream]**; a inbox antiga precisa ser re-registrada (o override de WABA legado tem que ser removido, senão fica um resíduo — inofensivo por precedência, mas confuso no diagnóstico).
- **Risco:** **baixo**. Código já validado upstream há mais de um mês em release estável. Risco residual: a versão da API v22.0 do fork versus os exemplos v25.0 da doc **[AMBÍGUO]** — mitigar validando com `GET /<PHONE_NUMBER_ID>?fields=webhook_configuration` logo após o primeiro registro.

### (b) URL de callback compartilhada + roteamento por `phone_number_id`

Registrar **uma** URL (override de WABA, uma vez só) e deixar o roteamento por payload resolver a inbox.

- **Prós:** o roteamento **já existe e já funciona** neste fork (`whatsapp_events_job.rb:118-133` prioriza `metadata.phone_number_id`/`display_phone_number` sobre a URL) **[FATO]**; é o padrão que a Meta descreve para multi-WABA/multi-número **[FATO: manage-webhooks]**; zero chamada extra à Graph API por inbox; imune à corrida de "quem registrou por último".
- **Contras:** exige `verify_token` **igual** entre as inboxes (cenário A da Q6 dá 401) — perda de isolamento e, neste fork, sem `verify_meta_signature!` para compensar **[FATO]**; a URL contém o número de uma inbox específica, então `inactive_whatsapp_number?` passa a filtrar pelo número errado **[FATO — código]**; o casamento por `display_phone_number` no fork é literal, e o Brasil é justamente o caso da variante com/sem o 9 que o upstream normaliza no PR #13709 **[FATO]** — sem isso, um payload com formato inesperado não acha canal e a mensagem é descartada; e apagar uma inbox tende a derrubar a URL das duas se o teardown atual rodar.
- **Risco:** **médio**. Sem escrever código novo o caminho fica frágil (token compartilhado + normalização ausente). Serve bem como **mitigação temporária** até (c) ser portada.

### (a) Separar os números em WABAs distintos

- **Prós:** cada WABA tem seu slot de override, sem colisão **[INFERÊNCIA sobre FATO de precedência]**; não exige mudança de código; mantém `verify_token` distinto por inbox.
- **Contras:** é mudança de estrutura de negócio na Meta, não de software — reonboarding do número (o número precisa sair de um WABA e entrar em outro, com o downtime e a burocracia que isso implica); duplica limites e configurações (templates são por WABA, então templates precisam ser recriados no novo WABA); limite de 20 WABAs por portfólio **[FATO]**; não escala se amanhã surgir um terceiro número; e o cliente pode simplesmente não querer dois WABAs.
- **Risco:** **alto** operacionalmente (mexe em número em produção), **baixo** tecnicamente. E resolve o sintoma sem corrigir o bug: qualquer par futuro de números no mesmo WABA reproduz o problema.

### (d) Outras opções que a doc suporta

**(d1) Um app Meta por inbox/cliente.** **[INFERÊNCIA]** Como o override é por par (WABA, app), dois apps distintos inscritos no mesmo WABA teriam slots independentes.
- Prós: isolamento total.
- Contras: multiplica app IDs/secrets, review da Meta e configuração de Embedded Signup por cliente; a própria issue #13426 do Chatwoot descarta como *"unfeasible at scale"*; o fork tem `WHATSAPP_APP_ID`/`WHATSAPP_APP_SECRET` como config global **[FATO — `facebook_api_client.rb`]**, então exigiria refatoração maior que a opção (c).
- Risco: **alto** (custo/complexidade), sem ganho sobre (c).

**(d2) Proxy/fan-out externo (n8n, worker próprio).** Uma URL recebe e redistribui por `phone_number_id`.
- Prós: não toca o Chatwoot.
- Contras: mais um ponto de falha no caminho crítico do inbound, latência, e reimplementa fora o que (b) já faz dentro. Citado nas issues upstream como alternativa indesejada.
- Risco: **médio-alto** operacional.

### Comparativo

| Opção | Alinhada à doc da Meta | Código | Isolamento de token | Reversível | Risco |
|---|---|---|---|---|---|
| **(c) override por número** | **Sim, é o mecanismo previsto** | Portar PR #13817 | Preservado | Sim (limpa com `""`) | **Baixo** |
| (b) URL única + roteamento | Sim, é o padrão multi-número | Zero (já existe), mas frágil | Perdido (token comum) | Sim | Médio |
| (a) WABAs separados | Sim | Zero | Preservado | Difícil (reonboarding) | Alto operacional |
| (d1) app por inbox | Sim | Refatoração grande | Preservado | Difícil | Alto |
| (d2) proxy externo | Neutra | Fora do produto | Depende | Sim | Médio-alto |

### O que a doc da Meta favorece

**[FATO]** A doc coloca o override por número como o primeiro elo da cadeia de precedência e descreve o caso de uso literalmente: *"if you are a partner and wish to use unique webhook endpoints for each of your onboarded customers"*. **[INFERÊNCIA]** Para o cenário auditado — um mesmo app servindo várias inboxes/clientes, cada uma querendo sua URL e seu token — a opção **(c)** é a que a Meta desenhou, e é também a que o upstream do Chatwoot adotou em v4.16.0. **(b)** é o plano B legítimo e imediato; **(a)** é remédio de contorno com custo operacional; **(d)** não compensa.

---

## Verificação sem escrever nada (diagnóstico read-only sugerido)

Com um token válido do cliente, apenas GETs:

```
GET /<PHONE_NUMBER_ID_1>?fields=webhook_configuration   # mostra phone / whatsapp_business_account / application
GET /<PHONE_NUMBER_ID_2>?fields=webhook_configuration
GET /<WABA_ID>/subscribed_apps                          # mostra qual app está inscrito e o override_callback_uri vigente
```

**[INFERÊNCIA]** Se os dois números vierem sem `webhook_configuration.phone_number` e com o mesmo `whatsapp_business_account` (apontando para a URL da inbox criada por último), o diagnóstico do slot único de WABA está confirmado empiricamente. Este fork já lê esse campo no health check — `app/services/whatsapp/health_service.rb:50,79` inclui `webhook_configuration` nos `health_fields` e o devolve como `webhook_configuration` junto de `expected_webhook_url` **[FATO]** — ou seja, dá para conferir pela própria tela de saúde da inbox, sem tocar na Graph API manualmente.

---

## Fontes

**Meta (documentação oficial)**
- Webhook overrides — https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/
- Subscribed Apps API (WABA) — https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/whatsapp-business-account/subscribed-apps-api
- Managing Webhooks (Solution Providers) — https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/manage-webhooks
- Webhooks (visão geral, Cloud API) — https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks/
- Webhooks — componentes do payload (`metadata`) — https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/components/
- Create a webhook endpoint (handshake `hub.*`) — https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/create-webhook-endpoint
- Graph API Webhooks — Getting Started — https://developers.facebook.com/docs/graph-api/webhooks/getting-started/
- WhatsApp Business Accounts (limites) — https://developers.facebook.com/documentation/business-messaging/whatsapp/whatsapp-business-accounts
- Embedded Signup — Webhooks — https://developers.facebook.com/docs/whatsapp/embedded-signup/webhooks/

**Chatwoot (GitHub)**
- PR #13817 (fix oficial, v4.16.0) — https://github.com/chatwoot/chatwoot/pull/13817
- PR #13279 — https://github.com/chatwoot/chatwoot/pull/13279
- PR #13709 — https://github.com/chatwoot/chatwoot/pull/13709
- Issues #13097, #13154, #13219, #13426, #14079, #12488, #11882, #10663, #7404
- Discussions #13497, #14132

**Código lido (read-only)**
- Fork local: `app/services/whatsapp/facebook_api_client.rb`, `app/services/whatsapp/health_service.rb`, `app/jobs/webhooks/whatsapp_events_job.rb`, `app/controllers/webhooks/whatsapp_controller.rb`, `app/controllers/concerns/meta_token_verify_concern.rb`, `config/routes.rb:779-780`
- `upstream/develop` (commit `7c7459b7341166a845a9a5700e43a918e2d181f3`): `facebook_api_client.rb`, `webhook_setup_service.rb`, `webhook_teardown_service.rb`, `webhook_channel_finder_service.rb`, `whatsapp_controller.rb`
