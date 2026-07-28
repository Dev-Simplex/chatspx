# W1 — Cadeia de ingestão: quem monta "👥 Nome (LID@lid)" e "(GROUP)"

> Worker: W1 · Data: 2026-07-27 · VM: 192.168.8.232 (homologação) · Branch: `homologacao`
> Escopo: SOMENTE PESQUISA. Nenhum arquivo fora de `plano/pesquisa-grupos-waha/` foi tocado.
> Banco: apenas `SELECT` (toda sessão psql abriu com `SET default_transaction_read_only = on`).
> WAHA: apenas `GET` (`/api/version`, `/api/sessions`, `/api/apps`).

---

## Resumo executivo

**VEREDITO: o produtor das strings parasitas está FORA do Rails. Não é o front, não é o
Chatwoot/ChatSPX, não é n8n. São DOIS produtores externos distintos, e o dump do usuário é uma
mistura dos dois.**

1. `👥 *Nome (<lid>@lid)*` no corpo da mensagem é montado pela **WAHA Chatwoot App** (plugin nativo
   da WAHA, `app: "chatwoot"`), em `src/apps/chatwoot/consumers/waha/base.ts:379-390`, usando o
   template i18n `whatsapp.group.message: 👥 *{{{participant}}}*`. O `(<lid>@lid)` vem da linha
   `participant = \`${name} (${participant})\`` — a WAHA concatena o JID **cru** do participante ao
   nome, e para participantes em modo LID esse JID continua `@lid` (`toCusFormat` não converte LID
   → telefone).
2. `(GROUP)` **em caixa alta** NÃO é da WAHA. É da **Evolution API**, hardcoded em
   `chatwoot.service.ts:737`: `` nameContact = `${group.subject} (GROUP)` ``. A WAHA usa i18n:
   `'Group'` (en-US) / `'Grupo'` (pt-BR) — **nunca** `GROUP`, em nenhuma versão desde 2025-09.
3. O Rails **apenas persiste**: `Public::Api::V1::Inboxes::MessagesController#message_params`
   grava `content: permitted_params[:content]` sem transformar
   (`app/controllers/public/api/v1/inboxes/messages_controller.rb:78-88`). O front só renderiza
   markdown (`FormattedContent.vue` → `MessageFormatter.js`). Provado no banco: o `👥 … (@lid)`
   está **dentro** da coluna `messages.content`.
4. O webhook nativo `POST /webhooks/waha/:session_name` **não ingere mensagem nenhuma** — só trata
   `poll.vote` (`app/jobs/webhooks/waha_events_job.rb:9-16`). Todo o inbound de grupo entra pela
   **API pública de inbox** (`/public/api/v1/inboxes/...`), chamada pela WAHA App.
5. Consequência direta: **o caminho de normalização LID→PN do Rails nunca roda para grupos.** Ele
   só dispara quando `source_id` termina em `@lid`
   (`public/api/v1/inboxes_controller.rb:37,156-158`), e em grupo o `source_id` é um UUID gerado
   pelo próprio Rails. O LID do participante nem chega como identificador — chega **embutido no
   texto**.
6. **A boa notícia**: a WAHA App expõe `config.templates` (override Mustache por chave i18n). Dá
   para matar o `👥` e o `(<lid>@lid)` **sem tocar em uma linha de Rails**, via `POST /api/apps` na
   WAHA. (Escrita não executada — fora do escopo desta rodada.)

---

## Achados

### 1. FATO VERIFICADO — O `👥 … (@lid)` está gravado na coluna `messages.content`

Query (read-only) na conversa 2446, inbox 43 (`simplexteste`, WAHA):

```json
{
  "id": 34084,
  "content": "👥 *Walisson (60756640940218@lid)*\n\nVish\n`🗓️ Hoje, 02 de mai. • 18:26 BRT`",
  "inbox_id": 43,
  "sender_id": 1963,
  "sender_type": "Contact",
  "source_id": null,
  "content_type": 0,
  "message_type": 0,
  "content_attributes": {},
  "additional_attributes": {}
}
```

```json
{
  "id": 33966,
  "content": "👥 *‎Rogerio José Da Silva (229480102662169@lid)*\n\nquando cheegar quero ver umas coisa no fw com vc",
  "inbox_id": 43, "sender_id": 1963, "sender_type": "Contact", "source_id": null
}
```

Verificado também que o `U+200E` (LEFT-TO-RIGHT MARK) citado no briefing **está no banco**:

```
SELECT position(U&'\200E' in content) > 0 FROM messages WHERE id=33966;  -->  true
```

**Isso encerra a dúvida "front ou backend": é dado gravado, não renderização.**
O mesmo LID `229480102662169@lid` do dump do usuário aparece aqui — é o mesmo participante real.

Volumetria:

| | contagem |
|---|---|
| `messages.content LIKE '%👥%'` | 543 |
| `messages.content LIKE '%@lid)%'` | 542 |

Distribuição por inbox (a única ocorrência fora de inbox WAHA é uma mensagem de menu em que o
usuário digitou o emoji — id 16371, falso positivo):

| inbox_id | nome | motor | msgs com 👥 | primeira | última |
|---|---|---|---|---|---|
| 11 | ADM-Realizare | Evolution | 1 (falso positivo) | 2025-08-22 | 2025-08-22 |
| 17 | spx | WAHA | 420 | 2025-12-03 | 2026-02-23 |
| 41 | teste | WAHA | 8 | 2026-02-19 | 2026-02-23 |
| 42 | spx | WAHA | 16 | 2026-02-28 | 2026-03-03 |
| 43 | simplexteste | WAHA | 98 | 2026-03-12 | 2026-05-02 |

**100% do `👥` real vem de inbox WAHA. Zero de inbox Evolution.**

---

### 2. FATO VERIFICADO — Quem concatena `(<lid>@lid)`: `base.ts:379-390` da WAHA

Código-fonte público da WAHA (`devlikeapro/waha`, branch `core`, HEAD `7e719d8894a3` de 2026-07-08),
`src/apps/chatwoot/consumers/waha/base.ts`:

```ts
375:    // Add participant name to group messages
376:    const manyParticipants = isJidGroup(chatId) || isJidBroadcast(chatId);
377:    if (!payload.fromMe && manyParticipants) {
378:      const key = parseMessageIdSerialized(payload.id, true);
379:      let participant = toCusFormat(
380:        key.participant || (payload as any)._data.participant,
381:      );
382:      const contact: any = await this.session.getContact(participant);
383:      const name = contact?.name || contact?.pushName || contact?.pushname;
384:      if (name) {
385:        participant = `${name} (${participant})`;     // <-- AQUI nasce "Nome (229480102662169@lid)"
386:      }
387:      content = this.l.key(TKey.WHATSAPP_GROUP_MESSAGE).render({
388:        text: content,
389:        participant: participant,
390:      });
391:    }
```

Ou seja: a WAHA **resolve o nome** (`getContact` → `pushName`), mas em vez de descartar o JID ela o
**anexa entre parênteses**. Isso confirma a leitura do coordenador: o problema não é falta de nome,
é o JID concatenado.

Por que continua `@lid` e não vira telefone —
`src/core/utils/jids.ts:149-161`:

```ts
149: export function toCusFormat(remoteJid) {
150:   if (!remoteJid) return remoteJid;
153:   if (isJidGroup(remoteJid))     return remoteJid;
156:   if (isJidBroadcast(remoteJid)) return remoteJid;
159:   if (isLidUser(remoteJid))      return normalizeJid(remoteJid);   // <-- LID passa direto
```

`normalizeJid` só remove o sufixo `:device` (`jids.ts:52-54`). **Não há resolução LID→PN nesse
caminho** — a WAHA tem `findPNByLid` (usado em `LidContactInfo`, para conversas 1:1), mas o código
de participante de grupo não o chama.

---

### 3. FATO VERIFICADO — Quem prefixa `👥 `: template i18n da WAHA

`src/apps/chatwoot/i18n/locales/en-US.yaml:75-78` (idêntico em `pt-BR.yaml:77-80`):

```yaml
whatsapp.group.message: |-
  👥 *{{{participant}}}*

  {{{text}}}
```

Confirmado em 4 revisões históricas do arquivo (`bcd219968`, `e839203db`, `55499a614`,
`304b0037e`) — **sempre foi `👥`**.

Outras strings do dump do usuário, todas do mesmo arquivo (locale `pt-BR`):

| String no dump | Chave da WAHA | Arquivo:linha (pt-BR.yaml) |
|---|---|---|
| `✏️ Editado no WhatsApp` | `message.edited.in.whatsapp` | 72-75 |
| `Reagiu com 👍` | `whatsapp.reaction.added` | 82-83 |
| `📱 Enviado do WhatsApp` | `message.from.whatsapp` | (equiv. en-US:57-60) |
| `` `🗓️ Hoje, 02 de mai. • 18:26 BRT` `` | `whatsapp.history.message.wrapper` | (equiv. en-US:80-82) |

Confirmação no banco (todas essas strings aparecem **só** em inboxes WAHA):

| String | inboxes onde ocorre |
|---|---|
| `Reagiu com` | 17 (19x), 41 (2x), 43 (5x) — nenhuma Evolution |
| `Editado no WhatsApp` | 17 (5x), 41 (5x), 42 (7x), 43 (13x) — nenhuma Evolution |

Exemplo cru de reação (id 32957, inbox 43):
`👥 *Paulo Moggi (20942428352717@lid)*\n\n*Reagiu com* 🤨`

---

### 4. FATO VERIFICADO — Quem sufixa `(GROUP)`: **NÃO é a WAHA. É a Evolution API.**

> ⚠️ **CONTRADIZ PARCIALMENTE O BRIEFING.** O briefing trata `👥` e `(GROUP)` como se viessem do
> mesmo produtor. Não vêm.

**WAHA** — `src/apps/chatwoot/contacts/WhatsAppContactInfo.ts:152-169`:

```ts
152:  async PublicContactCreate(): Promise<Contact> {
153:    let name = this.chatId;
154:    const group: any = await this.session?.getGroup(this.chatId);
155:    if (group) {
156:      name = group.subject || group.name || group.topic || name;
158:      const suffix = this.locale.key(TKey.WHATSAPP_CONTACT_GROUP_SUFFIX).render();
161:      name = `${name} (${suffix})`;
162:    }
164:    return { identifier: this.chatId, name: name, custom_attributes: await this.Attributes() };
165:  }
```

com `whatsapp.contact.group.suffix: 'Group'` (en-US.yaml:112) / `'Grupo'` (pt-BR.yaml:88).
**Capitalização normal, nunca `GROUP`.**

**Evolution API** — `EvolutionAPI/evolution-api`,
`src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts:737`:

```ts
737:          nameContact = `${group.subject} (GROUP)`;
```

Hardcoded, caixa alta, sem i18n. E o formato de participante da Evolution é **outro**
(mesmo arquivo, linhas 2099-2100 e 2280):

```ts
2099:  ? `**${formattedPhoneNumber} - ${participantName}:**\n\n${bodyMessage}`
```

Evidência no banco desta VM — a divisão é perfeita:

| inbox | motor (webhook_url) | contatos `(GROUP)` | contatos `(Grupo)` |
|---|---|---|---|
| 2 `simplex_996571379` | `evo.simplexsolucoes.com.br/...` | **51** | 0 |
| 8 `Plantao-Realizare` | `evo…` | **1** | 0 |
| 11 `ADM-Realizare` | `evo…` | **32** | 0 |
| 12 `Locacao-Realizare` | `evo…` | **23** | 0 |
| 17 `spx` | `waha.simplexsolucoes.com.br/webhooks/chatwoot/spxdev/spxdev` | 0 | **3** |
| 41 `teste` | `api.chatspx.app/webhooks/chatwoot/SPX/teste` | 0 | **1** |
| 42 `spx` | `waha…/webhooks/chatwoot/spx/chatwoot-spx` | 0 | **2** |
| 43 `simplexteste` | `waha…/webhooks/chatwoot/simplexteste/chatwoot-simplexteste` | 0 | **1** |

E o conteúdo antigo da inbox 2 (Evolution) bate exatamente com o template da Evolution:

```
id 17047 | conv 1177 | source_id "WAID:3A251CF275F9B168DDAB"
content: "**+55 (66) 9994-9191 - ‎Rogerio José Da Silva:**\n\n…"
```

(o prefixo `WAID:` no `source_id` também é assinatura da Evolution; nas mensagens WAHA o
`source_id` é `NULL`.)

**Nota crítica**: o contato `TI TOZI - Inovação (GROUP)` **existe nesta VM** — `contacts.id = 24`,
`identifier = 556696571379-1634750731@g.us`, conta 3 — e todos os seus 9 `contact_inboxes` estão na
**inbox 2 (Evolution)**. Ou seja: esse nome exato do dump do usuário foi gravado por Evolution API.

---

### 5. HIPÓTESE FORTE (mecanismo provado, caso concreto não observável aqui) — por que o dump mistura `(GROUP)` da Evolution com `👥 …@lid` da WAHA

O dump do usuário tem cabeçalho `TI TOZI - Inovação (GROUP)` (assinatura Evolution) e corpo
`👥 Nome (…@lid)` (assinatura WAHA). Explicação:

1. A WAHA cria contato via **API pública de inbox** com `identifier = <groupid>@g.us`
   (`WhatsAppContactInfo.ts:165`) e **sem** `source_id`.
2. O Rails, em `ContactInboxWithContactBuilder#find_contact`
   (`app/builders/contact_inbox_with_contact_builder.rb:65-72,96-100`), procura contato existente
   **por `identifier`** no escopo da conta. Se achar, **retorna o contato como está** — só
   `create_contact` (linha 54-63) define `name`.
3. A WAHA, do lado dela, ao encontrar contato existente só atualiza **custom_attributes e avatar**
   (`client/ContactService.ts:132-148` `upsertCustomAttributes`, `:169-195` `updateAvatar`) —
   **nunca o `name`**. A própria doc oficial diz: *"It Does Not Update Existing Contacts … WAHA
   searches for the contact by the WhatsApp Chat ID attribute"*.

Logo: quem migrou uma conta de Evolution → WAHA fica com o **nome de contato legado
`… (GROUP)`** para sempre, recebendo mensagens novas no formato WAHA. É exatamente o retrato do
dump.

**NÃO CONFIRMADO** com dado direto porque: (a) o cliente do dump é a Tozi PROD (`.109`) e o
briefing proíbe SSH para outras VMs; (b) nesta VM nenhum contato `(GROUP)` tem `contact_inbox` em
inbox WAHA (`SELECT … WHERE name LIKE '%(GROUP)%' AND inbox_id IN (17,41,42,43)` → 0 linhas).

**Hipóteses alternativas restantes para o `(GROUP)` na Tozi**, e como testar (tudo read-only, mas
exige acesso que W1 não tem):
- **H-a (mais provável)**: contato legado Evolution reusado por identifier, como acima.
  *Teste*: na `.109`, `SELECT id,name,identifier,created_at FROM contacts WHERE name LIKE '%(GROUP)%'`
  e comparar `created_at` do contato com o `created_at` da inbox WAHA. Se o contato for mais antigo
  que a inbox WAHA → confirmado.
- **H-b**: a inbox da Tozi ainda é Evolution e o `👥 …@lid` vem de outra inbox exibida junto.
  *Teste*: `SELECT ca.webhook_url FROM inboxes i JOIN channel_api ca … WHERE i.id = <inbox da conversa>`.
  Se apontar para `evo.…` → é Evolution; mas então o `👥` teria de vir de outro lugar (improvável,
  Evolution não emite `👥` em nenhuma versão do `chatwoot.service.ts`).
- **H-c**: a Tozi roda a WAHA com um arquivo de idioma **customizado**
  (`WAHA_APPS_CHATWOOT_LANGUAGES_FOLDER`) em que alguém escreveu `GROUP`.
  *Teste*: `GET /api/apps?session=<sessão da Tozi>` e ver `config.locale` / `config.templates`;
  e `docker inspect` da WAHA da Tozi procurando esse env.

---

### 6. FATO VERIFICADO — O Rails só persiste; nada é montado aqui

Caminho de gravação da mensagem, ponta a ponta:

- Rota: `config/routes.rb:711-728` →
  `POST /public/api/v1/inboxes/:inbox_id/contacts/:contact_id/conversations/:conversation_id/messages`
- `app/controllers/public/api/v1/inboxes/messages_controller.rb:8-14` — `create`
- `:78-88` — `message_params`:

```ruby
78:  def message_params
79:    {
80:      account_id: @conversation.account_id,
81:      sender: @contact_inbox.contact,        # <-- sender é o CONTATO-GRUPO, sempre o mesmo
82:      content: permitted_params[:content],   # <-- content vai CRU, sem transformação
83:      inbox_id: @conversation.inbox_id,
84:      echo_id: permitted_params[:echo_id],
85:      source_id: permitted_params[:source_id],
86:      message_type: :incoming
87:    }
88:  end
```

Confirmação por grep (reproduzindo o que o briefing afirmou):

```
grep -rn "(GROUP)" app lib enterprise config          -> 0 resultados
grep -rn $'\U0001F465' app lib enterprise config      -> 1 resultado, e é o help center:
   app/javascript/dashboard/components-next/HelpCenter/EmptyState/Category/categoryEmptyStateContent.js:45
```

**Front**: `app/javascript/dashboard/components-next/message/bubbles/Text/FormattedContent.vue:17-28`
apenas roda `new MessageFormatter(props.content).formattedMessage` e injeta com
`v-dompurify-html`. O `MessageFormatter` (`app/javascript/shared/helpers/MessageFormatter.js:61-91`)
só converte markdown (é ele que transforma o `*Nome*` da WAHA em **negrito** na tela). **Nenhuma
concatenação de nome, LID ou sufixo no front.**

---

### 7. FATO VERIFICADO — Qual caminho de entrada está ativo

| Caminho | Status | Evidência |
|---|---|---|
| (a) `POST /webhooks/waha/:session_name` → `Webhooks::WahaEventsJob` | **NÃO ingere mensagens** | `app/jobs/webhooks/waha_events_job.rb:9-16` — `case event` só trata `poll.vote` / `poll.vote.failed`; qualquer outro evento cai no `else` e vira `logger.debug`. O comentário do controller diz explicitamente: *"Receives WAHA session-level webhooks for events the external \"chatwoot\" app does not relay (poll votes)"* (`app/controllers/webhooks/waha_controller.rb:3-5`). |
| (b) **API pública de inbox** (`/public/api/v1/inboxes/...`) | **ATIVO — é por aqui que tudo entra** | `config/routes.rb:711-728`; do lado WAHA, `client/ContactService.ts:157-159` usa `this.inboxAPI.contacts.create({ inboxIdentifier: this.config.inboxIdentifier, … })`. O `inboxIdentifier` na config da app bate com `channel_api.identifier` da inbox (ver achado 8). |
| (c) `Messages::MessageBuilder` / `Api::V1::…::MessagesController` | Não participa do inbound WAHA | são caminhos de mensagem **outgoing** (agente) e de outros canais. |
| (c') `app/services/messages/waha_message_resolvable.rb` | Só **editar/apagar** mensagem já existente | `:39-59` `resolve_waha_message_id` — mapeia Message→WhatsApp id para chamar `PUT/DELETE` na WAHA. Não cria mensagem. |

Complemento: a WAHA usa **dois** clientes contra o Chatwoot — o *público* (cria contato/conversa/
mensagem, autenticado por `inboxIdentifier`) e o de *conta* (`accountAPI`, autenticado pelo
`accountToken` = access token de um usuário admin) para `contacts/filter`, `contacts/update` e
avatar (`client/ContactService.ts:112-116, 144-148, 199+`).

---

### 8. FATO VERIFICADO — A config real da app WAHA (ambiente de homologação)

`GET https://waha.simplexsolucoes.com.br/api/apps?session=simplexteste` (token mascarado por mim):

```json
{
  "id": "chatwoot-simplexteste",
  "session": "simplexteste",
  "app": "chatwoot",
  "enabled": true,
  "config": {
    "linkPreview": "OFF",
    "locale": "pt-BR",
    "url": "https://chatspx.app",
    "accountId": 3,
    "accountToken": "***MASKED***",
    "inboxId": 43,
    "inboxIdentifier": "1a4qsxXHYjPyJXUecxZKN9b3"
  }
}
```

Bate exatamente com o banco: `inboxes.id = 43`, `channel_api.identifier = 1a4qsxXHYjPyJXUecxZKN9b3`.
E com o código que cria essa app: `app/controllers/api/v1/accounts/waha_connections_controller.rb:83-99`
(`app_config` com `url/accountId/accountToken/inboxId/inboxIdentifier/locale: 'pt-BR'/agentSignatureEnabled`)
→ `app/services/waha/api_service.rb:221-233` (`create_chatwoot_app`, `POST /api/apps`).

> **Nota**: `locale: 'pt-BR'` é enviado pelo NOSSO código (linha 89). É por isso que aqui aparece
> `(Grupo)` e não `(Group)`.

`GET /api/version` → `{"version":"2026.4.2","engine":"GOWS","tier":"PLUS", …}`.

Outra app na mesma WAHA (sessão `Simplex`, `enabled: false`) mostra que **override de template já é
usado na prática pela Simplex**:

```json
"templates": {
  "chatwoot.to.whatsapp.message.text": "*{{{chatwoot.sender.name}}}*:\n{{{ content }}}",
  "chatwoot.to.whatsapp.message.media.caption": "…"
}
```

---

### 9. FATO VERIFICADO — Por que a normalização LID→PN do Rails não pega grupos

`app/controllers/public/api/v1/inboxes_controller.rb`:

```ruby
 35:  def normalize_waha_contact_params(source_id:, phone_number:, custom_attributes: nil)
 36:    return { … } if source_id.blank?
 37:    return { … } unless waha_lid?(source_id)      # <-- gate
…
156:  def waha_lid?(source_id)
157:    source_id.to_s.end_with?('@lid')
158:  end
```

Para grupo, a WAHA **não envia `source_id`** (`WhatsAppContactInfo.ts:164-168` devolve só
`identifier`, `name`, `custom_attributes`). Então o Rails cai em
`app/controllers/public/api/v1/inboxes/contacts_controller.rb:8`:

```ruby
8:    source_id = params[:source_id] || SecureRandom.uuid
```

Confirmado no banco — todo contato de grupo tem `source_id` UUID:

```
inbox 43 | source_id 5ae81747-2dd5-4e93-b5d1-703c7cb81306 | contact 1963
          name "Simplex - Uptime (Grupo)" | identifier "120363403758104643@g.us"
          custom_attributes {"waha_whatsapp_chat_id": "120363403758104643@g.us"}
```

Consequências:
- `waha_lid?(source_id)` → `false` → `resolve_lid_to_pn` **nunca é chamado**;
- `merge_waha_lid_contact_inbox_to_pn` e `Contacts::ResolveLidJob` também não;
- `sanitize_waha_contact_name` (`inboxes_controller.rb:183-196`) remove sufixos `@c.us/@lid/@g.us`
  do **nome**, mas o nome do grupo não termina em JID — então não faz nada aqui;
- os LIDs dos participantes **não existem como dado estruturado** em lugar nenhum do nosso banco:
  só como substring do `content`.

E `messages.sender_id` é **sempre o contato-grupo** (1963 em todas as amostras) — não há
modelagem de participante. Isso responde antecipadamente parte da pergunta 4 do briefing.

---

## Diagrama da cadeia (onde cada string parasita entra)

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ WhatsApp (grupo 1203…@g.us)                                                      │
│   payload.key.participant = "229480102662169@lid"   ← WhatsApp já entrega LID     │
│   payload.pushName        = "‎Rogerio José Da Silva" (com U+200E)                 │
└───────────────────────────────┬──────────────────────────────────────────────────┘
                                │ engine GOWS
┌───────────────────────────────▼──────────────────────────────────────────────────┐
│ WAHA 2026.4.2  (https://waha.simplexsolucoes.com.br)  — FORA do nosso repo        │
│                                                                                   │
│  consumers/waha/base.ts:379-386                                                   │
│     participant = toCusFormat(key.participant)   → "229480102662169@lid"          │
│     name        = getContact(participant).pushName                                │
│  ▶▶ participant = `${name} (${participant})`     ← ①  ENTRA O "(<lid>@lid)"       │
│                                                                                   │
│  base.ts:387-390 → render(TKey.WHATSAPP_GROUP_MESSAGE)                            │
│     i18n/locales/pt-BR.yaml:77-80  "👥 *{{{participant}}}*\n\n{{{text}}}"          │
│  ▶▶                                              ← ②  ENTRA O PREFIXO "👥 "        │
│                                                                                   │
│  base.ts:403 finalizeContent → whatsapp.history.message.wrapper (msg antiga)      │
│  ▶▶                                              ← ③  ENTRA "🗓️ Hoje, 02 de mai."  │
│                                                                                   │
│  contacts/WhatsAppContactInfo.ts:158-161                                          │
│     name = `${subject} (${suffix})`  suffix = 'Grupo' (pt-BR) | 'Group' (en-US)   │
│  ▶▶                                              ← ④  ENTRA "(Grupo)"/"(Group)"   │
└───────────────────────────────┬──────────────────────────────────────────────────┘
                                │ HTTPS
                                │ POST /public/api/v1/inboxes/{inboxIdentifier}/contacts
                                │ POST …/conversations   POST …/messages
┌───────────────────────────────▼──────────────────────────────────────────────────┐
│ ChatSPX / Rails — NÃO TRANSFORMA NADA                                             │
│  contacts_controller.rb:8      source_id = params[:source_id] || SecureRandom.uuid │
│  contacts_controller.rb:16     sanitize_waha_contact_name (não mexe em "(Grupo)")  │
│  ContactInboxWithContactBuilder:65-72  find_contact BY identifier → NÃO renomeia   │
│  messages_controller.rb:82     content: permitted_params[:content]   ← passa cru   │
│  messages_controller.rb:81     sender: @contact_inbox.contact  (= o contato-GRUPO) │
└───────────────────────────────┬──────────────────────────────────────────────────┘
                                │
┌───────────────────────────────▼──────────────────────────────────────────────────┐
│ Postgres  messages.content = "👥 *Nome (…@lid)*\n\nTexto"    ← PROVADO (achado 1)  │
│           contacts.name    = "Nome do grupo (Grupo)"                              │
└───────────────────────────────┬──────────────────────────────────────────────────┘
                                │
┌───────────────────────────────▼──────────────────────────────────────────────────┐
│ Front Vue — só renderiza markdown                                                 │
│  bubbles/Text/FormattedContent.vue:17-28 → MessageFormatter.js:61-91              │
│  "*Nome (…@lid)*" vira <strong>Nome (…@lid)</strong>  ← 👥 e @lid seguem visíveis  │
└──────────────────────────────────────────────────────────────────────────────────┘


   ╔═══ CAMINHO LEGADO (Evolution API) — ainda vivo nas inboxes 2, 8, 11, 12 ════╗
   ║  evo.simplexsolucoes.com.br                                                 ║
   ║   chatwoot.service.ts:737   nameContact = `${group.subject} (GROUP)`  ← ⑤   ║
   ║   chatwoot.service.ts:2099  `**${phone} - ${participantName}:**\n\n${body}` ║
   ║  → mesmo endpoint público → mesmo Rails → mesmo banco                       ║
   ╚═════════════════════════════════════════════════════════════════════════════╝
```

**Legenda das strings do dump do usuário:**

| String no dump | Produtor | Local exato |
|---|---|---|
| `👥 ` | WAHA | `i18n/locales/*.yaml` → `whatsapp.group.message` |
| `(229480102662169@lid)` | WAHA | `consumers/waha/base.ts:385` |
| `*…*` (negrito) | WAHA (template) + front (render) | template `👥 *{{{participant}}}*` → `MessageFormatter.js` |
| `‎` (U+200E) | WhatsApp | vem no `pushName`, ninguém insere |
| `✏️ Editado no WhatsApp` | WAHA | `message.edited.in.whatsapp` (pt-BR.yaml:72-75) |
| `Reagiu com 👍` | WAHA | `whatsapp.reaction.added` (pt-BR.yaml:82-83) |
| `(GROUP)` | **Evolution API** | `chatwoot.service.ts:737` |

---

## Lacunas / o que não consegui verificar

1. **Não confirmei o dado da Tozi PROD.** O dump veio da `.109` e o briefing proíbe SSH para outras
   VMs. Toda a evidência de banco é da homologação (`.232`). O mecanismo está provado no
   código-fonte dos dois produtores; a atribuição do `(GROUP)` **especificamente na Tozi** é
   hipótese forte (achado 5), não fato verificado.
2. **Não consegui reproduzir localmente o caso misto** `(GROUP)` + `👥…@lid` na mesma inbox: nesta
   VM não existe contato `(GROUP)` com `contact_inbox` em inbox WAHA.
3. **`content_attributes.in_reply_to` das reações**: no dump do usuário a reação aparece com a
   mensagem citada acima (`👥 *Angela Tozi …* Resolvido ✅`), o que sugere `in_reply_to`. Aqui na
   homologação, `SELECT count(*) … WHERE inbox_id IN (17,41,42,43) AND content_attributes->>'in_reply_to' IS NOT NULL`
   → **0**. O código da WAHA seta `content_attributes: { in_reply_to: replyTo }` (`base.ts:404-410`),
   mas depende do `mappingService` ter o mapa da mensagem citada. Não sei dizer se na Tozi funciona
   e aqui não, ou se a versão da app mudou. **NÃO CONFIRMADO.**
4. **Não li o código do `message.reaction.ts` / `MessageEdited.ts`** da WAHA em detalhe — inferi o
   comportamento pelas chaves i18n e pelo dado no banco. Suficiente para a atribuição, insuficiente
   para descrever o algoritmo de match da reação.
5. **Não verifiquei se existe `WAHA_APPS_CHATWOOT_LANGUAGES_FOLDER` configurado** em nenhuma
   instância WAHA (nem na daqui, nem na da Tozi) — se houver, o YAML efetivo pode divergir do
   GitHub.
6. **n8n**: não encontrei nenhum indício de n8n nesta cadeia (nenhum processo local, `docker` nem
   está instalado nesta VM, e os webhooks das inboxes apontam só para `evo.…`, `waha.…` e
   `api.chatspx.app`). Mas **não varri `/opt`, `/srv`, `/home/*` procurando workflows exportados** —
   julguei desnecessário depois que a evidência de código fechou. Se o coordenador quiser
   fechar 100%, é um `grep -rl "g.us" --include=*.json` nesses diretórios.
7. **A versão exata da WAHA em produção na Tozi é desconhecida.** A daqui é `2026.4.2 / GOWS / PLUS`.

---

## Implicações para a solução

### O que isto HABILITA

1. **Correção sem tocar no Rails, via `config.templates` da app WAHA.** A app aceita override
   Mustache por chave i18n (`POST /api/apps`, campo `config.templates` — já usado na sessão
   `Simplex`, achado 8). Overrides candidatos:

   ```yaml
   # tira o LID e o emoji, mantém o nome do participante
   whatsapp.group.message: |-
     *{{{participant}}}*

     {{{text}}}
   whatsapp.contact.group.suffix: 'Grupo'
   ```

   ⚠️ **Limite importante**: o template recebe `participant` **já concatenado** com o JID
   (`base.ts:385`). Um override de template **não consegue** remover o `(…@lid)` — ele só
   reposiciona/reveste a string. Para tirar o LID pelo template seria preciso que a WAHA exponha
   nome e JID separados, o que ela não faz hoje. **O emoji `👥` some com template; o `(<lid>@lid)`
   NÃO.**

2. **Portanto, o menor caminho para tirar o LID do texto é do nosso lado**: um saneamento no
   ingresso — `Public::Api::V1::Inboxes::MessagesController#message_params` — que, para inbox WAHA
   com conversa de grupo, reescreva o `content` removendo ` (\d+@lid)` do bloco de participante
   (e opcionalmente extraia esse LID para `content_attributes`, criando o dado estruturado que hoje
   não existe). Isso é **uma regex numa string que já é nossa quando chega**, não uma briga com o
   core.
   *(Fora do escopo desta rodada — registrado como caminho, não implementado.)*

3. **O LID do participante é recuperável.** Ele está no texto e pode ser extraído para
   `content_attributes` no momento da ingestão, virando chave para: (a) resolver PN via
   `Waha::ApiService#get_lid_phone_number` (já existe, `api_service.rb:92-95`); (b) montar a lista
   de participantes; (c) exibir avatar/nome por mensagem.

4. **Pedido upstream é viável e barato**: a WAHA é open-source no ponto exato do problema
   (`base.ts:385`). Um flag de config tipo `groups.participant.format: name|name-jid|jid` resolveria
   para todo mundo. O projeto já tem histórico de mudanças assim (`bcd219968` — *"ChatWoot - remove
   (WAHA) from contact name"*).

### O que isto IMPEDE / complica

5. **Não dá para consertar retroativamente sem UPDATE em massa.** Os 542 `content` já gravados
   continuam com o LID. Corrigir o histórico exige migration de dados (fora do escopo desta rodada,
   e o briefing proíbe escrita).

6. **`(GROUP)` não sai por config da WAHA** — nas inboxes Evolution ele é hardcoded upstream, e nas
   contas migradas o nome já está congelado no banco (nem Rails nem WAHA renomeiam contato
   existente — achados 5 e 6). Corrigir é `UPDATE contacts SET name = …` ou renomear pela UI.

7. **A modelagem de participante é inexistente e não há atalho**: `messages.sender_id` aponta sempre
   para o contato-grupo. Qualquer exibição "por participante" (avatar, nome próprio, filtro por
   pessoa) exige criar essa entidade — não é ajuste de CSS nem de template.

8. **Cuidado com o `Messages::WahaMessageResolvable`**: ele casa mensagens Chatwoot↔WhatsApp por
   **conteúdo** (`waha_message_resolvable.rb:135-154`). Se sanearmos o `content` na ingestão, o
   match de editar/apagar em grupo pode quebrar — mas note que essas estratégias só rodam para
   mensagens `fromMe` (`:91-93`), e o prefixo de participante só é adicionado quando
   `!payload.fromMe` (`base.ts:377`). Risco baixo, mas **precisa ser verificado antes de mexer**.

---

## Referências

### Código deste repositório (`/home/chatwoot/chatwoot`, branch `homologacao`)

- `app/controllers/webhooks/waha_controller.rb:3-5,9-18` — webhook nativo, só poll
- `app/jobs/webhooks/waha_events_job.rb:9-16` — `case event` ignora tudo menos `poll.vote`
- `app/controllers/public/api/v1/inboxes_controller.rb:35-37,96-109,112-146,156-158,183-196`
- `app/controllers/public/api/v1/inboxes/contacts_controller.rb:7-23`
- `app/controllers/public/api/v1/inboxes/messages_controller.rb:8-14,78-88`
- `app/builders/contact_inbox_with_contact_builder.rb:16-28,54-72,96-100`
- `app/controllers/api/v1/accounts/waha_connections_controller.rb:69-108`
- `app/services/waha/api_service.rb:92-110,221-233`
- `app/services/messages/waha_message_resolvable.rb:39-59,91-93,135-154,176-188`
- `app/javascript/dashboard/components-next/message/bubbles/Text/FormattedContent.vue:17-28`
- `app/javascript/shared/helpers/MessageFormatter.js:61-91`
- `config/routes.rb:711-728,764`

### Código externo (WAHA — `devlikeapro/waha`, branch `core`, HEAD `7e719d8894a3` 2026-07-08)

- `src/apps/chatwoot/consumers/waha/base.ts:247-273,301-333,356-410`
- `src/apps/chatwoot/contacts/WhatsAppContactInfo.ts:140-170,260-280`
- `src/apps/chatwoot/client/ContactService.ts:80-200`
- `src/apps/chatwoot/i18n/locales/en-US.yaml:57-118`
- `src/apps/chatwoot/i18n/locales/pt-BR.yaml:72-92`
- `src/core/utils/jids.ts:28-30,52-54,146-161`
- Histórico do YAML: `bcd219968`, `e839203db`, `55499a614`, `304b0037e` — sufixo sempre `'Group'`

### Código externo (Evolution API — `EvolutionAPI/evolution-api`, branch `main`)

- `src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts:725-762` — `(GROUP)`
- idem `:2088-2100`, `:2270-2280` — `**telefone - Nome:**`

### Documentação

- https://waha.devlike.pro/docs/apps/chatwoot/ — config da app, seção *Templates*, seção
  *Group Participant At The Bottom*, aviso *"It Does Not Update Existing Contacts"*,
  `WAHA_APPS_CHATWOOT_LANGUAGES_FOLDER`
- https://waha.devlike.pro/docs/integrations/chatwoot/
- https://raw.githubusercontent.com/devlikeapro/waha/refs/heads/core/src/apps/chatwoot/i18n/locales/en-US.yaml

### Requisições feitas (todas GET)

- `GET https://waha.simplexsolucoes.com.br/api/version` → `2026.4.2 / GOWS / PLUS`
- `GET https://waha.simplexsolucoes.com.br/api/sessions?all=true` → 12 sessões
- `GET https://waha.simplexsolucoes.com.br/api/apps?session=simplexteste` → app `chatwoot`, `locale: pt-BR`
- `GET https://waha.simplexsolucoes.com.br/api/apps?session=Simplex` → app `chatwoot` (disabled) com `templates` override

### Artefatos baixados (scratchpad da sessão, fora do repo)

`/tmp/claude-1001/-home-chatwoot-chatwoot/371fc09f-a460-4fe9-ba69-63b9bac21b10/scratchpad/`
— `waha-base.ts`, `waha-WhatsAppContactInfo.ts`, `waha-ContactService.ts`, `waha-jids.ts`,
`waha-en-US.yaml`, `waha-pt-BR.yaml`, `evo.ts`, `waha-chatwoot-app.txt`
