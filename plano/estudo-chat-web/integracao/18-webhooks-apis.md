# 18 — Webhooks, APIs e integração bidirecional

> **Onda:** estudo do chat de site (Task 18 — trilha `integracao/`)
> **Data da coleta:** 12/08/2026
> **Repositório analisado:** `/home/chatwoot/chatwoot`, branch `homologacao`, HEAD `ee87f5e799`, versão declarada `4.12.1` (`config/app.yml:2`, `package.json:3`)
> **Escopo:** o handshake do lado do servidor. A Task 17 cobriu "como o chat descobre quem é a pessoa". Esta cobre "como o sistema do cliente e o chat conversam nos dois sentidos".
> **Estado:** FASE DE ESTUDO. Nenhum arquivo de código foi alterado. Nenhum comando de escrita foi executado contra banco, fila ou serviço.

---

## Como ler as marcações

| Marca | Significado |
|---|---|
| `[FATO]` | Afirmação extraída de documentação oficial do fornecedor. A URL exata vem junto. |
| `[MEDIDO]` | Número/comportamento obtido por execução real minha (leitura de arquivo com linha, ou script rodado agora). O comando/arquivo vem junto. |
| `[INFERÊNCIA]` | Conclusão minha ligando dois fatos. Marcada como tal, não como fato. |
| `[NÃO VERIFICADO]` | Não consegui confirmar em fonte primária. Fica registrado como buraco, não como conclusão. |

**Aviso de rigor aplicado aqui:** webhook *de saída* e API *de entrada* são superfícies distintas — não generalizo de uma para a outra. "Tem assinatura" no webhook de conta **não** significa "tem assinatura" no webhook de agent bot; medi os dois separadamente e os resultados são diferentes. Da mesma forma, "documentado" e "implementado" são coisas diferentes: onde a doc oficial do Chatwoot diverge do código, aponto os dois.

**Sobre screenshots:** esta task não tem superfície visual a medir (é servidor/protocolo). Nenhum arquivo foi gravado em `frontend/shots/`.

---

## Sumário executivo — as 8 coisas que importam

1. **O Chatwoot ASSINA webhooks de conta.** HMAC-SHA256 sobre `"{timestamp}.{corpo_bruto}"`, headers `X-Chatwoot-Signature` / `X-Chatwoot-Timestamp` / `X-Chatwoot-Delivery`. Isso é recente (upstream #13573) e está no nível do mercado. `[MEDIDO]` `lib/webhooks/trigger.rb:44-53`
2. **Mas os OUTROS TRÊS caminhos de webhook do Chatwoot NÃO são assinados:** webhook de inbox do canal API, webhook de agent bot, e webhooks disparados por automação/macro/flow. `[MEDIDO]` `app/listeners/webhook_listener.rb:140-146`, `app/listeners/agent_bot_listener.rb:71`, `app/services/automation_rules/action_service.rb:38-41`
3. **Webhook de conta do Chatwoot NÃO TEM RETRY.** O `retry_on StandardError, attempts: 5` do `WebhookJob` nunca dispara porque `Webhooks::Trigger#execute` engole a exceção antes. Provei isso rodando o arquivo real com stubs. `[MEDIDO]` — ver §D.10.4. **Todo o mercado tem retry** (Intercom, Zendesk, HubSpot, Tidio, Crisp, tawk.to, Sunshine, LiveChat, Jivo).
4. **O `X-Chatwoot-Delivery` (chave de idempotência) só existe onde NÃO há retry**, e está ausente exatamente onde há retry (agent bot). Está invertido. `[MEDIDO]`
5. **Filtro por inbox nos webhooks do Chatwoot é letra morta.** A coluna `inbox_id` e o enum `inbox_type` existem, o controller aceita `inbox_id`, mas nada no código jamais grava `webhook_type: inbox_type` e a entrega itera só `webhooks.account_type` sem filtrar inbox. `[MEDIDO]`
6. **Mensagem proativa do backend do cliente para um visitante identificado no widget: DÁ, e sem gambiarra** — mas em 3 chamadas de API e sem endpoint de conveniência. Intercom faz em 1 chamada (`POST /messages`). Ver §D.13.
7. **O ChatSPX já tem um endpoint de webhook de ENTRADA bom** (`POST /webhooks/flows/:token`) com cap de payload, rate-limit por token, dedupe por `Idempotency-Key` e 404 anti-enumeração. Isso é melhor que o inbound de vários concorrentes. Só que é exclusivo do motor Flow. `[MEDIDO]` `app/controllers/webhooks/flows_controller.rb`
8. **O catálogo de eventos do Chatwoot é pequeno: 12 eventos.** Crisp publica ~60, Sunshine Conversations 24, Intercom 90+. Faltam eventos que qualquer integração de vendas quer: `conversation_resolved` (existe só para agent bot, não para webhook de conta), CSAT respondido, etiqueta aplicada, atribuição mudada.

---

# A. OUTBOUND — o chat avisa o sistema do cliente

## A.1 Catálogo de eventos por fornecedor

### A.1.1 Intercom

`[FATO]` https://developers.intercom.com/docs/references/webhooks/webhook-models

Intercom organiza em **topics**. Categorias e nomes exatos:

**Conversation** (a categoria que importa pro chat de site):
```
conversation.admin.assigned          conversation.admin.closed
conversation.admin.noted             conversation.admin.open.assigned
conversation.admin.opened            conversation.admin.replied
conversation.admin.single.created    conversation.admin.snoozed
conversation.admin.unsnoozed         conversation.operator.replied
conversation.deleted                 conversation_part.redacted
conversation_part.tag.created        conversation.priority.updated
conversation.rating.added            conversation.read
conversation.user.created            conversation.user.replied
conversation.contact.attached        conversation.contact.detached
conversation.company.updated
```

**Contact:** `contact.archived`, `contact.deleted`, `contact.email.updated`, `contact.lead.added_email`, `contact.lead.created`, `contact.lead.signed_up`, `contact.lead.tag.created`, `contact.lead.tag.deleted`, `contact.lead.updated`, `contact.merged`, `contact.subscribed`, `contact.unarchive`, `contact.unsubscribed`, `contact.user.created`, `contact.user.tag.created`, `contact.user.tag.deleted`, `contact.user.updated`

**Ticket:** `ticket.created`, `ticket.state.updated`, `ticket.note.created`, `ticket.admin.assigned`, `ticket.team.assigned`, `ticket.contact.attached`, `ticket.contact.detached`, `ticket.attribute.updated`, `ticket.admin.replied`, `ticket.contact.replied`, `ticket.closed`, `ticket.rating.provided`, `ticket.resolved`, `ticket.admin.snoozed`, `ticket.admin.unsnoozed`

**Call (voz no widget):** `call.started`, `call.ended`, `call.transcription_available`, `call.recording_available`

**Admin:** `admin.added_to_workspace`, `admin.away_mode_updated`, `admin.activity_log_event.created`, `admin.removed_from_workspace`, `admin.logged_in`, `admin.logged_out`

**Content stat (mensagem proativa/campanha):** `content_stat.banner`, `content_stat.carousel`, `content_stat.chat`, `content_stat.checklist`, `content_stat.custom_bot`, `content_stat.email`, `content_stat.news_item`, `content_stat.post`, `content_stat.push`, `content_stat.series`, `content_stat.series.webhook`, `content_stat.sms`, `content_stat.survey`, `content_stat.tooltip_group`, `content_stat.tour`

**Outros:** `article.created/updated/published/unpublished/deleted`, `company.created/deleted/updated`, `company.contact.attached/detached`, `event.created`, `api.request.completed`, `job.completed`, `ping`, `granular.subscribe`, `granular.unsubscribe`, `visitor.signed_up`, `data_connector.execution.completed`

**Envelope real, copiado verbatim** `[FATO]` https://developers.intercom.com/docs/webhooks.md:

```json
{
  "type": "notification_event",
  "app_id": "your-app-id",
  "data": {
    "type": "notification_event_data",
    "item": {
      "type": "ticket",
      "id": "5",
      "ticket_id": "1",
      "ticket_attributes": {},
      "ticket_state": "submitted",
      "ticket_type": {},
      "contacts": {},
      "admin_assignee_id": "0",
      "team_assignee_id": "0",
      "created_at": 1715937888,
      "updated_at": 1715937889,
      "ticket_parts": {},
      "open": true,
      "snoozed_until": null,
      "linked_objects": {},
      "category": "Tracker",
      "is_shared": false
    }
  },
  "links": {},
  "id": "notif_c2441832-5d5b-48d9-8f83-f8c37d8e03e6",
  "topic": "ticket.created",
  "delivery_status": "pending",
  "delivery_attempts": 1,
  "delivered_at": 0,
  "first_sent_at": 1715937891,
  "created_at": 1715937890,
  "self": null
}
```

Repare em `delivery_status`, `delivery_attempts`, `delivered_at`, `first_sent_at` — o próprio payload carrega a telemetria de entrega. O Chatwoot não carrega nada disso.

> ⚠️ Detalhe operacional relevante `[FATO]` https://developers.intercom.com/docs/webhooks.md — **não dá para criar subscription de webhook por API no Intercom hoje**: "you can only subscribe to webhooks now via your Developer Hub". Webhooks são amarrados ao **App**, não à workspace.

---

### A.1.2 Zendesk — dois sistemas diferentes, não confunda

O Zendesk tem **duas superfícies distintas** de webhook, e elas não são a mesma coisa:

**(a) Zendesk Webhooks (Support/Guide/Gather/Messaging)** `[FATO]` https://developer.zendesk.com/documentation/webhooks/
Webhooks que disparam por *event type* (`zen:event-type:...`) ou por *trigger/automação* do Support. A página de referência de event types (`https://developer.zendesk.com/api-reference/webhooks/event-types/`) devolveu **HTTP 403** para o meu fetch e para o `curl` — `[NÃO VERIFICADO]` a lista completa de event types nomeados. O que a doc de visão geral confirma: eventos de usuário e de organização enviam POST com payload JSON pré-definido, e triggers do Support podem disparar webhook com payload customizado montado pelo admin.

**(b) Sunshine Conversations** — é o **motor de mensageria** por baixo do Zendesk Messaging (o widget de chat moderno). Aqui a doc é aberta e completa.

`[FATO]` https://raw.githubusercontent.com/zendesk/sunshine-conversations-api-spec/master/openapi.yaml (linhas 244-277 do spec) — **24 triggers**:

| Trigger | Quando dispara |
|---|---|
| `client:add` | Início de link de canal, ou criação de client SDK |
| `client:remove` | Client removido (API, SDK, transferência por channel link, falha/cancelamento de link) |
| `client:update` | Canal casou usuário, client ativado, usuário desinscreveu/bloqueou |
| `conversation:create` | Nova conversa criada |
| `conversation:join` | Novo participante entra em conversa `sdkGroup` |
| `conversation:leave` | Participante sai de conversa `sdkGroup` |
| `conversation:remove` | Conversa apagada |
| `conversation:message` | Nova mensagem na conversa |
| `conversation:message:delivery:channel` | Mensagem entregue com sucesso ao canal |
| `conversation:message:delivery:failure` | Falha ao entregar mensagem |
| `conversation:message:delivery:user` | Mensagem entregue com sucesso ao usuário |
| `conversation:postback` | Usuário clicou em botão de postback |
| `conversation:read` | Usuário leu a conversa |
| `conversation:referral` | Usuário referido para uma conversa |
| `conversation:typing` | Usuário começou/parou de digitar (**só end user, não agente**) |
| `passthrough:messaging` | Mensagem recebida com info a repassar como veio |
| `switchboard:acceptControl` | Integração switchboard aceitou controle da conversa |
| `switchboard:acceptControl:failure` | Falha ao aceitar controle |
| `switchboard:offerControl` | Controle foi oferecido a uma integração |
| `switchboard:offerControl:failure` | Falha ao oferecer controle |
| `switchboard:passControl` | Uma integração passou controle para outra |
| `switchboard:passControl:failure` | Falha ao ativar a integração |
| `switchboard:releaseControl` | Integração liberou o controle |
| `user:merge` / `user:update` / `user:remove` | Ciclo de vida do usuário |

**Envelope real, copiado verbatim do spec** (exemplo `conversation:message:delivery:channel`):

```yaml
app:
  id: 5ebee0975ac5304b664a12fa
webhook:
  id: 5f4eaef81e3dcc117c7ba48a
  version: v2
events:
  - id: 5f74a0d52b5315fc007e798a
    createdAt: '2020-09-30T15:14:29.834Z'
    type: conversation:message:delivery:channel
    payload:
      conversation:
        id: f52b01137aa6c250bc7251fa
        type: personal
        activeSwitchboardIntegration:
          id: 5eecde2dcdbffb08f5c3ed37
          name: bot
          integrationId: 5f11a650e4e987667c2051d1
          integrationType: custom
      user:
        id: 26508c10541a4b0ff472e5e2
        externalId: '912382197'
        authenticated: true
      destination:
        type: telegram
        integrationId: 5ec69c6e12dda33be985cb1a
      externalMessages:
        - id: '371'
      message:
        id: 5f74a31c2b5315fc007e7997
      isFinalEvent: true
```

Três coisas de desenho que valem cópia:
- **`events` é um array** — a Sunshine faz *batching* de eventos numa entrega só.
- **`events[].id`** existe explicitamente "para garantir que um evento não seja processado duas vezes no caso de um webhook re-tentado por erro ou timeout" (texto do spec, campo `eventSubSchema.id`). É idempotência declarada no contrato.
- **`webhook.version`** viaja no payload — dá pra versionar o contrato sem quebrar consumidor.

---

### A.1.3 HubSpot

`[FATO]` https://developers.hubspot.com/docs/api-reference/legacy/webhooks/guide.md

Subscription types CRM (todos com escopo obrigatório): `contact.creation`, `contact.deletion`, `contact.merge`, `contact.associationChange`, `contact.restore`, `contact.privacyDeletion`, `contact.propertyChange`; o mesmo conjunto para `company.*`, `deal.*`, `ticket.*`, `product.*`, `line_item.*`.

**Conversations (é o que interessa pro chat):**

| Subscription type | Escopo | Descrição (verbatim) |
|---|---|---|
| `conversation.creation` | `conversations.read` | "Get notified if a new thread is created in an account." |
| `conversation.deletion` | `conversations.read` | "Get notified if a thread is archived or soft-deleted in an account." |
| `conversation.privacyDeletion` | `conversations.read` | "Get notified if a thread is permanently deleted in an account." |
| `conversation.propertyChange` | `conversations.read` | "Get notified if a property on a thread has been changed." |
| `conversation.newMessage` | `conversations.read` | "Get notified if a new message on a thread has been received." |

Propriedades observáveis via `conversation.propertyChange` `[FATO]`: `assignedTo` (reatribuição — `propertyValue` = actor ID, vazio se desatribuiu), `status` (`OPEN` ou `CLOSED`), `isArchived`.

**Payload real, copiado verbatim:**

```json
[
  {
    "objectId": 1246965,
    "propertyName": "lifecyclestage",
    "propertyValue": "subscriber",
    "changeSource": "ACADEMY",
    "eventId": 3816279340,
    "subscriptionId": 25,
    "portalId": 33,
    "appId": 1160452,
    "occurredAt": 1462216307945,
    "eventType": "contact.propertyChange",
    "attemptNumber": 0
  },
  {
    "objectId": 1246978,
    "changeSource": "IMPORT",
    "eventId": 3816279480,
    "subscriptionId": 22,
    "portalId": 33,
    "appId": 1160452,
    "occurredAt": 1462216307945,
    "eventType": "contact.creation",
    "attemptNumber": 0
  }
]
```

Campos específicos de conversa `[FATO]`: `messageId` ("only sent when a webhook is listening for new messages to a thread") e `messageType` (`MESSAGE` ou `COMMENT`).

**Batching, ordem e duplicidade (verbatim):** "you should expect to receive an array of objects in a single request. The batch size can vary, but will be under 100 notifications." / "HubSpot does not guarantee that you'll receive these notifications in the order they occurred." / "HubSpot also does not guarantee that you'll only get a single notification for an event."

O campo **`attemptNumber`** vem no payload — o consumidor sabe se está vendo uma retentativa. `[INFERÊNCIA]` É o equivalente barato do `X-Chatwoot-Delivery`, mas mais informativo, porque diz *qual* tentativa é.

---

### A.1.4 Tidio

`[FATO]` https://developers.tidio.com/reference/events.md — **15 tópicos**:

```
contact.updated                    contact.created
conversation.solved_by_operator    conversation.solved_by_lyro
conversation.solved_automatically  conversation.operator_replied
ticket.created                     ticket.status_updated
ticket.operator_assigned           ticket.operator_replied
ticket.contact_replied             ticket.internal_note_added
ticket.replied                     ticket.holder_changed
customer_satisfaction.rated
```

Repare: `conversation.solved_by_lyro` (resolvido pela IA) tem campo `reason` com valor `"handoff"` — o Tidio expõe *por que* a IA encerrou. E `customer_satisfaction.rated` existe como evento de primeira classe.

**Envelope real, verbatim** `[FATO]` https://developers.tidio.com/docs/webhooks-structure.md:

```json
{
    "created_at": 1687177445,
    "project_public_key": "m8ixolegtgfvo6ckzvmuempdq0obbqsy",
    "topic": "contact.created",
    "version": 1,
    "webhook_id": "7307ac4d-2c74-4d32-b7f9-f7d037ed2ebb",
    "content": {
        ...
    }
}
```

Headers mínimos, verbatim:
```
content-type: application/json
user-agent: Tidio Webhook
x-tidio-signature: t=1687177446,s=4ecdcaf813c422d34413671b2ed68e0a6e69ea8496d34ab40bd33cef26571e70
```

Payload de `conversation.operator_replied`, verbatim:
```json
{
  "contact_id": "b8f4b536-0362-41d6-a692-f25e767835e2",
  "message": {
    "id": "1001",
    "operator_id": "555",
    "operator_name": "Bart",
    "operator_avatar_url": "https://example.com/avatar.png",
    "message": "Hi — I can help with that.",
    "created_at": "2026-04-22T09:14:02+00:00"
  }
}
```
com a nota explícita "Visitor-authored messages are not emitted on this topic."

**Anti-loop declarado** `[FATO]` https://developers.tidio.com/docs/webhooks-delivering.md: "To prevent creating an event loop, notifications will not be issued for events triggered by OpenAPI. For example, importing contacts into Tidio using OpenAPI will not send a `contact.created` webhook."

`[INFERÊNCIA]` Isso é uma decisão de produto que o Chatwoot não tomou: no Chatwoot, uma mensagem criada por API dispara `message_created` normalmente, o que exige que o integrador se proteja de loop sozinho.

---

### A.1.5 Crisp — o catálogo mais extenso do grupo

`[FATO]` https://docs.crisp.chat/references/web-hooks/v1/

O Crisp tem **duas origens de webhook**, com garantias diferentes (isso importa muito):

| Origem | Configurado em | Assinado? | Retry? | Nº de namespaces |
|---|---|---|---|---|
| **Plugin Hooks** | Crisp Marketplace (integração) | **Sim** (`X-Crisp-Signature`) | **Sim** | ~60 |
| **Website Hooks** | Configurações do site | **Não** | **Não** | ~35 (subconjunto) |

Texto verbatim: *"Those Web Hooks are not signed, nor is delivery attempted multiple times in case of a failure."* — referindo-se aos Website Hooks.

**Namespaces de sessão** (parcial, os relevantes ao widget):
```
session:update_availability   session:update_verify        session:request:initiated
session:set_email             session:set_phone            session:set_address
session:set_subject           session:set_avatar           session:set_nickname
session:set_origin            session:set_data             session:set_segments
session:set_block             session:set_opened           session:set_closed
session:set_participants      session:set_mentions         session:set_routing
session:set_inbox             session:set_state            session:sync:capabilities
session:sync:geolocation      session:sync:system          session:sync:network
session:sync:timezone         session:sync:locales         session:sync:pages
session:sync:events           session:sync:rating          session:sync:topic
session:removed               session:error
```

**Namespaces de mensagem:**
```
message:updated               message:send                 message:received
message:removed               message:compose:send         message:compose:receive
message:acknowledge:read:send        message:acknowledge:read:received
message:acknowledge:unread:send      message:acknowledge:delivered
message:acknowledge:ignored          message:notify:unread:send
message:notify:unread:received
```

**People / Campaign / Browsing / Call / Identity / Status / Website / Bucket / Email / Plugin / Plan:**
```
people:profile:created  people:profile:updated  people:profile:removed
people:bind:session     people:sync:profile
campaign:progress       campaign:dispatched     campaign:running
browsing:request:initiated  browsing:request:rejected
call:request:initiated      call:request:rejected
identity:verify:request
status:health:changed
website:update_visitors_count  website:update_operators_availability  website:users:available
bucket:url:upload:generated (e variantes avatar/website/campaign/helpdesk/status/processing)
email:subscribe  email:track:view
plugin:channel  plugin:event  plugin:subscription:updated  plugin:settings:saved
plan:subscription:updated
```

**Envelope real, verbatim:**
```json
{
  "website_id": "<website_id>",
  "event": "<event_name>",
  "data": { /* Event data (same as sent over the RTM API) */ },
  "timestamp": 0
}
```

**Payload de `message:send` (visitante → operadores), verbatim:**
```json
{
  "website_id": "42286ab3-b29a-4fde-8538-da0ae501d825",
  "event": "message:send",
  "data": {
    "website_id": "42286ab3-b29a-4fde-8538-da0ae501d825",
    "session_id": "session_36ba3566-9651-4790-afc8-ffedbccc317f",
    "inbox_id": null,
    "type": "text",
    "origin": "chat",
    "content": "Hello Crisp, this is a message from a visitor!",
    "timestamp": 1632396148646,
    "fingerprint": 163239614854320,
    "from": "user",
    "user": {
      "nickname": "visitor607",
      "user_id": "session_36ba3566-9651-4790-afc8-ffedbccc317f"
    },
    "stamped": true
  },
  "timestamp": 1632396148743
}
```

Tipos de mensagem suportados no mesmo evento (campo `type`): `text`, `file`, `animation`, `audio`, `picker`, `field`, `carousel`. `picker` é a resposta do visitante a uma seleção — quer dizer que o webhook do Crisp carrega **respostas de menu interativo** como evento nativo.

Um ponto que vale para o nosso desenho: **os payloads do webhook são idênticos aos da RTM API (WebSocket)**. Texto verbatim: *"Event data (same as sent over the RTM API)"*. Um contrato, dois transportes.

---

### A.1.6 LiveChat / Text Platform

`[FATO]` https://platform.text.com/docs/management/webhooks e https://platform.text.com/docs/management/configuration-api

Ações de webhook, agrupadas:

- **Chats:** `incoming_chat`, `chat_deactivated`
- **Acesso ao chat:** `chat_access_updated`, `chat_transferred`
- **Usuários no chat:** `user_added_to_chat`, `user_removed_from_chat`
- **Eventos:** `incoming_event`, `event_deleted`, `event_updated`, `incoming_rich_message_postback`
- **Propriedades:** atualização/remoção de chat properties, thread properties, event properties
- **Tags de thread:** `thread_tagged`, `thread_untagged`
- **Roteamento:** `routing_status_set`
- **Cliente:** `customer_session_fields_updated`
- **Configuração:** ciclo de vida de agente (created, approved, updated, suspended, unsuspended, deleted), bots, grupos, tags
- **Outros:** `events_marked_as_seen`, `thread_summary_set`

**Formato geral, verbatim:**
```json
{
  "webhook_id": "<webhook_id>",
  "secret_key": "<secret_key>",
  "action": "<action>",
  "organization_id": "<organization_id>",
  "payload": {},
  "additional_data": {
    "chat_properties": {},
    "chat_presence_user_ids": []
  }
}
```

⚠️ Diferença de desenho importante: o **`secret_key` viaja DENTRO do corpo**, não como header de assinatura. Isso é *shared secret*, não HMAC — o corpo não é assinado, então não protege contra adulteração em trânsito se o TLS for terminado por um intermediário. `[INFERÊNCIA]` É o esquema mais fraco entre os nove fornecedores medidos.

---

### A.1.7 Freshchat

`[FATO]` https://crmsupport.freshworks.com/support/solutions/articles/50000004461-freshchat-webhooks-payload-structure-and-authentication

Apenas **4 eventos**:

| `action` | Quando |
|---|---|
| `message_create` | Mensagem enviada (por agente, usuário ou bot) |
| `conversation_assignment` | Conversa atribuída |
| `conversation_resolution` | Conversa resolvida |
| `conversation_reopen` | Conversa reaberta |

Payloads verbatim:

```json
{
  "actor": { "actor_type": "agent", "actor_id": "1b8d2418-89a3-4de6-b93c-9f6557f13d04" },
  "action": "message_create",
  "action_time": "2022-11-22T10:55:23.126Z",
  "data": {
    "message": {
      "message_parts": [{ "text": { "content": "Hi there!" } }],
      "app_id": "c6ec783e-4c89-490a-bbbc-32c97e2a8c3d",
      "actor_id": "1b8d2418-89a3-4de6-b93c-9f6557f13d04",
      "conversation_id": "35e80ec8-c697-42e4-8ce9-a47a050b1d1a",
      "actor_type": "agent"
    }
  }
}
```

```json
{
  "actor": { "actor_type": "agent", "actor_id": "fc2d90bc-688b-46bc-a5f0-bcd60b7c2370" },
  "action": "conversation_assignment",
  "action_time": "2020-04-07T13:35:18.622Z",
  "data": {
    "assignment": {
      "assignor": "agent",
      "to_agent_id": "999abdc6-e4b1-4944-a246-86f63109df7e",
      "conversation": { "conversation_id": "40c15ddf-74e0-41e5-870e-69187d085778" }
    }
  }
}
```

```json
{
  "actor": { "actor_type": "agent" },
  "action": "conversation_resolution",
  "action_time": "2020-04-06T15:59:46.407Z",
  "data": {
    "resolve": {
      "resolver": "agent",
      "conversation": { "conversation_id": "aecf3cc7-138a-4b40-9723-5bf4d1abb97b", "status": "resolved" }
    }
  }
}
```

```json
{
  "actor": { "actor_type": "agent" },
  "action": "conversation_reopen",
  "action_time": "2020-04-07T13:28:49.194Z",
  "data": {
    "reopen": {
      "reopener": "agent",
      "conversation": { "conversation_id": "40c15ddf-74e0-41e5-870e-69187d085778", "status": "reopened" }
    }
  }
}
```

Catálogo pobre — menor que o do Chatwoot. Mas o Freshchat é o **único do grupo que assina com criptografia assimétrica** (`SHA256withRSA` com chave pública), e envia `X-Retry-Count` no header.

---

### A.1.8 tawk.to

`[FATO]` https://developer.tawk.to/webhooks/

**4 eventos:** `chat:start`, `chat:end`, `chat:transcript_created`, `ticket:create`.

Payload de `chat:start` verbatim:
```json
{
  "event": "chat:start",
  "chatId": "70fe3290-99ad-11e9-a30a-51567162179f",
  "time": "2019-06-28T14:03:04.646Z",
  "domain": "tawk.to",
  "referrer": "https://www.google.com/",
  "message": {
    "text": "Sample message",
    "type": "msg",
    "sender": { "type": "visitor" }
  },
  "visitor": {
    "name": "V1561719148780935",
    "email": "hello@test.com",
    "city": "jelgava",
    "country": "LV"
  },
  "property": {
    "id": "58ca8453b8a7e060cd3b1ecb",
    "name": "Bobs Burgers"
  }
}
```

Nota da doc, verbatim: *"Generated when the first message in a chat is sent by visitor or agent. Whispers and system notifications like triggers do not generate this event."*

`chat:transcript_created` entrega a conversa **inteira** num payload só, com anexos resolvidos em URL, mimeType, size e extension. Payload verbatim (recortado):
```json
{
  "event": "chat:transcript_created",
  "time": "2024-07-03T01:02:37.780Z",
  "domain": "tawk.to",
  "referrer": "https://www.google.com/",
  "chat": {
    "id": "70fe3290-99ad-11e9-a30a-51567162179f",
    "visitor": { "name": "V1561719148780935", "email": "hello@test.com", "city": "jelgava", "country": "LV" },
    "messages": [
      { "sender": { "t": "s", "n": "Customer Support" }, "type": "msg",
        "msg": "👋 Hi! How can we help?\n[option]I have a question\n[option]Tell me more",
        "time": "2024-07-03T01:02:37.780Z" },
      { "sender": { "t": "v" }, "type": "msg", "msg": "Tell me more", "time": "2024-07-03T01:02:48.176Z" },
      { "sender": { "t": "a", "n": "Eugene", "id": "666668688fe587223fdf8685" }, "type": "msg", "msg": "msg",
        "time": "2024-07-03T01:02:37.780Z",
        "attchs": [ { "type": "file", "content": { "file": {
            "url": "https://tawkto.link/.../tawky_big.png",
            "name": "tawky_big.png", "mimeType": "image/png", "size": 3797, "extension": "png" } } } ] }
    ]
  },
  "property": { "id": "58ca8453b8a7e060cd3b1ecb", "name": "Bobs Burgers" }
}
```

`[INFERÊNCIA]` O `chat:transcript_created` é um padrão que o Chatwoot não tem e que resolve um problema real: quem quer arquivar a conversa num CRM não precisa remontar N eventos `message_created` em ordem — recebe o transcript pronto, uma vez, depois que acabou.

---

### A.1.9 JivoChat

`[FATO]` https://www.jivochat.com/docs/webhooks/ e https://www.jivochat.com/help/api/api-crm.html

Eventos (campo `event_name`): `call_event`, `chat_accepted`, `chat_assigned`, `chat_updated`, `client_updated`, `client_attribute_updated`, `chat_finished`, `offline_message`. Mais eventos de pipeline: `created_pipeline`, `assigned_status`, `created_status`/`updated_status`/`deleted_status`.

Payload de `chat_accepted` verbatim (recortado):
```json
{
  "event_name": "chat_accepted",
  "widget_id": "3948",
  "user_token": null,
  "visitor": { "name": "John Smith", "email": "email@example.com", "phone": "+14084987855",
               "description": "Description text", "number": "2198", "social": {}, "chats_count": 1 },
  "organization": { "id": "1", "name": "Company name" },
  "status": { "id": "4", "title": "contact_later" },
  "assigned_agent": { "id": 1, "email": "agent1@gmail.com", "name": "Agent" },
  "tags": [ { "id": "17", "title": "Tag example" } ],
  "chat_id": 7636,
  "department": { "id": 281, "name": "Sales" },
  "session": {
    "geoip": { "region_code": "CA", "country": "United States", "country_code": "US",
               "region": "California", "city": "San Francisco",
               "latitude": "37.7898", "longitude": "-122.3942", "organization": "Wikimedia Foundation" },
    "utm": "source=google|medium=cpc|content=banner|campaign=campaign_name",
    "utm_json": { "source": "google", "campaign": "campaign_name", "content": "banner", "medium": "cpc", "term": "..." },
    "ip_addr": "208.80.152.201",
    "user_agent": "Mozilla/5.0 (Macintosh; ...) Chrome/54.0.2840.71 Safari/537.36"
  },
  "page": { "url": "http://example.com/", "title": "Page title" },
  "analytics": {},
  "agent": { "id": "2016", "name": "Thomas Anderson", "email": "agent@jivosite.com", "phone": "+14083682346" }
}
```

Duas coisas notáveis:
1. **`utm_json` vem parseado no payload.** O Chatwoot guarda `additional_attributes` bruto — quem consome tem que garimpar.
2. **O webhook do Jivo é SÍNCRONO E BIDIRECIONAL.** A resposta HTTP do CRM ao webhook é usada: se a resposta a `chat_accepted` traz `contact_info`, *"this data will be displayed to the agent as if a visitor introduced himself in the chat form. It will be saved in the chat log as well."* Resposta verbatim:
```json
{"result":"ok",
 "custom_data":[{"title":"Answer","content":"42"},{"title":"Last chat","content":"27 Sep 2016 19:37:12"}],
 "contact_info":{"name":"John Doe","phone":"+79500123567","email":"johny1337@jivoteam.com","description":"Visitor comment"},
 "enable_assign":true,
 "crm_link":"http:\/\/mycrm.ru\/user\/1"}
```

`[INFERÊNCIA]` Esse é o padrão "webhook que enriquece": o chat pergunta ao CRM quem é a pessoa **enquanto o agente abre a conversa**, e o painel do agente já mostra saldo, plano, link pro cadastro. É a integração de maior valor percebido de todo o levantamento, e o Chatwoot não tem nada equivalente no fluxo de webhook (o mais próximo é o Dashboard App em iframe — ver §D.11.5).

---

## A.2 Confiabilidade — tabela comparativa medida

| Fornecedor | Assinatura (header / algoritmo / o que é assinado) | Timeout esperado | Retentativas | Após N falhas | Ordem garantida? | Idempotência oferecida |
|---|---|---|---|---|---|---|
| **Intercom** | `X-Hub-Signature` — HMAC **SHA-1**, hex (40 bytes), prefixo `sha1=`, chave = `client_secret` do App, material = corpo JSON. Verbatim: *"The signature is the hexadecimal (40-byte) representation of an SHA-1 signature computed using the HMAC algorithm defined in RFC2104"*. Exemplo real da doc: `X-Hub-Signature: sha1=21ff2e149e0fdcac6f947740f6177f6434bda921` | **5000 ms** | reenvia se não receber `200` em 5000 ms | >1000 erros HTTP consecutivos em 15 min → **pausa 15 min**; erros por **>7 dias** → **suspende a subscription** (só para Private apps) | **Não** — "we do not offer any guarantee on the order" | `id` do notification + `delivery_attempts` no payload |
| **Zendesk (Webhooks)** | `X-Zendesk-Webhook-Signature` + `X-Zendesk-Webhook-Signature-Timestamp` — `base64(HMACSHA256(TIMESTAMP + BODY))` | **12 s** | `409` → até **3**; `429`/`503` → só se `retry-after` < 60 s; **timeout → até 5** | Falhas consecutivas **não desativam**; disparam *circuit breaker*: 70% de erro em 5 min **ou** >1000 erros em 5 min (não ativa com <100 req/5 min) → bloqueia **5 s** | `[NÃO VERIFICADO]` | Activity log de 7 dias, filtrável por `filter[status]=failed` |
| **Sunshine Conversations** | `X-API-Key` = shared secret gerado na criação do webhook (**não é HMAC do corpo**) | **20 s** | até **5 tentativas numa janela de 15 min**, intervalo exponencial | Aborta em *non-recoverable*: `400`, `401`, `403`, `404`, `406` | `[NÃO VERIFICADO]`; `externalMessages` diz explicitamente que a ordem **não** é garantida entre triggers | `events[].id` documentado *"May be used to ensure that an event is not processed twice"* |
| **HubSpot** | `X-HubSpot-Signature` (v1: SHA-256 de `secret+body`; v2: `secret+method+uri+body`) — **ou** `X-HubSpot-Signature-v3` + `X-HubSpot-Request-Timestamp` (HMAC-SHA256 base64 de `method+uri+body+timestamp`) | **5 s** | até **10**, espalhadas por **24 h**, com jitter | Doc não menciona desativação | **Não** — "does not guarantee that you'll receive these notifications in the order they occurred" | `eventId` (**não garantido único**) + `attemptNumber` no payload; v3 rejeita requisição > **300 000 ms** |
| **Tidio** | `x-tidio-signature: t=<ts>,s=<hmac>[,s=<hmac2>]` — HMAC-SHA256 de `{body}_{timestamp}`; **múltiplos `s` para rotação de segredo** | **4 s** | **9 retentativas**: 5 s, 10 s, 30 s, 1 min, 3 min, 10 min, 30 min, 1 h, 3 h (última ~4 h 45 min após a original) | Doc não menciona desativação automática; painel tem *Logs* e taxa de erro dos últimos 7 dias | **Não** — "requests can be sent in random order" | `webhook_id` (uuid) — "Keeping track of the processed webhooks in your system by storing information about them is recommended" |
| **Crisp (Plugin Hooks)** | `X-Crisp-Signature` + `X-Crisp-Request-Timestamp` — HMAC-SHA256 de `[timestamp;body_as_string]` (com `[` `]` e `;`) | `[NÃO VERIFICADO]` | Sim; nº nos headers `X-Delivery-Attempt-Limit` / `X-Delivery-Attempt-Count` | Se todas falharem: *"we will pause all Web Hook deliveries to your endpoint for about a minute, meaning some events will never be received"* | `[NÃO VERIFICADO]` | `X-Delivery-Attempt-Count` + `fingerprint` no payload de mensagem |
| **Crisp (Website Hooks)** | **Nenhuma** | — | **Nenhuma** | — | — | — |
| **LiveChat / Text** | `secret_key` **no corpo** — shared secret, sem HMAC | **~10 s** (verbatim: *"The timeout is set to approx. 10 seconds"*) | **até 3 em ~1 minuto** (verbatim: *"we'll retry sending the webhook up to 3 times within ~1 minute"*) | `[NÃO VERIFICADO]` | `[NÃO VERIFICADO]` | `webhook_id` no corpo |
| **Freshchat** | `X-Freshchat-Signature` — **SHA256withRSA** (chave **pública** fornecida no painel), base64 | `[NÃO VERIFICADO]` | Sim — header `X-Retry-Count` | `[NÃO VERIFICADO]` | `[NÃO VERIFICADO]` | `X-Retry-Count` |
| **tawk.to** | `X-Tawk-Signature` — HMAC-**SHA1** hex do corpo | **30 s** | Retenta **por até 12 h** enquanto não receber 2XX | `[NÃO VERIFICADO]` | `[NÃO VERIFICADO]` | **`X-Hook-Event-Id` — "The event Id will remain the same in case of retries"** (o melhor contrato de idempotência do grupo) |
| **JivoChat (CRM webhooks)** | Nenhuma assinatura documentada; a credencial é a URL secreta | `[NÃO VERIFICADO]` | `[NÃO VERIFICADO]` para CRM webhooks | — | — | — |
| **JivoChat (Chat API)** | URL contém string aleatória + `JIVO_PUBLIC_ID` | ~3 s | **3 tentativas a cada 3 s** ("This gives 6 seconds to update the software on the server"); erro após 9 s | Agente vê mensagem de erro no chat | — | `message.id` |
| **JivoChat (Bot API)** | idem | **3 s** | **2 retentativas** | Se não responder: *"the chat is transferred to the agent"* | — | `id` (uuid do evento) |
| **🟡 Chatwoot/ChatSPX — webhook de CONTA** | `X-Chatwoot-Signature` + `X-Chatwoot-Timestamp` — `sha256=HMAC-SHA256(secret, "{ts}.{body}")` | **5 s** (default; `WEBHOOK_TIMEOUT`) | **NENHUMA** `[MEDIDO]` | Nada — só `Rails.logger.warn` | Não garantida (jobs concorrentes) | `X-Chatwoot-Delivery` (uuid) — mas sem retry, nunca se repete |
| **🔴 Chatwoot/ChatSPX — webhook de INBOX (canal API)** | **NENHUMA** `[MEDIDO]` | 5 s | **NENHUMA** | Marca a mensagem como `failed` | Não garantida | `X-Chatwoot-Delivery` presente |
| **🔴 Chatwoot/ChatSPX — webhook de AGENT BOT** | **NENHUMA** `[MEDIDO]` | 5 s | **3 tentativas, wait 3 s** — **só** em `429` e `500`. Connection refused / timeout / 502 / 503 **não** retentam `[MEDIDO]` | Reabre a conversa (`pending` → `open`) e posta mensagem de atividade, salvo `keep_pending_on_bot_failure` | Não garantida | **NENHUM** `X-Chatwoot-Delivery` `[MEDIDO]` |
| **🔴 Chatwoot/ChatSPX — webhook de AUTOMAÇÃO / MACRO / FLOW** | **NENHUMA** `[MEDIDO]` | 5 s | **NENHUMA** | Nada | — | Nenhum |

**Fontes das linhas de fornecedor:**
Intercom → https://developers.intercom.com/docs/webhooks/webhook-notifications.md (timeout/retry/pausa/suspensão/rate limit) e https://developers.intercom.com/docs/references/webhooks/webhook-models.md §"Signed notifications" (assinatura) ·
Zendesk → https://developer.zendesk.com/documentation/webhooks/verifying/ e https://developer.zendesk.com/documentation/webhooks/creating-and-monitoring-webhooks/ ·
Sunshine → https://raw.githubusercontent.com/zendesk/sunshine-conversations-api-spec/master/openapi.yaml ·
HubSpot → https://developers.hubspot.com/docs/api-reference/legacy/webhooks/guide.md e https://developers.hubspot.com/docs/apps/legacy-apps/authentication/validating-requests ·
Tidio → https://developers.tidio.com/docs/webhooks-delivering.md e https://developers.tidio.com/docs/webhooks-signature-verification.md ·
Crisp → https://docs.crisp.chat/references/web-hooks/v1/ ·
LiveChat → https://platform.text.com/docs/management/configuration-api (formato, filtros, limite de 3/action) + https://platform.text.com/docs/getting-started/livechat-apps/webhook-apps/ (timeout ~10 s e até 3 retries em ~1 min, **citado verbatim**) ·
Freshchat → https://crmsupport.freshworks.com/support/solutions/articles/50000004461-freshchat-webhooks-payload-structure-and-authentication ·
tawk.to → https://developer.tawk.to/webhooks/ ·
JivoChat → https://www.jivochat.com/help/api/webhooks-api.html e https://www.jivochat.com/docs/bot/

### Leitura da tabela — o que ela diz de fato

- **Assinatura HMAC do corpo é o padrão de 2026**, mas há três escolas: HMAC com timestamp no material assinado (Zendesk, HubSpot v3, Tidio, Crisp, **Chatwoot**) — a mais forte, porque protege contra replay; HMAC só do corpo (Intercom, tawk.to) — protege integridade, não replay; e shared secret sem HMAC (Sunshine `X-API-Key`, LiveChat `secret_key` no corpo) — só autentica origem.
- **O Chatwoot está no grupo mais forte na assinatura do webhook de conta.** Isso é um fato favorável e frequentemente ignorado.
- **Retry é universal, com uma exceção: nós.** A janela varia de ~1 min (LiveChat) a 24 h (HubSpot), passando por 12 h (tawk.to) e ~4h45 (Tidio). O Chatwoot é o único da lista com **zero** retentativa no caminho principal.
- **Ordem NUNCA é garantida** por ninguém que documenta o assunto (Intercom, HubSpot, Tidio dizem explicitamente que não). Isso é consenso de indústria: o consumidor ordena por timestamp. Não é um gap nosso.
- **Idempotência é sempre delegada ao consumidor**, mas os bons dão a chave. O tawk.to é o mais explícito ("o event Id permanece o mesmo em caso de retry"). O nosso `X-Chatwoot-Delivery` tem a forma certa e o comportamento errado (é regenerado por entrega e não há retry para reaproveitá-lo).

---

## A.3 Filtro por evento, por inbox, e limites de taxa

| Fornecedor | Filtro por evento | Filtro por inbox/canal/caixa | Filtros avançados | Limite de taxa |
|---|---|---|---|---|
| **Intercom** | Sim (topics, via Developer Hub) | Não (é por App/workspace) | — | US: **150 000 eventos/min**; EU e AU: **20 000/min**. Endpoints que respondem em >500 ms recebem prioridade menor. `429` do seu lado → throttle de 1 min até 2 h; descarta se não obtiver sucesso em 2 h |
| **Zendesk** | Sim (event types ou trigger) | Sim, indiretamente (trigger com condição de brand/form/grupo) | Condições de trigger completas | Circuit breaker (ver A.2). Requisições do webhook não contam contra rate limit da API |
| **Sunshine** | Sim (array `triggers`) | Escopo = 1 app; **máx. 10 webhooks por app** | — | `[NÃO VERIFICADO]` |
| **HubSpot** | Sim (`subscriptionType` + `propertyName` para property change) | Não | — | `maxConcurrentRequests` configurável (mín. > 5, exemplo 10); **máx. 1000 subscriptions por app**; cada requisição carrega até 100 eventos; POSTs de webhook **não** contam contra o rate limit da API do app |
| **Tidio** | Sim (seleção de eventos por webhook, agrupados em *stacks*) | `[NÃO VERIFICADO]` | — | API: Plus **60 req/min**, Premium **120 req/min** (Free: indisponível) |
| **Crisp** | Sim (por namespace) | `inbox_id` **vem no payload** mas não filtra | Plugin vs Website hook define o conjunto disponível | `[NÃO VERIFICADO]` |
| **LiveChat** | Sim (por `action`) | Sim — `filters.only_my_chats`, `filters.chat_presence.user_ids.values` / `.exclude_values`, `filters.my_bots`, `filters.source_type` (`my_client`/`other_clients`/`system`), `filters.author_type` (`customer`/`agent`, só para `incoming_event` e `event_updated`) | **O melhor sistema de filtro do grupo** | **3 webhooks por action por Client ID** |
| **Freshchat** | `[NÃO VERIFICADO]` (parece ser tudo-ou-nada nos 4 eventos) | `[NÃO VERIFICADO]` | — | `[NÃO VERIFICADO]` |
| **tawk.to** | Sim (4 eventos selecionáveis) | Sim — webhook é por **property** (site) | — | `[NÃO VERIFICADO]` |
| **JivoChat** | Parcial (o conjunto é fixo por tipo de integração) | **Sim — a URL de webhook é configurada POR CANAL** | — | `[NÃO VERIFICADO]` |
| **🟡 Chatwoot/ChatSPX** | Sim (`subscriptions` array, 12 eventos) `[MEDIDO]` `app/models/webhook.rb:32-34` | **NÃO** — enum existe, nada usa `[MEDIDO]` (ver §D.10.5) | Nenhum | **Nenhum limite de taxa de entrega**; o `WebhookJob` entra na fila `medium` sem throttle `[MEDIDO]` `app/jobs/webhook_job.rb:2` |

> ⚠️ **Restrição não óbvia do Chatwoot:** `validates :url, uniqueness: { scope: [:account_id] }` (`app/models/webhook.rb:28`) `[MEDIDO]`. Isso significa que **uma conta não pode registrar a mesma URL duas vezes com conjuntos de eventos diferentes**. No LiveChat você pode ter 3 webhooks por action; aqui, se você já mandou `message_created` pra `https://meu-erp/hook`, não dá pra criar um segundo webhook pra mesma URL com `conversation_created` — tem que juntar tudo num só e desambiguar do lado de lá.

---

# B. INBOUND — o sistema do cliente age no chat

## B.4 APIs REST — matriz de capacidades

Legenda: ✅ endpoint dedicado · 🟡 possível mas indireto · ❌ não existe/não documentado

| Ação | Intercom | Sunshine (Zendesk) | HubSpot | Crisp | LiveChat | Freshchat | Tidio | tawk.to | Jivo | **ChatSPX** |
|---|---|---|---|---|---|---|---|---|---|---|
| Criar contato | ✅ | ✅ `POST /users` | ✅ | ✅ | ✅ `update_customer` | ✅ `POST /v2/users` | ✅ `POST /contacts` | ❌ | 🟡 (via mensagem) | ✅ |
| Criar conversa | ✅ `POST /conversations` | ✅ `POST /conversations` | 🟡 | ✅ | ✅ `start_chat` | ✅ `POST /v2/conversations` | ❌ | ❌ | 🟡 | ✅ |
| Enviar msg como **agente** | ✅ `POST /conversations/{id}/reply` | ✅ `POST /conversations/{id}/messages` | ✅ | ✅ `from: operator` | ✅ `send_event` | ✅ `POST /v2/conversations/{id}/messages` | ❌ `[NÃO VERIFICADO]` | ❌ | ✅ (Chat API) | ✅ |
| Enviar msg como **contato** (ingestão) | ✅ (`from.type: contact`) | ✅ | ✅ (custom channels) | ✅ `from: user` | ✅ (Customer Chat API) | ✅ | ✅ `POST /contacts/{id}/messages` | ❌ | ✅ | ✅ (Client API) |
| Nota interna / privada | ✅ (`conversation.admin.noted`) | 🟡 | ✅ (`messageType: COMMENT`) | ✅ (`type: note`) | 🟡 | ✅ | ✅ (ticket) | ❌ | ❌ | ✅ (`private: true`) |
| Atualizar atributos do contato | ✅ | ✅ | ✅ | ✅ `session:set_data` | ✅ | ✅ | ✅ `PATCH /contacts/{id}` | ❌ | 🟡 (resposta do webhook) | ✅ |
| Aplicar etiqueta | ✅ | ❌ | ✅ | ✅ (segments) | ✅ `tag_thread` | ✅ | ✅ (tickets) | ❌ | 🟡 | ✅ |
| Atribuir a agente/time | ✅ | 🟡 (switchboard) | ✅ | ✅ `Assign Conversation Routing` | ✅ `transfer_chat` | ✅ | ✅ (tickets) | ❌ | ❌ | ✅ |
| Resolver / fechar | ✅ | ❌ | ✅ | ✅ `Change Conversation State` | ✅ `deactivate_chat` | ✅ | ✅ (tickets) | ❌ | ❌ | ✅ |
| Transferir bot → humano | ✅ | ✅ `passControl` | ✅ | 🟡 | ✅ `transfer_chat` | ✅ | 🟡 | ❌ | ✅ `INVITE_AGENT` | 🟡 (ver B.6) |
| **Msg proativa p/ visitante identificado** | ✅ **`POST /messages`, 1 chamada** | ✅ | 🟡 | ✅ | 🟡 | ✅ `outbound-messages` | ❌ | ❌ | ❌ | 🟡 **3 chamadas** (ver D.13) |

### Autenticação por fornecedor `[FATO]`

| Fornecedor | Esquema |
|---|---|
| Intercom | `Bearer` token — Access Token (private app) ou OAuth (public app). Limites: **10 000 req/min por app, 25 000/min por workspace**, distribuídos em janelas de 10 s. Headers `X-RateLimit-Limit/Remaining/Reset` |
| Sunshine Conversations | `basicAuth` (keyId/secret) ou `bearerAuth`; escopos `account` / `app` / `integration`. OAuth para parceiros de marketplace — token de escopo `integration` só enxerga os webhooks criados por ele mesmo |
| HubSpot | Private app token (Bearer) ou OAuth por app |
| Crisp | Token por *tier*: `user` (privado) ou `plugin` (marketplace, com escopos por namespace) |
| LiveChat/Text | OAuth 2.0 por Client ID; escopo `webhooks.configuration:rw` para gerenciar webhooks |
| Freshchat | OAuth 2.0 — `Authorization: Bearer <access-token>`, token com validade definida; escopos granulares (ex.: `freshchat.conversation.message.create`) |
| Tidio | Chave de projeto (OpenAPI habilitado no painel); disponível só em planos pagos |
| JivoChat | URL secreta com string aleatória + `JIVO_PUBLIC_ID` |
| **ChatSPX** | Header `api_access_token` — `AccessToken` polimórfico com dono `User` **ou** `AgentBot` `[MEDIDO]` `app/controllers/concerns/access_token_auth_helper.rb:8-20`. Sem OAuth para apps de terceiros. Sem escopos. Sem expiração. Platform API tem token próprio |

---

## B.5 O padrão "canal API" / conversational API

Todo fornecedor sério tem uma forma de dizer: *"use meu motor de atendimento, mas o front é meu"*. As implementações:

**Sunshine Conversations** — é o produto inteiro. `POST /v2/apps/{appId}/conversations` + `POST .../messages`, com `switchboard` para roteamento e `passthrough:messaging` para canais próprios. `[FATO]` openapi.yaml

**HubSpot Custom Channels API** — versão `2026-03`. Endpoints: criar canal (`POST /conversations/custom-channels/2026-03`), criar channel account, publicar mensagem (`POST .../messages`), atualizar mensagem. `[FATO]` https://developers.hubspot.com/docs/api-reference/latest/conversations/custom-channels/guide.md — é o mais novo dos três e o mais próximo do nosso `Channel::Api`.

**JivoChat Chat API** — o mais didático. `[FATO]` https://www.jivochat.com/help/api/webhooks-api.html. O contrato inteiro cabe numa página:

- Status do canal: `GET https://wh.jivosite.com/<random>/JIVO_PUBLIC_ID/status` → corpo `0` (offline) ou `1` (online), `404` se o canal não existe.
- Mensagem do usuário: `POST https://wh.jivosite.com/<random>/JIVO_PUBLIC_ID`
```json
{
  "sender": { "id": "12345", "name": "John Doe", "photo": "https://example.com/photo.jpg",
              "url": "https://ya.ru/simple/page.html", "phone": "12345678901",
              "email": "john@doe.com", "invite": "Hello! Can I help you?" },
  "message": { "type": "text", "id": "customer_message_id", "text": "User Message Text" }
}
```
- Mensagem do agente (Jivo → você): `POST <sua URL>/JIVO_PUBLIC_ID`
```json
{
  "sender": { "name": "Agent Name", "photo": "Agent Photo URL" },
  "recipient": { "id": "12345" },
  "message": { "type": "text", "id": "jivo_message_id", "text": "Agent Message Text" }
}
```
- Resposta esperada: `{"result":"ok"}` ou `{"error":{"code":<n>,"message":"..."}}` — *"An error message will be displayed to the agent in the JivoSite conversation"*.
- **`typein` / `typeout`** para indicador de digitação, **nos dois sentidos**.
- Multimídia: `video`, `audio`, `voice`, `photo`, `sticker`, `document`, `location`, cada um com campos obrigatórios declarados (`file`, `file_name`, `file_size`, ou `latitude`/`longitude`).
- Limite: mensagem cortada em **1000 caracteres**.

**LiveChat** — separa **Agent Chat API** (`start_chat`, `send_event`, `transfer_chat`, `tag_thread`, `update_chat_properties`, `set_routing_status`, `send_typing_indicator`, `send_thinking_indicator`, `multicast`, `request_thread_summary`…) de **Customer Chat API** (lado do visitante). `[FATO]` https://platform.text.com/docs/messaging/agent-chat-api

**Tidio** — meio-caminho: `POST /contacts/{contactId}/messages` — *"Ingests a message as if the contact had sent it themselves. Used by partners whose end-users type messages into a partner-hosted widget"*, resposta `202 Accepted`, processamento assíncrono. `[FATO]` https://developers.tidio.com/llms.txt

**ChatSPX** — temos os dois lados (§D.11.3). O nosso `Channel::Api` é comparável ao Custom Channels do HubSpot em capacidade; o que falta é o polimento do Jivo (endpoint de status do canal, `typein`/`typeout` bidirecional documentado, contrato de erro que o agente vê).

---

## B.6 Bots / agent-bots — como um bot externo se conecta

### JivoChat Bot API — o contrato mais enxuto `[FATO]` https://www.jivochat.com/docs/bot/

Cinco tipos de evento, com direção declarada:

| Tipo | Direção | Descrição (verbatim) |
|---|---|---|
| `CLIENT_MESSAGE` | JivoChat → Bot | "New client message event, that requires response options" |
| `BOT_MESSAGE` | Bot → JivoChat | "Bot's response to a client message" |
| `INVITE_AGENT` | Bot → JivoChat | **"Chat transfer from a bot to an agent"** |
| `AGENT_UNAVAILABLE` | JivoChat → Bot | "Event, informing that no agents are available to accept the chat at the moment" |
| `CHAT_CLOSED` | JivoChat → Bot | "Chat closing event" |

Payload de `CLIENT_MESSAGE`, verbatim:
```json
{
  "id": "9661ab9c-48b0-11ed-a3d6-859398ff9bd9",
  "site_id": "123456",
  "client_id": "1233",
  "chat_id": "2037",
  "agents_online": true,
  "sender": { "id": 1233, "name": "John Smith", "url": "https://test.com", "has_contacts": true },
  "message": { "type": "TEXT", "text": "Can you help me?", "timestamp": 1665415879 },
  "channel": { "id": "12345678", "type": "widget" },
  "event": "CLIENT_MESSAGE"
}
```

Resposta do bot com botões, verbatim:
```json
{
  "id": "093e9c6a-48b6-11ed-907d-7d426317dad5",
  "client_id": "1235",
  "chat_id": "2041",
  "message": {
    "type": "BUTTONS",
    "title": "Would you like to make an order?",
    "text": "Would you like to make an order? Yes / No",
    "timestamp": 1583910736,
    "force_reply": true,
    "buttons": [ { "text": "Yes", "id": 1 }, { "text": "No", "id": 2 } ]
  }
}
```

Confiabilidade, verbatim: *"The request timeout is 3 seconds, with 2 retries until a regular successful response is received. If not, **the chat is transferred to the agent**."*

`[INFERÊNCIA]` Essa última cláusula é o desenho certo: **falha de bot degrada para humano, não para silêncio**. O Chatwoot tem exatamente isso (§D.10.6) — é um dos pontos em que estamos alinhados com o melhor do mercado.

Dois campos do `CLIENT_MESSAGE` que valem cópia e que não temos: **`agents_online`** (o bot sabe se tem gente pra transferir antes de prometer transferência) e **`sender.has_contacts`** (o bot sabe se já tem e-mail/telefone antes de pedir de novo).

### Sunshine Conversations — switchboard `[FATO]` openapi.yaml

Modelo mais sofisticado: um **switchboard** com N *switchboard integrations* (bot, agente humano, terceiros), com um `activeSwitchboardIntegration` por conversa. Ações: `passControl` ("marca a integração selecionada como ativa e transiciona todas as outras para standby"), `offerControl` ("convida a integração a aceitar controle, mudando o status para pending, e dispara um webhook sinalizando a oferta"), `acceptControl`, `releaseControl`. Cada uma tem seu evento de sucesso e de falha (`switchboard:passControl:failure` etc.).

`[INFERÊNCIA]` É o único modelo do grupo em que **o handoff é uma máquina de estados observável**: você recebe webhook de oferta, de aceite e de falha. No Chatwoot, o handoff bot→humano é implícito (bot deixa de responder / conversa vira `open`), sem evento próprio.

### Intercom, HubSpot, Freshchat, Crisp

- **Intercom:** bots são "Operator"/Fin, com webhooks `conversation.operator.replied`. Bot externo se conecta como App via Canvas Kit ou como agente por API.
- **HubSpot:** "Running code snippets in bots" — a lógica roda dentro do chatflow. `[FATO]` https://developers.hubspot.com/docs/api-reference/latest/conversations/chat-configuration/working-with-chatbots.md
- **Crisp:** plugin com token tier `plugin` recebe todos os namespaces por webhook ou RTM (WebSocket) e responde por `POST /v1/website/{id}/conversation/{session}/message` com `from: operator`.
- **LiveChat:** `create_bot` na Configuration API, webhooks de tipo `bot`, `set_routing_status` para bots. Filtro `filters.my_bots` permite que o webhook só dispare quando um bot seu está no chat.

---

## B.7 Mensagem proativa a partir do backend do cliente

O caso concreto: *"o pedido dele saiu para entrega, avisa no chat"*.

| Fornecedor | Suporta? | Como |
|---|---|---|
| **Intercom** | ✅ **Sim, uma chamada** | `POST /messages` com `message_type: "in_app"`, `from: {type: "admin", id: <admin>}`, `to: {type: "user", id: <contact>}`, `body`. Campo `create_conversation_without_contact_reply: true` decide se abre conversa na inbox sem o contato responder. Aviso da doc: *"There can be a short delay between when a contact is created and when a contact becomes available to be messaged through the API. A 404 Not Found error will be returned in this case."* `[FATO]` https://developers.intercom.com/docs/references/rest-api/api.intercom.io/messages/createmessage.md |
| **Sunshine** | ✅ Sim | `POST /v2/apps/{appId}/conversations/{id}/messages` com `author.type: business`. Se não houver conversa, `POST /conversations` com `type: personal`. Campo `recentNotifications` no webhook `conversation:message` lista "Messages sent with the Notification API since the last user message" |
| **Freshchat** | ✅ Sim | `POST /v2/outbound-messages` (e `/v2/outbound-messages/whatsapp`), com `GET /v2/outbound-messages?request_id=` para auditar o envio `[FATO]` https://developers.freshchat.com/api/ |
| **Crisp** | ✅ Sim | `POST /v1/website/{website_id}/conversation/{session_id}/message` com `from: "operator"`, `origin: "chat"`, `type` entre `text`/`file`/`picker`/`carousel`/`field`/`event` `[FATO]` https://docs.crisp.chat/references/rest-api/v1/ |
| **HubSpot** | 🟡 Parcial | Custom Channels publica mensagem no thread; para o widget nativo o caminho é workflow/chatflow, não API direta `[NÃO VERIFICADO]` para o widget nativo |
| **LiveChat** | 🟡 | `start_chat` + `send_event` funcionam, mas exigem sessão de customer ativa `[NÃO VERIFICADO]` para visitante offline |
| **Tidio** | ❌ | O endpoint de mensagem (`POST /contacts/{id}/messages`) ingere **como o contato**, não como operador. Não achei endpoint de mensagem proativa como operador `[NÃO VERIFICADO]` |
| **tawk.to** | ❌ | Só webhooks de saída + JavaScript API no navegador. Sem REST de escrita |
| **JivoChat** | ❌ | Sem REST de escrita de mensagem para o widget nativo (o Chat API é para canal próprio) |
| **ChatSPX** | 🟡 **Sim, em 3 chamadas** | Ver §D.13 |

---

# C. Integração sem código

## C.8 Zapier / Make / n8n

### Zapier

**Intercom** `[FATO]` https://zapier.com/apps/intercom/integrations — o catálogo mais completo do grupo:

*Triggers (18):* Lead Added Email · Lead Converted to User · New Lead · Contact Replied · Tag Added to Lead · New Conversation Rating · New AI Summary · New Closed Conversation · New Company · New Conversation · New Ticket · New User · Tag Added to Conversation · Updated Company · Updated Contact · Updated Ticket · Tag Added to User · New Unsubscription

*Actions (16):* Add Note · Add Tag to Contact · Create Article · Create Conversation · Create Data Event · Create or Update Company · Create Ticket · Remove Tag From Contact · **Reply to Conversation** · **Send Incoming Message** · **Send Message to Contact** · Add/Remove Tag on Company · Create/Update Lead · Update Ticket · Create/Update User · Create User

*Searches (6):* Find Company · Find Conversation · Find Lead · Find Ticket · Find User · Retrieve a Conversation
*Search-or-create (2):* Find or Create Company · Find or Create Lead

**Crisp** `[FATO]` https://zapier.com/apps/crisp/integrations — 8 triggers / 8 actions / 2 searches:
*Triggers:* Edited Contact · Message Sent · Message Incoming · New Contact · New Conversation · Conversation Custom Data Updated · Conversation Segments Updated · Conversation Status Change
*Actions:* Add Segments to Conversation · Create/Update Contact · Create Conversation · Add a User Event · Send Note Message · **Send Operator Text Message** · **Send User Text Message** · Change Conversation State
*Searches:* Search for Conversation · Search for a Profile

**LiveChat** `[FATO]` https://zapier.com/apps/livechat/integrations — só triggers: Chat Changed (lista de tags mudou) · Finished Chat · New Chat · New Ticket · New Visitor in Queue. **Nenhuma action publicada.**

**Tidio** `[FATO]` https://zapier.com/apps/tidio/integrations — **um trigger só**: "Contact Sent From Bot" (requer o nó "Send to Zapier" no bot). Nenhuma action.

**JivoChat** `[FATO]` https://zapier.com/apps/jivochat/integrations — **um trigger**: "New Chat Finished". Nenhuma action.

**tawk.to** — tem app no Zapier (documentado em https://developer.tawk.to/zapier/) mas a URL `zapier.com/apps/tawkto/integrations` retorna **404** `[MEDIDO]` `curl -sIL`. A doc do tawk.to não lista triggers/actions nominalmente. `[NÃO VERIFICADO]` o catálogo exato.

**Freshchat** — `zapier.com/apps/freshchat/integrations` → **404** `[MEDIDO]`. `[NÃO VERIFICADO]`.

**Chatwoot** — `zapier.com/apps/chatwoot/integrations` → **404** `[MEDIDO]`. **Não há app oficial do Chatwoot no Zapier.**

### Make

Apps confirmados existentes (HTTP 200) `[MEDIDO]` `curl -sIL`: `apps.make.com/jivochat`, `apps.make.com/crisp`, `apps.make.com/intercom`. `[NÃO VERIFICADO]` o catálogo de módulos de cada um.

### n8n

`[FATO]` Não há nó **built-in** de Chatwoot no n8n. Existem **community nodes** publicados por terceiros: `@pixelinfinito/n8n-nodes-chatwoot` (https://github.com/pixelinfinito/n8n-nodes-chatwoot), `@fedcairo/n8n-nodes-chatwoot`, `munirajg-n8n-nodes-chatwoot`. Cobrem accounts, contacts, conversations, messages, inboxes, canned responses, **webhooks**, teams e labels.

`[INFERÊNCIA]` Para o mercado brasileiro isso é menos grave do que parece: o n8n self-hosted é o padrão de fato nas integrações que a operação SPX já faz, e community node instalável resolve. Já a ausência no **Zapier** e no **Make** fecha a porta para o cliente que não tem time técnico — e esse é justamente o cliente que o widget de site atrai.

---

## C.9 Integração nativa com CRM

| Fornecedor | Integrações CRM nativas | Direção | Frequência |
|---|---|---|---|
| **Intercom** | Salesforce, HubSpot, Pipedrive e dezenas via App Store | Bidirecional nos apps oficiais | `[NÃO VERIFICADO]` |
| **HubSpot** | É o CRM — a conversa é objeto de primeira classe do CRM | N/A | Tempo real |
| **Zendesk/Sunshine** | Marketplace + Zendesk Sell | `[NÃO VERIFICADO]` | `[NÃO VERIFICADO]` |
| **JivoChat** | Modelo "responda ao webhook e eu mostro no painel" — funciona com qualquer CRM que exponha um endpoint. O retorno preenche `contact_info`, `custom_data` (linhas título/valor no painel do agente) e `crm_link` | **Bidirecional e síncrono**, no momento do `chat_accepted` | Por evento |
| **Crisp** | Marketplace de plugins | `[NÃO VERIFICADO]` | — |
| **Tidio** | Integrações nativas com e-commerce (Shopify, WooCommerce) e CRMs via Zapier | `[NÃO VERIFICADO]` | — |
| **🟡 ChatSPX** | **LeadSquared apenas** (atrás da flag `crm_integration`) `[MEDIDO]` `config/integration/apps.yml:314-321`. Há stubs comentados para HubSpot e Zoho `[MEDIDO]` `app/jobs/crm/setup_job.rb:28-30`. Fora de CRM: Shopify, Linear, Notion, Slack, Dialogflow, Google Translate, Dyte, Meta Lead Ads, OpenAI `[MEDIDO]` `config/integration/apps.yml` | Saída (Chatwoot → CRM) apenas. Eventos: `contact.created`, `contact.updated`, `conversation.created`, `conversation.updated` `[MEDIDO]` `app/services/crm/base_processor_service.rb:17-29` | Por evento, via `HookJob` |

---

# D. O nosso estado (leitura apenas)

> Tudo nesta seção é `[MEDIDO]` — leitura direta do repositório em `HEAD ee87f5e799`, com arquivo:linha. Nenhuma alteração foi feita.

## D.10 Inventário dos webhooks de saída

### D.10.1 O catálogo — 12 eventos

`app/models/webhook.rb:32-34`:
```ruby
ALLOWED_WEBHOOK_EVENTS = %w[conversation_status_changed conversation_updated conversation_created contact_created contact_updated
                            message_created message_updated webwidget_triggered inbox_created inbox_updated
                            conversation_typing_on conversation_typing_off].freeze
```

| Evento | Onde é montado | Payload base | Extras |
|---|---|---|---|
| `conversation_created` | `app/listeners/webhook_listener.rb:18-23` | `conversation.webhook_data` | — |
| `conversation_updated` | `webhook_listener.rb:10-16` | `conversation.webhook_data` | `changed_attributes` |
| `conversation_status_changed` | `webhook_listener.rb:2-8` | `conversation.webhook_data` | `changed_attributes` |
| `message_created` | `webhook_listener.rb:25-42` | `message.webhook_data` | Só se `message.webhook_sendable?` |
| `message_updated` | `webhook_listener.rb:44-63` | `message.webhook_data` | `changed_attributes` |
| `contact_created` | `webhook_listener.rb:74-78` | `contact.webhook_data` | Só webhook de **conta** |
| `contact_updated` | `webhook_listener.rb:80-87` | `contact.webhook_data` | `changed_attributes`; abortado se `changed_attributes.blank?` |
| `inbox_created` | `webhook_listener.rb:89-94` | `Inbox::EventDataPresenter#push_data` | Só webhook de conta |
| `inbox_updated` | `webhook_listener.rb:96-104` | `Inbox::EventDataPresenter#push_data` | `changed_attributes` |
| `webwidget_triggered` | `webhook_listener.rb:65-72` | `contact_inbox.webhook_data` | `event_info` (idioma do widget, idioma do browser, dados do browser) |
| `conversation_typing_on` | `webhook_listener.rb:106-108` → `:116-128` | `{event, user, conversation, is_private}` | — |
| `conversation_typing_off` | `webhook_listener.rb:110-112` → `:116-128` | idem | — |

**Divergência doc × código:** a doc oficial (https://www.chatwoot.com/hc/user-guide/articles/1677693021-how-to-use-webhooks) documenta **8** eventos — não documenta `contact_created`, `contact_updated`, `inbox_created`, `inbox_updated`, que existem no código. `[MEDIDO]` comparação da lista da doc com `app/models/webhook.rb:32-34`.

### D.10.2 Estrutura real do payload

Montado em `app/models/message.rb:190-208`:
```ruby
def webhook_data
  data = {
    account: account.webhook_data,               # {id, name}                app/models/account.rb:205-210
    additional_attributes: additional_attributes,
    content_attributes: content_attributes,
    content_type: content_type,
    content: webhook_content,                    # MessageContentPresenter#webhook_content
    conversation: conversation.webhook_data,     # Conversations::EventDataPresenter#push_data
    created_at: created_at,
    id: id,
    inbox: inbox.webhook_data,                   # {id, name}                app/models/inbox.rb:181-186
    message_type: message_type,
    private: private,
    sender: sender.try(:webhook_data),
    source_id: source_id
  }
  data[:attachments] = attachments.map(&:push_event_data) if attachments.present?
  data
end
```

`conversation.webhook_data` = `Conversations::EventDataPresenter#push_data` (`app/presenters/conversations/event_data_presenter.rb:2-22`), que traz `additional_attributes`, `can_reply`, `channel`, `contact_inbox`, `id` (**é o `display_id`**, não o id global), `inbox_id`, `messages` (só a **última** mensagem de chat — linha 26-28), `labels`, `meta` (sender, assignee, assignee_type, team, **`hmac_verified`**), `status`, `custom_attributes`, `snoozed_until`, `unread_count`, `first_reply_created_at`, `priority`, `waiting_since`, e os timestamps (`agent_last_seen_at`, `contact_last_seen_at`, `last_activity_at`, `timestamp`, `created_at`, `updated_at`).

`contact.webhook_data` (`app/models/contact.rb:167-181`): `account`, `additional_attributes`, `avatar`, `custom_attributes`, `email`, `id`, `identifier`, `name`, `phone_number`, `thumbnail`, `blocked`.

`contact_inbox.webhook_data` (`app/models/contact_inbox.rb:43-52`): `id`, `contact`, `inbox`, `account`, `current_conversation`, `source_id`.

`user.webhook_data` (`app/models/user.rb:156-163`): `id`, `name`, `email`, `type: 'user'`.
`agent_bot.webhook_data` (`app/models/agent_bot.rb:69-75`): `id`, `name`, `type: 'agent_bot'`.

> Ponto positivo pouco notado: **`meta.hmac_verified` viaja no payload** (`event_data_presenter.rb:36`). O consumidor sabe se aquele contato foi identificado com HMAC ou é só um visitante anônimo que digitou um e-mail. Nenhum concorrente medido expõe isso tão explicitamente.

### D.10.3 Assinatura — o que temos é bom

`lib/webhooks/trigger.rb:44-53`:
```ruby
def request_headers(body)
  headers = { content_type: :json, accept: :json }
  headers['X-Chatwoot-Delivery'] = @delivery_id if @delivery_id.present?
  if @secret.present?
    ts = Time.now.to_i.to_s
    headers['X-Chatwoot-Timestamp'] = ts
    headers['X-Chatwoot-Signature'] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @secret, "#{ts}.#{body}")}"
  end
  headers
end
```

Exemplo concreto gerado agora `[MEDIDO]` (`ruby -e` com o mesmo algoritmo, segredo fictício):
```
Corpo:                {"event":"message_created","id":42,"content":"oi"}
X-Chatwoot-Timestamp: 1786000000
X-Chatwoot-Signature: sha256=55bf556de6a5c8ee614e733b061f32992efc042245d871ea8b22f45ddb3d0eac
```

O segredo: `has_secure_token :secret` + `encrypts :secret if Chatwoot.encryption_configured?` (`app/models/webhook.rb:24-25`). Introduzido pelo commit upstream `c218eff5ec` — *"feat: add per-webhook secret with backfill migration (#13573)"* — com migrations `20260218075101_add_secret_to_webhooks.rb` e `20260226084618_backfill_webhook_secrets.rb`. É upstream, não fork.

⚠️ **O segredo é devolvido em texto claro no `index`** (`app/views/api/v1/accounts/webhooks/_webhook.json.jbuilder:6`: `json.secret webhook.secret`). Ou seja, `GET /api/v1/accounts/{id}/webhooks` devolve todos os segredos. Só administradores conseguem (`app/policies/webhook_policy.rb:2-4`), e a auditoria enterprise exclui o campo (`enterprise/app/models/enterprise/audit/webhook.rb:5` — `except: [:secret]`), mas **não existe endpoint de rotação de segredo**: o único jeito de trocar é destruir e recriar o webhook.

### D.10.4 Retry — provado que não existe

`app/jobs/webhook_job.rb`:
```ruby
class WebhookJob < ApplicationJob
  queue_as :medium
  retry_on StandardError, wait: :polynomially_longer, attempts: 5   # linha 3
  discard_on ActiveJob::DeserializationError
  def perform(url, payload, webhook_type = :account_webhook, secret: nil, delivery_id: nil)
    Webhooks::Trigger.execute(url, payload, webhook_type, secret: secret, delivery_id: delivery_id)
  end
end
```

Parece que há 5 retentativas. **Não há.** `lib/webhooks/trigger.rb:16-24`:
```ruby
def execute
  perform_request
rescue RestClient::TooManyRequests, RestClient::InternalServerError => e
  raise if @webhook_type == :agent_bot_webhook
  handle_failure(e)
rescue StandardError => e
  handle_failure(e)
end
```
`handle_failure` (`:26-29`) chama `handle_error` e faz `Rails.logger.warn` — **não relança**. Logo o job termina com sucesso e o ActiveJob nunca reagenda.

**Prova executada agora** — script isolado (sem Rails, sem banco, sem rede) que carrega o arquivo REAL `lib/webhooks/trigger.rb` com stubs mínimos e força falhas:

```
$ ruby /tmp/.../scratchpad/trigger_probe.rb
account_webhook:   NAO levantou excecao  -> ActiveJob NAO reagenda (sem retry)
api_inbox_webhook: NAO levantou excecao  -> ActiveJob NAO reagenda (sem retry)
agent_bot_webhook: NAO levantou excecao  -> ActiveJob NAO reagenda (sem retry)
--- com HTTP 500 ---
account_webhook:   NAO levantou excecao  -> sem retry
api_inbox_webhook: NAO levantou excecao  -> sem retry
agent_bot_webhook: LEVANTOU RestClient::InternalServerError -> retry
```

Primeiro bloco: erro de conexão (`Errno::ECONNREFUSED`). Segundo: HTTP 500.

**Conclusões precisas:**
- Webhook de conta e de inbox: **zero retentativa, em qualquer tipo de falha**.
- Webhook de agent bot: retenta **só** em `429` e `500` (`AgentBots::WebhookJob`, `app/jobs/agent_bots/webhook_job.rb:3`, 3 tentativas com `wait: 3.seconds`). **Endpoint fora do ar, DNS quebrado, timeout, 502 e 503 NÃO retentam** — o `rescue StandardError` genérico pega antes.

Timeout: `lib/webhooks/trigger.rb:108-113` — `GlobalConfig.get_value('WEBHOOK_TIMEOUT')`, default **5 s**.

### D.10.5 Filtro por inbox — letra morta

Três fatos que se contradizem:
1. `app/models/webhook.rb:30` — `enum webhook_type: { account_type: 0, inbox_type: 1 }`, com `belongs_to :inbox, optional: true` (`:22`) e coluna `inbox_id`.
2. `app/controllers/api/v1/accounts/webhooks_controller.rb:26` — o controller **aceita** `:inbox_id` no `permit`, mas **nunca** grava `webhook_type`.
3. `app/listeners/webhook_listener.rb:130-138` — a entrega itera `account.webhooks.account_type` e filtra **só** por `subscriptions.include?(payload[:event])`. Nenhuma checagem de inbox.

`grep -rn "webhook_type" app/ enterprise/ db/ lib/` `[MEDIDO]`: as únicas ocorrências fora do model e dos jobs são o `db/schema.rb:2006` e specs. **Nada no código-fonte jamais atribui `inbox_type`.** O front (`app/javascript/dashboard/routes/dashboard/settings/integrations/Webhooks/WebhookForm.vue`) não tem seletor de inbox `[MEDIDO]` `grep -n "inbox"` → zero ocorrências.

Resultado prático: **se você tem 4 caixas de entrada (widget do site, WhatsApp, e-mail, Instagram), um webhook de `message_created` recebe as 4.** Sem filtro. O consumidor tem que descartar 3/4 do tráfego pelo `inbox.id` do payload.

### D.10.6 Agent bots — o caminho paralelo

`app/listeners/agent_bot_listener.rb` publica **5 eventos**, e o conjunto é **diferente** do de webhook de conta:

| Evento | Linha | Existe também no webhook de conta? |
|---|---|---|
| `conversation_resolved` | `:2-8` | **NÃO** |
| `conversation_opened` | `:10-16` | **NÃO** |
| `message_created` | `:18-25` | Sim |
| `message_updated` | `:27-34` | Sim |
| `webwidget_triggered` | `:36-43` | Sim |

`[INFERÊNCIA]` Isso é um acidente histórico, não um desenho: `conversation_resolved` é o evento mais pedido por qualquer integração de CRM/NPS/pós-venda, e ele **existe no barramento** (`lib/events/types.rb:22-23`) mas só é entregue a agent bots.

Quais bots recebem (`agent_bot_listener.rb:47-59`): o `assignee_agent_bot` da conversa **e** o agent bot ativo da inbox (`inbox.agent_bot_inbox&.active?`), deduplicados. Bots do tipo `captain` nunca disparam webhook (`:68` — `return unless agent_bot.webhook?`), e o model proíbe `outgoing_url` em bots captain (`app/models/agent_bot.rb:49`).

Degradação em falha (`lib/webhooks/trigger.rb:67-79`): se o bot falha e a conversa está `pending`, ela vira `open` e é postada uma mensagem de atividade (`conversations.activity.agent_bot.error_moved_to_open`) — a não ser que `account.keep_pending_on_bot_failure` esteja ligado. **Isso é o mesmo desenho do JivoChat Bot API** ("If not, the chat is transferred to the agent") e é um acerto.

### D.10.7 Webhooks disparados por automação, macro e flow

Três caminhos adicionais, todos usando `WebhookJob` **sem segredo e sem delivery id**:

| Origem | Arquivo:linha | Nome do evento no payload |
|---|---|---|
| Regra de automação | `app/services/automation_rules/action_service.rb:38-41` | `"automation_event.#{@rule.event_name}"` |
| Macro | `app/services/macros/execution_service.rb:72-75` | `"macro.executed"` |
| Flow (motor ChatSPX) | `app/services/flows/action_service.rb:132-135` | `webhook_event_name` (derivado de `flow.trigger_config['event_name']`) |

Payload nos três: `@conversation.webhook_data.merge(event: ...)`.

⚠️ Consequência: um endpoint que **valida assinatura** vai **rejeitar** os webhooks vindos de automação/macro/flow, porque eles chegam sem `X-Chatwoot-Signature`. Quem integra tem que aceitar requisição não assinada nesse endpoint — o que anula a proteção. `[INFERÊNCIA]`

### D.10.8 O que NÃO existe do nosso lado

`[MEDIDO]` por busca no repositório e na UI:

- ❌ **Log de entregas.** `app/javascript/dashboard/routes/dashboard/settings/integrations/Webhooks/` tem `Index.vue`, `NewWebHook.vue`, `EditWebHook.vue`, `WebhookForm.vue`, `WebhookRow.vue`. Nenhuma tela de histórico. `app/javascript/dashboard/i18n/locale/en/webhooks.json` inteiro é `{"WEBHOOKS_SETTINGS":{"HEADER":"Webhook Settings"}}`.
- ❌ **Replay manual.** Sem endpoint, sem job, sem UI.
- ❌ **Estatística de erro / taxa de falha.** Nada.
- ❌ **Ping / teste de endpoint.** O Intercom valida a URL com um `HEAD` no cadastro; nós não validamos nada além do formato (`app/models/webhook.rb:28`).
- ❌ **Desativação automática de endpoint morto.** Um endpoint que responde 500 há 3 meses continua recebendo POST para sempre.
- ❌ **Rotação de segredo.**
- ❌ **Batching.** Um POST por evento. HubSpot manda até 100 por requisição; Sunshine manda array.

---

## D.11 Inventário da API pública

### D.11.1 Autenticação

`app/controllers/api/base_controller.rb:1-12`:
```ruby
class Api::BaseController < ApplicationController
  include AccessTokenAuthHelper
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?
  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
  end
```

`AccessToken` é polimórfico (`app/models/concerns/access_tokenable.rb`) e o dono pode ser `User` ou `AgentBot` (`app/controllers/concerns/access_token_auth_helper.rb:22-27`). **Sem escopos, sem expiração, sem OAuth de terceiros.**

### D.11.2 Superfície de escrita relevante (Application API)

Todas em `/api/v1/accounts/{account_id}/...`, com `api_access_token`:

| Ação | Rota (config/routes.rb) |
|---|---|
| Criar/atualizar contato | `resources :contacts` + `contact_inboxes` (`:333-336`) |
| Criar conversa | `resources :conversations, only: [..., :create, ...]` (`:212`) |
| Enviar mensagem (agente ou bot) | `conversations/{id}/messages` (`:223`) — `Messages::MessageBuilder` em `app/controllers/api/v1/accounts/conversations/messages_controller.rb:45-56` |
| Nota privada | mesma rota, `private: true` |
| Etiquetar | `conversations/{id}/labels` (`:335`) |
| Atribuir | `conversations/{id}/assignments` (`:242`) |
| Resolver / snooze / reabrir | `conversations/{id}/toggle_status` |
| Prioridade | `toggle_priority` |
| Atributos customizados | `custom_attributes` |
| Typing | `toggle_typing_status` |
| Encaminhar mensagem | `messages/{id}/forward` (`:344`) |
| Anexar reação / fixar / favoritar | `:228-240` (extensões do fork) |
| Webhooks CRUD | `resources :webhooks, only: [:index, :create, :update, :destroy]` (`:484`) |
| Agent bots CRUD | `resources :agent_bots` |
| Integração hooks | `integrations/hooks` + `POST :process_event` (`:487-491`) |

### D.11.3 Canal API (o nosso "conversational API")

Duas metades:

**(a) Saída** — `Channel::Api` com `webhook_url` (`app/models/channel/api.rb:21-30`): cada `message_created`/`message_updated` de uma inbox do tipo API é POSTado para `channel.webhook_url` (`app/listeners/webhook_listener.rb:140-146`), **sem assinatura**, com `X-Chatwoot-Delivery`. Se falhar, a mensagem é marcada `failed` via `Messages::StatusUpdateService` (`lib/webhooks/trigger.rb:90-92`).

**(b) Entrada** — "Client APIs" em `config/routes.rb:724-750`:
```
POST   /public/api/v1/inboxes/{inbox_identifier}/contacts
GET/PATCH /public/api/v1/inboxes/{inbox_identifier}/contacts/{contact_identifier}
GET/POST  .../conversations
GET       .../conversations/{id}
POST      .../conversations/{id}/toggle_status
POST      .../conversations/{id}/toggle_typing
POST      .../conversations/{id}/update_last_seen
GET/POST/PATCH .../conversations/{id}/messages
```
Autenticação: **o `inbox_identifier` na URL é a credencial** (`has_secure_token :identifier`, `app/models/channel/api.rb:27`; resolvido em `app/controllers/public/api/v1/inboxes_controller.rb:15`). Verificação de identidade opcional via HMAC (`hmac_token`, `hmac_mandatory`, `before_action :process_hmac` em `app/controllers/public/api/v1/inboxes/contacts_controller.rb:3`).

`[INFERÊNCIA]` Em capacidade, isso empata com o Custom Channels do HubSpot e com o Chat API do Jivo. O que falta em relação ao Jivo é cosmético mas importante: **endpoint de status do canal** (o Jivo tem `GET .../status` → `0`/`1`), **contrato de erro que o agente vê no painel**, e o par `typein`/`typeout` bidirecional documentado.

### D.11.4 Agent bots — a jaula

`app/controllers/concerns/access_token_auth_helper.rb:2-6`:
```ruby
BOT_ACCESSIBLE_ENDPOINTS = {
  'api/v1/accounts/conversations' => %w[toggle_status toggle_typing_status toggle_priority create update custom_attributes],
  'api/v1/accounts/conversations/messages' => ['create'],
  'api/v1/accounts/conversations/assignments' => ['create']
}.freeze
```

Um agent bot com token pode: mudar status, digitar, mudar prioridade, criar/atualizar conversa, mexer em atributos customizados, criar mensagem, criar atribuição. **Só isso.** Não pode ler mensagens (`messages#index` não está na lista), não pode etiquetar, não pode ler contatos.

`[INFERÊNCIA]` Como o bot **recebe** a mensagem pelo webhook (`agent_bot_listener.rb`), não precisa ler — mas isso significa que **um bot que perdeu um webhook não tem como se recuperar**: ele não pode consultar o histórico. Junte isso com "webhook de agent bot só retenta em 429/500" e você tem um bot que fica surdo permanentemente se o endpoint dele piscar num timeout. Esse é o pior par de gaps do inventário.

**Handoff bot → humano:** `assignments#create` está liberado, então o bot pode atribuir a um agente. Não há evento próprio de handoff, nem estado `pending`→`open` explícito por API (o bot faria `toggle_status`). Comparado ao `passControl`/`offerControl` do Sunshine ou ao `INVITE_AGENT` do Jivo, é funcional mas mudo — nenhum sistema externo consegue observar "o bot passou o bastão".

### D.11.5 Dashboard Apps

`app/models/dashboard_app.rb` — array de `{type: 'frame', url: 'https?://...'}`, validado por JSON schema (`:29-41`). O painel embute um iframe e conversa por `postMessage`:

`app/javascript/dashboard/components/widgets/DashboardApp/Frame.vue`:
- linha `:64` — o app dentro do iframe manda `'chatwoot-dashboard-app:fetch-info'`
- linhas `:84-89` — o Chatwoot responde com `postMessage(JSON.stringify({event: 'appContext', data: {conversation, contact, currentAgent}}), targetOrigin)`
- `targetOrigin` é derivado da URL configurada (`:71-78`), não é `'*'` — está correto do ponto de vista de segurança.

`[INFERÊNCIA]` É o análogo do `custom_data` do JivoChat, mas invertido: no Jivo o **CRM responde ao webhook** e o Chatwoot renderiza nativamente; aqui o **CRM tem que construir uma página** e nós a embutimos. O nosso dá mais liberdade e exige muito mais trabalho do integrador. Para o cliente PME brasileiro, o modelo do Jivo ganha.

### D.11.6 Webhook de ENTRADA do motor Flow — o que temos de melhor

`app/controllers/webhooks/flows_controller.rb` + `config/routes.rb:789` (`POST /webhooks/flows/:token`).

Defesas, na ordem em que rodam (`:48-58`):
1. **Cap de payload** — `FLOW_WEBHOOK_MAX_BYTES`, default **65 536 bytes** → `413` (`:43`, `:49`)
2. **Rate-limit por token** — `FLOW_WEBHOOK_RATE_LIMIT` default **60** requisições em `FLOW_WEBHOOK_RATE_PERIOD` default **60 s**, em Redis (`:44-45`, `:50`), somado ao Rack::Attack por IP
3. **Token → flow** — `SecureRandom.hex(24)` (192 bits), lookup + `secure_compare`; token desconhecido **ou** flow inativo → **404 genérico idêntico** (anti-enumeração) (`:52-53`)
4. **Engine ativo** — conta com motor desligado → `200` no-op (`:54`)
5. **Dedupe** — `Idempotency-Key` via header (`Idempotency-Key` ou `X-Idempotency-Key`) ou corpo, janela `FLOW_WEBHOOK_DEDUPE_WINDOW` default **600 s** → `200 duplicate` (`:46`, `:55`)
6. **Alvo** — resolve conversa existente por `conversation_id` (o `display_id`, escopo da conta); sem alvo → `200` no-op
7. **Payload é só dado** — nunca executado nem renderizado; entra como dado de comparação nas condições; o Liquid das ações expõe só `contact`/`conversation`/`account`, nunca o payload

Execução pesada vai para `Flows::WebhookTriggerJob` (`app/jobs/flows/webhook_trigger_job.rb`), que **re-valida** flow ativo, engine ligado e conversa existente antes de rodar (`:15-22`).

`[INFERÊNCIA]` Esse endpoint tem um contrato de confiabilidade **melhor** que o webhook de saída do próprio Chatwoot (tem idempotência de verdade, rate-limit e cap). O padrão já existe na casa — só não foi aplicado ao caminho de saída.

---

## D.12 O que o Chatwoot/ChatSPX já faz bem (seja justo)

1. **Assinatura HMAC-SHA256 com timestamp no material assinado.** Está no grupo mais forte, ao lado de Zendesk, HubSpot v3, Tidio e Crisp. A doc oficial inclusive publica o verificador em Ruby, Python, Node e Go.
2. **`meta.hmac_verified` no payload.** Ninguém mais expõe "esse contato foi identificado criptograficamente" tão explicitamente. Para quem integra com backoffice, é ouro: dá pra decidir se confia no e-mail que veio.
3. **Degradação de bot para humano.** Bot falhou e a conversa está `pending` → vira `open` + mensagem de atividade, com override por conta (`keep_pending_on_bot_failure`). Mesmo desenho do JivoChat, e mais configurável.
4. **Canal API completo nos dois sentidos**, com HMAC opcional na identificação do contato. Comparável ao Custom Channels do HubSpot, que é do ano passado.
5. **Payload rico.** O `message_created` do Chatwoot carrega conta, inbox, conversa inteira (com labels, prioridade, assignee, team, unread_count, waiting_since) e remetente numa tacada. O `contact.propertyChange` do HubSpot carrega `objectId` e `propertyValue` — só. Quem consome nosso webhook raramente precisa de uma segunda chamada.
6. **Webhook de ENTRADA do motor Flow** com cap, rate-limit, dedupe e anti-enumeração — melhor que o inbound de vários concorrentes.
7. **Auditoria enterprise do webhook com o segredo excluído** (`enterprise/app/models/enterprise/audit/webhook.rb:5`).
8. **Escolha por evento** funciona e é granular (12 eventos selecionáveis por webhook).
9. **Restrição de agent bot por endpoint** (`BOT_ACCESSIBLE_ENDPOINTS`) é uma trava de segurança que a maioria dos concorrentes não tem — bot com token vazado não vira acesso total à conta.
10. **`X-Chatwoot-Delivery`** existe. A forma está certa; falta o comportamento (§D.10.4).

---

## D.13 Mensagem proativa para visitante identificado — dá ou não dá?

**Resposta: DÁ. Sem gambiarra, mas sem endpoint de conveniência — são 3 chamadas.**

O caminho medido `[MEDIDO]` (rotas e código citados):

**Passo 0 — pré-requisito no widget.** O visitante precisa ter sido identificado com `setUser` + `identifier_hash` (HMAC), o que cria/liga o `Contact` e marca `contact_inbox.hmac_verified = true` (`app/builders/contact_inbox_with_contact_builder.rb:6,46`). Sem isso, você não tem como achar a pessoa a partir do seu backend.

**Passo 1 — achar o contato.** `GET /api/v1/accounts/{account_id}/contacts/search?q={identifier|email}` (`config/routes.rb:317-321`) — o `identifier` é o que você mandou no `setUser`.

**Passo 2 — achar/criar a conversa.** Ler `contact_inboxes` do contato para pegar o `source_id` da inbox do widget e, se não houver conversa aberta, `POST /api/v1/accounts/{account_id}/conversations` com `source_id`, `inbox_id`, `contact_id` (`config/routes.rb:212`; `app/controllers/api/v1/accounts/conversations_controller.rb:60`).

**Passo 3 — mandar a mensagem.** `POST /api/v1/accounts/{account_id}/conversations/{display_id}/messages` com `content` e `message_type: outgoing` (`config/routes.rb:223`; `messages_controller.rb:45-56` → `Messages::MessageBuilder`).

O visitante recebe em tempo real via ActionCable se o widget estiver aberto; se não estiver, aparece como não lida quando voltar, e há continuidade por e-mail se `continuity_via_email` estiver ligado no canal (`app/models/channel/web_widget.rb:35`).

**O que falta em relação ao Intercom:**

| | Intercom | ChatSPX |
|---|---|---|
| Chamadas | **1** (`POST /messages`) | **3** |
| Endereçar por identificador externo | Sim (`to: {type: "user", id}`) | Não — tem que resolver contato → contact_inbox → conversa |
| Decidir se abre conversa na inbox | Sim (`create_conversation_without_contact_reply`) | Não — sempre abre |
| Remetente configurável | Sim (`from: {type: "admin", id}`) | Sim (o token define o autor) |

**O que existe e não resolve:** as **Campanhas** do Chatwoot (`app/models/campaign.rb`). O tipo é **forçado pelo canal**, não escolhido: `ensure_correct_campaign_attributes` (`:106-116`) atribui `campaign_type = 'one_off'` para Twilio SMS / Sms / Whatsapp e `campaign_type = 'ongoing'` com `scheduled_at = nil` para **todo** o resto — inclusive `Website`. E `execute_campaign` (`:80-93`) só tem `case` para `'Twilio SMS'`, `'Sms'` e `'Whatsapp'`; **canal Website não tem ramo de execução**. Campanha de widget é, por construção, disparada por comportamento do visitante no site (`trigger_rules['url']`, `:118-123`), nunca por decisão do backend do cliente. Não há caminho de campanha para "meu backend decidiu agora que essa pessoa precisa saber X".

---

# O QUE FALTA NO CHATSPX — e o que isso significa para o redesenho

> Recomendações. Sem código de implementação, como pedido. Prioridade por impacto sobre o cliente que o widget de site atrai (PME brasileira com ERP/CRM próprio ou de prateleira).

## Trava 1 — Retry no webhook de saída · **crítico**

Somos o único fornecedor medido sem retry no caminho principal. Um deploy do ERP do cliente, um pico de latência, uma janela de manutenção de 30 segundos — e o evento some para sempre, sem log, sem alerta, sem replay. O cliente descobre uma semana depois que faltam pedidos no CRM.

**O que fazer:** deixar a exceção subir para o ActiveJob no caminho de conta e de inbox (o `retry_on` já está declarado e é a política certa), e tratar como não-recuperáveis os códigos que a Sunshine já enumerou (`400`, `401`, `403`, `404`, `406`) para não martelar endpoint que nunca vai aceitar. Manter o `handle_error` que marca mensagem como `failed` — mas só depois da última tentativa.

**Referência de janela:** Tidio 9 tentativas até ~4h45; HubSpot 10 em 24 h; tawk.to até 12 h. Uma escada tipo Tidio é a mais adequada ao nosso perfil de cliente.

## Trava 2 — `X-Chatwoot-Delivery` estável entre retentativas · **crítico, e acompanha a trava 1**

Retry sem idempotência gera pedido duplicado no ERP do cliente — pior do que não ter retry. O `delivery_id` precisa ser gerado **uma vez por evento** e **repetido em todas as retentativas**, exatamente como o `X-Hook-Event-Id` do tawk.to ("The event Id will remain the same in case of retries"). Hoje é gerado no listener a cada `perform_later` (`webhook_listener.rb:136`) e não sobrevive a nada, porque não há retentativa para sobreviver.

E precisa existir no caminho de agent bot, que é justamente onde HÁ retry hoje e onde ele está ausente.

## Trava 3 — Assinar os outros três caminhos · **alto**

Webhook de inbox (canal API), de agent bot e de automação/macro/flow saem sem assinatura. Um endpoint que valida assinatura é obrigado a abrir uma exceção — e a exceção vira o buraco. Precisa haver segredo por canal API, segredo por agent bot, e o webhook de ação de automação precisa herdar o segredo de um webhook cadastrado (ou ter o seu).

## Trava 4 — Filtro por inbox de verdade · **alto**

O cliente com WhatsApp + widget + e-mail recebe hoje 3× o tráfego que pediu. A infraestrutura já existe (coluna, enum, `belongs_to`); falta gravar `webhook_type` e filtrar na entrega, e expor o seletor no formulário. Enquanto isso não existe, remover `inbox_id` do `permit` seria mais honesto que aceitar um parâmetro que não faz nada.

Junto disso, revisar a unicidade de URL por conta (`app/models/webhook.rb:28`): ela impede a configuração legítima "mesma URL, dois conjuntos de eventos, duas inboxes".

## Trava 5 — `conversation_resolved` (e amigos) no webhook de conta · **alto**

O evento existe no barramento e é entregue a agent bots, mas não a webhooks de conta. É o evento mais pedido por integração de CRM, NPS e pós-venda. Junto dele, a lista curta do que o mercado tem e nós não:

| Evento que falta | Quem tem |
|---|---|
| `conversation_resolved` / `conversation_opened` | Tidio (`conversation.solved_by_*`), Freshchat (`conversation_resolution`/`_reopen`), Intercom (`conversation.admin.closed`), tawk.to (`chat:end`) |
| CSAT respondido | Tidio (`customer_satisfaction.rated`), Intercom (`conversation.rating.added`) |
| Etiqueta aplicada/removida | Intercom (`conversation_part.tag.created`), LiveChat (`thread_tagged`/`thread_untagged`) |
| Atribuição mudada | Freshchat (`conversation_assignment`), Intercom (`conversation.admin.assigned`) |
| Mensagem entregue / falhou entrega | Sunshine (`conversation:message:delivery:*`) |
| Transcript da conversa completo | tawk.to (`chat:transcript_created`) |
| Resposta a menu interativo / postback | Crisp (`type: picker`), LiveChat (`incoming_rich_message_postback`), Sunshine (`conversation:postback`) |

`conversation_resolved` e CSAT são os dois que mudam a venda. `chat:transcript_created` é o que economiza trabalho de quem integra.

## Trava 6 — Observabilidade: log de entrega, taxa de erro, replay · **alto**

Todo fornecedor sério tem: Zendesk (activity log de 7 dias, filtrável por `filter[status]=failed`), Tidio (aba Logs + taxa de erro dos últimos 7 dias), Intercom (banner de subscription suspensa + botão "Set live"), Crisp (headers de tentativa).

Nós não temos nada — nem tela, nem tabela, nem endpoint. Quando o cliente reclama "não chegou", a única ferramenta é `grep` no log do Sidekiq. Isso é o que mais custa suporte no dia a dia.

Mínimo viável: tabela de entregas (evento, url, status HTTP, tentativa, timestamp, delivery_id), retenção curta (7 dias basta, é o padrão do mercado), tela com filtro por status, e botão de reenviar.

## Trava 7 — Rotação de segredo e ping de validação · **médio**

Rotação: hoje o único caminho é destruir e recriar o webhook, o que perde histórico e gera janela de indisponibilidade. O Tidio resolve elegantemente aceitando **múltiplos `s=` no header** durante a transição — dois segredos válidos ao mesmo tempo.

Ping: o Intercom exige que a URL responda a um `HEAD` antes de aceitar o cadastro. Nós aceitamos qualquer URL sintaticamente válida, e o cliente só descobre o erro de digitação quando nada chega.

## Trava 8 — Mensagem proativa em uma chamada · **médio-alto (é venda, não é bug)**

`POST /api/v1/accounts/{id}/proactive_messages` com `{identifier | email | contact_id, inbox_id, content, create_conversation: true|false}`, resolvendo contato → contact_inbox → conversa internamente. É açúcar sobre o que já existe, mas é exatamente o que o integrador PME consegue implementar sem ler o modelo de dados inteiro. É o `POST /messages` do Intercom.

## Trava 9 — Agent bot precisa poder ler · **médio**

Hoje, um bot que perde um webhook fica surdo — não pode consultar `messages#index`. Combinado com "retry só em 429/500", basta um timeout para o bot perder o fio da conversa em definitivo. Liberar leitura de mensagens da própria conversa para agent bots (e `labels#index`) fecha esse buraco.

Junto: **eventos de handoff observáveis**. Hoje "o bot passou pro humano" não gera evento nenhum. O Sunshine tem `switchboard:passControl` e `switchboard:offerControl` com evento de sucesso E de falha; o Jivo tem `INVITE_AGENT`. Ter um `conversation_bot_handoff` no catálogo permite medir taxa de contenção da IA sem gambiarra.

## Trava 10 — Enriquecimento síncrono no `chat_accepted` · **médio, alto valor percebido**

O padrão do JivoChat: o chat POSTa no CRM quando o agente aceita a conversa, e **a resposta do CRM** vira `contact_info` (preenche nome/telefone/e-mail no painel), `custom_data` (linhas título/valor: saldo, plano, último pedido) e `crm_link` (botão para o cadastro). Sem iframe, sem página nova, sem front do integrador.

O nosso equivalente hoje é o Dashboard App em iframe, que exige que o cliente construa e hospede uma página. Para PME, é o dobro de trabalho para o mesmo resultado.

## Trava 11 — `utm_json` e contexto de origem parseados · **baixo, mas barato**

O Jivo entrega `utm_json: {source, campaign, content, medium, term}` pronto no payload. Nós entregamos `additional_attributes` bruto — o integrador garimpa. É uma normalização de campo, não uma feature.

## Trava 12 — Presença no Zapier e no Make · **estratégico, fora do escopo técnico**

`zapier.com/apps/chatwoot/integrations` → 404 `[MEDIDO]`. Intercom tem 18 triggers e 16 actions publicados; Crisp tem 8 e 8; até o LiveChat e o Jivo têm ao menos um trigger. Sem Zapier, o cliente sem time técnico não integra — e é justamente esse cliente que o widget de site converte melhor.

Um app de Zapier com 6 triggers (`conversation_created`, `conversation_resolved`, `message_created`, `contact_created`, `csat_rated`, `webwidget_triggered`) e 6 actions (criar contato, criar conversa, enviar mensagem, etiquetar, atribuir, resolver) cobriria 90% dos casos e é construível sobre a API que já existe.

---

## Ordem sugerida de ataque

| Ordem | Item | Por quê primeiro |
|---|---|---|
| 1 | Trava 1 + Trava 2 juntas (retry + delivery_id estável) | Não se faz uma sem a outra. É a diferença entre "webhook confiável" e "webhook que às vezes funciona". |
| 2 | Trava 6 (log de entrega + replay) | Corta o custo de suporte imediatamente e é o que torna a trava 1 auditável. |
| 3 | Trava 5 (`conversation_resolved` + CSAT + etiqueta) | Desbloqueia integração de CRM e pós-venda; puro ganho de catálogo. |
| 4 | Trava 3 (assinar os outros caminhos) | Fecha o buraco que a trava 1 vai expor mais. |
| 5 | Trava 4 (filtro por inbox) | Reduz tráfego e ruído; a infraestrutura já existe. |
| 6 | Trava 8 (mensagem proativa em 1 chamada) | Venda. Curto e vistoso. |
| 7 | Trava 9 (agent bot lê + evento de handoff) | Habilita métrica de contenção da IA. |
| 8 | Trava 10 (enriquecimento síncrono) | Diferencial de percepção contra Jivo/RD/Leadster no mercado BR. |
| 9 | Trava 7, 11, 12 | Acabamento e distribuição. |

---

## Anexo — fontes primárias consultadas

Todas verificadas em 12/08/2026. Códigos HTTP obtidos com `curl -sIL -o /dev/null -w "%{http_code}"`.

**Intercom**
- https://developers.intercom.com/docs/references/webhooks/webhook-models (catálogo de topics)
- https://developers.intercom.com/docs/references/webhooks/webhook-models.md §"Signed notifications" (X-Hub-Signature, SHA-1 HMAC — **fonte primária da assinatura**)
- https://developers.intercom.com/docs/webhooks.md (envelope + FAQ)
- https://developers.intercom.com/docs/webhooks/setting-up-webhooks.md (configuração, HEAD de validação)
- https://developers.intercom.com/docs/webhooks/webhook-notifications.md (pausa/suspensão, rate limit, ordem, duplicidade, throttling)
- https://developers.intercom.com/docs/references/rest-api/api.intercom.io/messages/createmessage.md (mensagem proativa)
- https://developers.intercom.com/docs/references/rest-api/api.intercom.io/conversations/createconversation.md
- https://developers.intercom.com/docs/references/rest-api/errors/rate-limiting.md

**Zendesk / Sunshine Conversations**
- https://developer.zendesk.com/documentation/webhooks/
- https://developer.zendesk.com/documentation/webhooks/verifying/ (assinatura)
- https://developer.zendesk.com/documentation/webhooks/creating-and-monitoring-webhooks/ (retry, timeout, circuit breaker, activity log)
- https://developer.zendesk.com/api-reference/webhooks/event-types/ → **HTTP 403**, não acessível
- https://raw.githubusercontent.com/zendesk/sunshine-conversations-api-spec/master/openapi.yaml (triggers, retry, X-API-Key, switchboard, payloads)

**HubSpot**
- https://developers.hubspot.com/docs/api-reference/legacy/webhooks/guide.md (subscription types, payload, retries, limites)
- https://developers.hubspot.com/docs/apps/legacy-apps/authentication/validating-requests (assinaturas v1/v2/v3)
- https://developers.hubspot.com/docs/apps/developer-platform/add-features/configure-webhooks.md
- https://developers.hubspot.com/docs/api-reference/latest/conversations/custom-channels/guide.md
- https://developers.hubspot.com/docs/llms.txt (índice)

**Tidio**
- https://developers.tidio.com/llms.txt (índice de endpoints)
- https://developers.tidio.com/docs/webhooks-structure.md
- https://developers.tidio.com/docs/webhooks-signature-verification.md
- https://developers.tidio.com/docs/webhooks-delivering.md (retries, timeout, ordem, duplicidade, anti-loop)
- https://developers.tidio.com/docs/openapi-rate-limiting.md
- https://developers.tidio.com/reference/events.md (15 tópicos + payloads)

**Crisp**
- https://docs.crisp.chat/references/web-hooks/v1/ (entrega, origens, assinatura, ~60 namespaces, payloads)
- https://docs.crisp.chat/references/rest-api/v1/ (Send A Message In Conversation e demais)

**LiveChat / Text**
- https://platform.text.com/docs/management/webhooks (catálogo de ações + payloads)
- https://platform.text.com/docs/management/configuration-api (register_webhook, filtros, limite de 3 por action)
- https://platform.text.com/docs/messaging/agent-chat-api (send_event, transfer_chat, start_chat…)
- https://platform.text.com/docs/getting-started/livechat-apps/webhook-apps/ (timeout ~10 s, 3 retries)

**Freshchat**
- https://developers.freshchat.com/api/ (REST v2, OAuth, outbound-messages)
- https://crmsupport.freshworks.com/support/solutions/articles/50000004461-freshchat-webhooks-payload-structure-and-authentication (4 eventos, payloads, X-Freshchat-Signature RSA)

**tawk.to**
- https://developer.tawk.to/webhooks/ (4 eventos, retry 12 h, timeout 30 s, X-Tawk-Signature, X-Hook-Event-Id, payloads)
- https://developer.tawk.to/zapier/

**JivoChat**
- https://www.jivochat.com/docs/webhooks/ (eventos + payloads)
- https://www.jivochat.com/help/api/webhooks-api.html (Chat API, retry 3×3 s, multimídia)
- https://www.jivochat.com/help/api/api-crm.html (integração CRM, resposta síncrona)
- https://www.jivochat.com/docs/bot/ (Bot API, INVITE_AGENT, timeout 3 s/2 retries)

**Zapier / Make**
- https://zapier.com/apps/intercom/integrations · /crisp/ · /livechat/ · /tidio/ · /jivochat/
- 404 verificados: /tawkto/, /freshchat/, /chatwoot/
- https://apps.make.com/jivochat · /crisp · /intercom (200, catálogo não verificado)

**n8n**
- https://github.com/pixelinfinito/n8n-nodes-chatwoot (community node)

**Chatwoot (documentação oficial)**
- https://www.chatwoot.com/hc/user-guide/articles/1677693021-how-to-use-webhooks (8 eventos documentados, assinatura, verificadores em 4 linguagens)
- https://developers.chatwoot.com/api-reference/webhooks/list-all-webhooks

**Chatwoot/ChatSPX (código, HEAD `ee87f5e799`)**
`lib/webhooks/trigger.rb` · `app/jobs/webhook_job.rb` · `app/jobs/agent_bots/webhook_job.rb` · `app/listeners/webhook_listener.rb` · `app/listeners/agent_bot_listener.rb` · `app/models/webhook.rb` · `app/models/agent_bot.rb` · `app/models/channel/api.rb` · `app/models/message.rb` · `app/models/contact.rb` · `app/models/contact_inbox.rb` · `app/models/inbox.rb` · `app/models/account.rb` · `app/models/user.rb` · `app/models/campaign.rb` · `app/models/dashboard_app.rb` · `app/presenters/conversations/event_data_presenter.rb` · `app/controllers/api/base_controller.rb` · `app/controllers/concerns/access_token_auth_helper.rb` · `app/controllers/api/v1/accounts/webhooks_controller.rb` · `app/controllers/api/v1/accounts/conversations/messages_controller.rb` · `app/controllers/api/v1/widget/events_controller.rb` · `app/controllers/public/api/v1/inboxes_controller.rb` · `app/controllers/public/api/v1/inboxes/contacts_controller.rb` · `app/controllers/webhooks/flows_controller.rb` · `app/jobs/flows/webhook_trigger_job.rb` · `app/services/automation_rules/action_service.rb` · `app/services/macros/execution_service.rb` · `app/services/flows/action_service.rb` · `app/services/crm/base_processor_service.rb` · `app/policies/webhook_policy.rb` · `app/views/api/v1/accounts/webhooks/_webhook.json.jbuilder` · `app/javascript/dashboard/components/widgets/DashboardApp/Frame.vue` · `config/routes.rb` · `config/integration/apps.yml` · `lib/events/types.rb` · `enterprise/app/models/enterprise/audit/webhook.rb`
