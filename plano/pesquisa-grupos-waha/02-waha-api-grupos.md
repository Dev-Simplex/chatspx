# W2 — Capacidades da API WAHA para grupos, participantes e LIDs

> Worker 2 · 2026-07-27 · Pesquisa externa (doc + código-fonte público + GETs na instância real)
> Instância inspecionada: `https://waha.simplexsolucoes.com.br` — **WAHA 2026.4.2, engine GOWS, tier PLUS**
> Todos os requests contra a WAHA foram **GET**. Nenhuma mensagem enviada, nenhuma sessão/grupo alterado.

---

## Resumo executivo

1. **A hipótese do coordenador está CONFIRMADA, com código-fonte na mão.** As strings `👥 Nome (id@lid)`
   e `Nome do grupo (GROUP)` **não são montadas pelo Rails nem pelo n8n** — são montadas pela
   **app Chatwoot embutida na própria WAHA**. Encontrei os dois trechos exatos:
   `src/apps/chatwoot/consumers/waha/base.ts:375-390` (participante) e
   `src/apps/chatwoot/contacts/WhatsAppContactInfo.ts:152-166` (sufixo do grupo).
2. **Pior (ou melhor): é o ChatSPX quem instala essa app.** `app/services/waha/api_service.rb:221-233`
   (`create_chatwoot_app`) faz `POST /api/apps` com `app: 'chatwoot', enabled: true`, e
   `app/controllers/api/v1/accounts/waha_connections_controller.rb:83-91` passa `locale: 'pt-BR'`
   **sem nenhum `templates`** — ou seja, aceitamos 100% dos templates default da WAHA.
3. **A causa-raiz do LID cru é uma linha:** `toCusFormat()` (`src/core/utils/jids.ts:159-161`)
   **preserva** o `@lid` em vez de resolvê-lo para telefone. O código da app já busca o nome
   (`getContact`) mas concatena o identificador sem nunca consultar o mapa LID→PN que a própria
   WAHA mantém.
4. **A WAHA já nos dá tudo o que falta — e nós jogamos fora.** Medição real nesta instância:
   **598 de 598 participantes (100%) de 40 grupos têm o telefone preenchido** no payload de
   `GET /api/{session}/groups`, mesmo com 100% dos JIDs em `@lid`. E
   `GET /api/{session}/groups/{id}/participants/v2` devolve `{id: <lid>, pn: <telefone@c.us>, role}`
   pronto — **campo `pn` que nem está documentado**.
5. **`GET /groups` é chamado hoje pelo `RefreshGroupsJob` e o payload é descartado.** Estamos pagando
   o custo da chamada e ignorando o dado que resolve os dois sintomas.
6. **O webhook de mensagem de grupo já traz o telefone e o nome**, sem chamada extra:
   `_data.Info.SenderAlt` = telefone, `_data.Info.PushName` = nome exibível. Capturei o payload real.
7. **Não há bloqueio de licença.** A instância já é `tier: PLUS`, e a partir de `2026.6.1` a WAHA
   passou a ser 100% grátis sem separação Core/Plus.
8. **Não adianta esperar upstream:** a issue que pede exatamente isso
   ([#1493](https://github.com/devlikeapro/waha/issues/1493)) está **aberta desde 13/10/2025** sem fix.
9. **Existe uma saída de 5 minutos**: o campo `config.templates` da app aceita override do template
   `whatsapp.group.message` — dá para tirar o LID do texto **sem tocar em uma linha de Ruby**.
   (Detalhes e ressalvas no Achado 12.)

---

## Achados

### 1. FATO VERIFICADO — Quem monta `👥 Nome (id@lid)`: a app Chatwoot da WAHA

Trecho exato, `src/apps/chatwoot/consumers/waha/base.ts:374-390` (branch `core`, repo público
`devlikeapro/waha`):

```ts
// Add participant name to group messages
const manyParticipants = isJidGroup(chatId) || isJidBroadcast(chatId);
if (!payload.fromMe && manyParticipants) {
  const key = parseMessageIdSerialized(payload.id, true);
  let participant = toCusFormat(
    key.participant || (payload as any)._data.participant,
  );
  const contact: any = await this.session.getContact(participant);
  const name = contact?.name || contact?.pushName || contact?.pushname;
  if (name) {
    participant = `${name} (${participant})`;      // ← "Rogerio José Da Silva (229480102662169@lid)"
  }
  content = this.l.key(TKey.WHATSAPP_GROUP_MESSAGE).render({
    text: content,
    participant: participant,
  });
}
```

E o template renderizado, `src/apps/chatwoot/i18n/locales/pt-BR.yaml`:

```yaml
whatsapp.group.message: |-
  👥 *{{{participant}}}*

  {{{text}}}
```

**Isso reproduz o dump do briefing caractere por caractere**, incluindo o `👥`, o negrito
(`*...*` → markdown do Chatwoot) e a quebra de linha antes do texto.

O mesmo arquivo de locale explica os outros elementos do dump:

| String no dump | Chave no locale pt-BR | Valor |
|---|---|---|
| `✏️ Editado no WhatsApp` | `message.edited.in.whatsapp` | `{{{text}}}\n\n✏️ *Editado no WhatsApp*` |
| `Reagiu com 👍` | `whatsapp.reaction.added` | `*Reagiu com* {{{emoji}}}` |
| `(GROUP)` / `(Grupo)` | `whatsapp.contact.group.suffix` | `Grupo` (pt-BR) / `Group` (en-US) |

> **Contradiz parcialmente o briefing?** Não — confirma. O briefing dizia "o prefixo `👥` e o sufixo
> `(GROUP)` não existem em lugar nenhum do repositório". Correto: eles existem no repositório **da
> WAHA**, não no nosso. O suspeito levantado (n8n/receptor externo) está **descartado**.

### 2. FATO VERIFICADO — Quem monta `Nome do grupo (GROUP)`

`src/apps/chatwoot/contacts/WhatsAppContactInfo.ts:152-166`:

```ts
class GroupContactInfo extends ChatContactInfo {
  async PublicContactCreate(): Promise<Contact> {
    let name = this.chatId;
    const group: any = await this.session?.getGroup(this.chatId);
    if (group) {
      name = group.subject || group.name || group.topic || name;
      name = group.Name || name;
      const suffix = this.locale
        .key(TKey.WHATSAPP_CONTACT_GROUP_SUFFIX)
        .render();
      name = `${name} (${suffix})`;                 // ← "TI TOZI - Inovação (Grupo)"
    }
    return {
      identifier: this.chatId,
      name: name,
      custom_attributes: await this.Attributes(),
    };
  }
}
```

Há classes irmãs `ChannelContactInfo` (sufixo `Canal`) e `StatusContactInfo` — mesmo padrão.

**Divergência de caixa — NÃO CONFIRMADO.** O dump mostra `(GROUP)` em maiúsculas, mas o locale atual
tem `'Grupo'` (pt-BR) e `'Group'` (en-US). Rastreei o histórico do `en-US.yaml` e em todos os commits
em que a chave existe o valor é `'Group'` — **nunca `'GROUP'`**. Duas hipóteses:
- **(a) mais provável)** o contato do grupo foi criado por uma versão **anterior** da app, quando o
  sufixo era hardcoded em maiúsculas, e **nunca foi renomeado**. A doc da WAHA afirma explicitamente
  que esses nomes **não são atualizados retroativamente**: *"this template does not retroactively
  update that contact"*;
- **(b)** a instância que atende a Tozi roda uma versão diferente da que inspecionei.

Isso é verificável em 1 query: se o contato do grupo no banco tiver `created_at` antigo e o nome
congelado, é a hipótese (a). **Deixo para o worker que tem o banco em mãos.**

### 3. FATO VERIFICADO — A causa-raiz do LID cru é `toCusFormat()`

`src/core/utils/jids.ts:149-172`:

```ts
export function toCusFormat(remoteJid) {
  if (!remoteJid) { return remoteJid; }
  if (isJidGroup(remoteJid)) { return remoteJid; }
  if (isJidBroadcast(remoteJid)) { return remoteJid; }
  if (isLidUser(remoteJid)) { return normalizeJid(remoteJid); }   // ← devolve o @lid como está
  if (isJidNewsletter(remoteJid)) { return remoteJid; }
  if (remoteJid == 'me') { return remoteJid; }
  let number = remoteJid.split('@')[0];
  number = number.split(':')[0];      // remove :{device}
  return ensureSuffix(number);
}
```

`isLidUser` → retorna o LID **normalizado** (só tira o `:{device}`), nunca traduzido. Como o
`participant` de todo grupo moderno vem em `@lid` (ver Achado 5), o resultado é sempre `@lid`.

O que torna isso especialmente frustrante: **duas linhas acima**, o mesmo código já fez
`this.session.getContact(participant)` — teve o participante em mãos e buscou o nome. Bastava ter
consultado o mapa LID→PN no mesmo ponto.

O changelog registra um fix **parcial** nesse caminho:
`2025.10.3 - Handle {device}@lid in groups - issue 1493` — resolveu o `:{device}`, **não** o LID→PN.

### 4. FATO VERIFICADO — A issue upstream está aberta e sem previsão

[devlikeapro/waha#1493](https://github.com/devlikeapro/waha/issues/1493) —
*"[GOWS][Chatwoot] - Group participant - show phone number if available instead of @lid"*

| Campo | Valor |
|---|---|
| Estado | **open** |
| Criada | 2025-10-13 |
| Fechada | — |
| Labels | `patron:PLUS`, `patron:PRO`, `apps:ChatWoot` |
| Milestone | nenhum |

Corpo: *"When we receive message from some users in a group, the message is prefixed with the @lid
information instead of number or contact name. Even if I have the contact saved."*

**Implicação:** esperar o upstream não é plano. Se quisermos resolver, resolvemos do nosso lado.

Issues correlatas encontradas (mesma família de problema, todas na app Chatwoot):
- [#1369](https://github.com/devlikeapro/waha/issues/1369) — "Contact name in groups above message"
  (originou o template `whatsapp.group.message`, changelog `2025.2.1`)
- [#1245](https://github.com/devlikeapro/waha/issues/1245) — "show group name instead of the id in
  contact name" (fix em `2025.9.6`: *"ChatWoot - Use group name for contact"* → gerou o `(Group)`)
- [#1173](https://github.com/devlikeapro/waha/issues/1173) — `phone_number should be in e164 format`
  causando *"Contact not found"* em mensagens de grupo (GOWS)
- [#1359](https://github.com/devlikeapro/waha/issues/1359) — nome do agente não aparece em grupo
- [#1767](https://github.com/devlikeapro/waha/issues/1767) — menções em grupo (resolvida em `2026.1.2`)

### 5. FATO VERIFICADO — Payload real de mensagem de grupo (GOWS 2026.4.2)

Capturado via `GET /api/Simplex/chats/overview` nesta instância. Texto omitido; identificadores reais
mantidos porque são de grupo interno da Simplex:

```jsonc
{
  "id": "false_120363040285567246@g.us_3EB0B972A6DDF5A0F4445A_224712722489413@lid",
  "timestamp": 1785156025,
  "from": "120363040285567246@g.us",          // ✅ o @g.us, como esperado
  "fromMe": false,
  "source": "app",
  "body": "<<TEXTO OMITIDO>>",
  "to": "224712722489413@lid",
  "participant": "224712722489413@lid",       // ⚠️ LID CRU — é isto que vaza na UI
  "hasMedia": false,
  "ack": 2,
  "ackName": "DEVICE",
  "replyTo": null,
  "_data": {
    "Info": {
      "Chat": "120363040285567246@g.us",
      "Sender": "224712722489413:69@lid",           // LID + device
      "IsFromMe": false,
      "IsGroup": true,
      "AddressingMode": "lid",
      "SenderAlt": "556696836077:69@s.whatsapp.net", // 🎯 O TELEFONE, DE GRAÇA, NO MESMO PAYLOAD
      "RecipientAlt": "",
      "ID": "3EB0B972A6DDF5A0F4445A",
      "Type": "text",
      "PushName": "Sentinela",                       // 🎯 O NOME EXIBÍVEL, DE GRAÇA
      "Timestamp": "2026-07-27T09:40:25-03:00",
      "MsgMetaInfo": { "TargetID": "", "TargetSender": "", "TargetChat": "", ... },
      "VerifiedName": null
    },
    "Message": { "conversation": "..." }
  }
}
```

**Respondendo diretamente às perguntas da missão:**

| Pergunta | Resposta |
|---|---|
| Em que campo vem o **nome exibível**? | `_data.Info.PushName` (GOWS). **Não existe** `notifyName` nem `pushName` no nível raiz. |
| Em que campo vem o **identificador do autor**? | `participant` (raiz) e `_data.Info.Sender` — **ambos em `@lid`**. |
| Vêm **ambos** LID e telefone? | **SIM.** LID em `Sender`/`participant`, telefone em **`_data.Info.SenderAlt`**. |
| Existe `participantPn` / `participantLid`? | **NÃO** nesta versão/engine. Grepei o código-fonte inteiro: zero ocorrências. São campos inexistentes. |
| Existe `notifyName`? | **NÃO.** Zero ocorrências no código-fonte da WAHA. |
| `from` é o `@g.us`? | **SIM**, confirmado. |

⚠️ **Alerta de precisão:** `SenderAlt` e `Sender` incluem o sufixo de device (`:69`). Qualquer
consumo desses campos **precisa** cortar em `:` antes do `@` — é exatamente o bug que a WAHA corrigiu
em `2025.10.3` e o que a `toCusFormat` faz na linha 170.

### 6. FATO VERIFICADO — O objeto de grupo do GOWS já traz telefone + admin de cada participante

`GET /api/Simplex/groups?limit=1` — resposta **real** (schema GOWS, bem diferente do exemplo genérico
da doc):

```jsonc
{
  "JID": "120363023843937267@g.us",
  "OwnerJID": "", "OwnerPN": "",
  "Name": "Password Mídia",
  "NameSetAt": "2022-06-28T16:38:24-03:00",
  "NameSetBy": "", "NameSetByPN": "",
  "Topic": "", "TopicID": "", "TopicSetAt": "0001-01-01T00:00:00Z",
  "TopicSetBy": "", "TopicSetByPN": "", "TopicDeleted": false,
  "IsLocked": false,
  "IsAnnounce": false, "AnnounceVersionID": "1656445104293337",
  "IsEphemeral": false, "DisappearingTimer": 0,
  "IsIncognito": false,
  "IsParent": false, "LinkedParentJID": "", "IsDefaultSubGroup": false,
  "DefaultMembershipApprovalMode": "",
  "IsJoinApprovalRequired": false,
  "AddressingMode": "lid",                    // ⚠️ grupo opera em modo LID
  "GroupCreated": "2022-06-28T16:38:24-03:00",
  "CreatorCountryCode": "",
  "ParticipantVersionID": "1761317248352055",
  "Participants": [
    {
      "JID": "112652781121720@lid",
      "PhoneNumber": "556699634471@s.whatsapp.net",   // 🎯 TELEFONE
      "LID": "112652781121720@lid",
      "IsAdmin": false,
      "IsSuperAdmin": false,
      "DisplayName": "",                               // sempre vazio (ver Achado 8)
      "Error": 0,
      "AddRequest": null
    },
    { "JID": "163492342579288@lid", "PhoneNumber": "556692223844@s.whatsapp.net",
      "LID": "163492342579288@lid", "IsAdmin": true, "IsSuperAdmin": false, ... }
  ],
  "ParticipantCount": 0,
  "MemberAddMode": "admin_add",
  "Suspended": false
}
```

### 7. FATO VERIFICADO — Medição empírica: 100% dos participantes têm telefone resolvido

Rodei `GET /api/Simplex/groups?limit=40` e contei:

```
grupos analisados: 40 | participantes: 598
com PhoneNumber preenchido: 598 (100.0%)
com JID em @lid:            598 (100.0%)
com DisplayName preenchido:   0 (0.0%)
AddressingMode por grupo:   {'lid': 40}   ← todos os 40 grupos em modo LID
```

**Este é o número que muda a decisão.** Todo participante chega como `@lid`, e **todos os 598** têm o
telefone disponível no mesmo payload. Não há "taxa de sucesso parcial" a gerenciar aqui — a
informação está lá.

> Ressalva honesta: 598 participantes de 40 grupos de **uma** sessão (Simplex). Não é prova de 100%
> universal — grupos com membros que nunca interagiram com a conta podem ter `PhoneNumber` vazio.
> Mas é ordem de grandeza suficiente para afirmar que **a resolução é a regra, não a exceção**.

### 8. FATO VERIFICADO — Onde está o nome do participante

`DisplayName` no objeto de grupo é **sempre vazio** (0/598). O nome vem de outra fonte —
`GET /api/contacts?session={s}&contactId={lid}`:

```jsonc
// GET /api/contacts?session=Simplex&contactId=112652781121720%40lid
{ "id": "112652781121720@lid", "name": "", "pushname": "Jéssica Caroline" }
```

É **exatamente** este endpoint que a app Chatwoot chama em `base.ts:381` (`this.session.getContact`),
e é daí que sai o `contact?.name || contact?.pushName || contact?.pushname`. Confirma a análise do
briefing: **o nome já vem resolvido; o problema é só o identificador concatenado.**

Note: `name` (nome salvo na agenda) vazio, `pushname` (nome que o usuário escolheu) preenchido. Para
participantes de grupo, `pushname` é a fonte realista.

### 9. FATO VERIFICADO — `participants/v2` devolve o telefone, e a doc não conta isso

```jsonc
// GET /api/Simplex/groups/120363023843937267%40g.us/participants/v2  — RESPOSTA REAL
[
  {"id":"112652781121720@lid","pn":"556699634471@c.us","role":"participant"},
  {"id":"267722592149653@lid","pn":"556696571379@c.us","role":"participant"},
  {"id":"163492342579288@lid","pn":"556692223844@c.us","role":"admin"}
]
```

**A documentação oficial mostra apenas `id` e `role`** — o campo **`pn` não está documentado**.
Ele existe e vem preenchido. Este é, na minha leitura, **o endpoint ideal** para montar a lista de
integrantes: já normaliza `role` entre engines (`left` / `participant` / `admin` / `superadmin`) e já
entrega o telefone em formato `@c.us` (pronto para casar com `contact_inboxes.source_id` do Chatwoot).

Introduzido em `2025.11.1` — *"**API** - `/api/:session/groups/:id/participants/v2`"*.

A versão v1 (`GET /groups/{id}/participants`) devolve o formato cru do engine
(`JID`/`PhoneNumber`/`LID`/`IsAdmin`/`IsSuperAdmin`/`DisplayName`) — mais rico em flags de admin,
menos portável entre engines.

### 10. FATO VERIFICADO — API de LIDs funciona nos dois sentidos, e o cache está quente

```jsonc
// GET /api/Simplex/lids/count
{"count":2757}

// GET /api/Simplex/lids?limit=3
[{"lid":"100150131310666@lid","pn":"556699996752@c.us"},
 {"lid":"100158704513042@lid","pn":"5524999950405@c.us"},
 {"lid":"100193114529848@lid","pn":"556692079631@c.us"}]

// GET /api/Simplex/lids/112652781121720          → LID → telefone
{"lid":"112652781121720@lid","pn":"556699634471@c.us"}

// GET /api/Simplex/lids/pn/556699634471           → telefone → LID  (INVERSO, existe!)
{"lid":"112652781121720@lid","pn":"556699634471@c.us"}
```

**O inverso PN→LID existe** (`GET /api/{session}/lids/pn/{phoneNumber}`) — o briefing perguntava e a
resposta é sim. Quando não encontra, devolve o objeto com o campo faltante em `null`
(`{"lid": null, "pn": "..."}`), **não** um 404.

O cache tem **2.757 mapeamentos** nesta sessão. Sobre o warmup: a doc da WAHA não prescreve uma
estratégia; a página de grupos apenas aponta *"Check 👤 Contacts - Lids if you see `@lid` in
participants list for a group"*. Nosso `RefreshGroupsJob` (que chama `GET /groups` para aquecer o
mapa) é uma estratégia **caseira** — e, como mostra o Achado 7, ela funciona: o `GET /groups` é
justamente o que popula LID→PN em massa. A ironia é que ele **já recebe a resposta com os telefones e
a descarta**.

### 11. FATO VERIFICADO — Eventos de grupo (a base para manter a lista viva)

Suportados por **todas** as engines (WEBJS, WPP, NOWEB, GOWS):

| Evento | Quando dispara | Payload essencial |
|---|---|---|
| `group.v2.join` | **você** entra/é adicionado | `payload.group` completo, **com `participants[]`** |
| `group.v2.leave` | **você** sai/é removido | `payload.group.id` apenas |
| `group.v2.participants` | alguém entra/sai/muda papel | `payload.type` + `payload.participants[]` (**só os alterados**) |
| `group.v2.update` | metadados do grupo mudam | `payload.group` com os campos alterados |
| ~~`group.join`~~ | depreciado | só WEBJS/NOWEB |
| ~~`group.leave`~~ | depreciado | só WEBJS |

`group.v2.participants` — `type` ∈ `join` | `leave` | `promote` | `demote`; `role` ∈
`left` | `participant` | `admin` | `superadmin`. Exemplo da doc:

```jsonc
{
  "event": "group.v2.participants",
  "session": "default",
  "payload": {
    "type": "join",
    "timestamp": 1666943582,
    "group": { "id": "123456789@g.us" },
    "participants": [ { "id": "123456789@c.us", "role": "participant" } ],
    "_data": {}
  }
}
```

⚠️ **A sessão `Simplex` desta instância tem `config.webhooks: []`** — nenhum webhook configurado.
Se formos usar esses eventos, precisamos **assiná-los explicitamente**. Hoje não recebemos nenhum.

### 12. FATO VERIFICADO — Existe override de template, e nós não usamos

A app Chatwoot aceita `config.templates` (Mustache). O que o ChatSPX manda hoje
(`app/controllers/api/v1/accounts/waha_connections_controller.rb:83-91`):

```ruby
app_config = {
  url: chatwoot_base_url,
  accountId: Current.account.id.to_i,
  accountToken: current_user.access_token.token,
  inboxId: @inbox.id.to_i,
  inboxIdentifier: channel.identifier,
  locale: 'pt-BR',
  agentSignatureEnabled: true
}
```

**Sem `templates`.** Logo, rodamos com os defaults do `pt-BR.yaml` — incluindo o
`👥 *{{{participant}}}*`.

Que já usamos override em outra sessão, aliás: `GET /api/apps?session=Simplex` mostra uma app
`chatwoot` (id `spx`) **com** `templates` customizados para o nome do agente:

```jsonc
{ "id":"spx", "session":"Simplex", "app":"chatwoot",
  "config": {
    "linkPreview":"LG", "locale":"pt-BR", "accountId":3, "inboxId":2,
    "templates": {
      "chatwoot.to.whatsapp.message.text":"*{{{chatwoot.sender.name}}}*:\n{{{ content }}}",
      "chatwoot.to.whatsapp.message.media.caption":"{{#singleAttachment}}\n{{#content}}\n*{{{chatwoot.sender.name}}}*:\n{{{ content }}}\n{{/content}}\n{{/singleAttachment}}"
    },
    "commands":{"server":false,"queue":false},
    "conversations":{"markAsRead":true,"sort":"created_newest","status":null}
  },
  "enabled": false }
```

**Ou seja: o mecanismo de override já é conhecido e usado na casa.** Falta aplicá-lo ao template de grupo.

⚠️ **Ressalva importante e honesta sobre o "ganho de 5 minutos":** o override do template
`whatsapp.group.message` mexe no **formato**, não no **valor**. A variável `{{{participant}}}` chega
já concatenada como `"Nome (id@lid)"` — a concatenação acontece em `base.ts:387`, **antes** do
Mustache. Mustache não tem regex nem split. Então:
- ✅ **dá** para mudar o layout (mover para o rodapé, trocar o emoji, tirar o negrito);
- ✅ **dá** para remover **a linha inteira** do participante (template = só `{{{text}}}`), o que
  **elimina o LID da UI** — ao custo de perder também o nome de quem falou;
- ❌ **não dá** para exibir "só o nome, sem o LID" via template.

Exibir "só o nome" ou "nome + telefone" exige que **nós** montemos o texto — ou seja, deixar de usar
a app da WAHA para o caminho de grupo, ou pós-processar no Rails. Isso é decisão de arquitetura, fora
do escopo desta pesquisa (é do W3/coordenador).

### 13. FATO VERIFICADO — Configuração completa da app Chatwoot

Schema oficial (doc `/docs/apps/chatwoot/`), com o que descobri de campos extras vistos em produção:

```jsonc
{
  "id": "app_RANDOMLONGSTRING_LIKE_UUID",   // string longa aleatória p/ app:chatwoot
  "session": "default",
  "app": "chatwoot",
  "config": {
    "linkPreview": "OFF",                    // visto também: "LG"
    "locale": "en-US",                       // qualquer locale de src/apps/chatwoot/i18n/locales
    "url": "http://localhost:3009",          // URL do Chatwoot
    "accountId": 1,
    "accountToken": "CHATWOOT_ACCOUNT_TOKEN",
    "inboxId": 1,
    "inboxIdentifier": "CHATWOOT_INBOX_IDENTIFIER",
    "templates": {},                         // 👈 overrides Mustache por chave de locale
    "commands": { "server": true, "queue": true },
    "conversations": {
      "sort": "created_newest",              // ou "activity_newest"
      "status": ["open", "pending", "snoozed"],
      "markAsRead": true                     // visto em produção; não está no exemplo da doc
    },
    "agentSignatureEnabled": true            // usado pelo ChatSPX; não está no exemplo da doc
  },
  "enabled": true
}
```

**Endpoints de gestão da app** (todos globais, não por sessão):

| Método | Path | Nota |
|---|---|---|
| `GET` | `/api/apps?session={session}` | **`?session=` é obrigatório** — `/api/{session}/apps` dá 404 |
| `POST` | `/api/apps` | o que `create_chatwoot_app` usa |
| `PUT` | `/api/apps/{appId}` | atualizar |
| `DELETE` | `/api/apps/{appId}` | remover |

Variáveis de ambiente relevantes (confirmadas ativas nesta instância via
`GET /api/server/environment`): `WAHA_APPS_ENABLED=true`, `WHATSAPP_DEFAULT_ENGINE=GOWS`,
`WAHA_APPS_JOBS_CONCURRENCY=20`, `WAHA_APPS_JOBS_ATTEMPTS`, `WAHA_APPS_CHATWOOT_LANGUAGES_FOLDER`
(pasta de overrides globais de idioma — **não** definida aqui),
`WAHA_CHATWOOT_COMMAND_PREFIX` (default `wa/`).

Como a app funciona internamente: fila via Redis/BullMQ, com retentativas e reporte de erro no
próprio Chatwoot. Dashboard de jobs em `{waha}/jobs`.

### 14. FATO VERIFICADO — Engines: qual usamos, e o que mudaria trocando

**Usamos GOWS** — `WHATSAPP_DEFAULT_ENGINE=GOWS` no `GET /api/server/environment`, e a sessão
`Simplex` reporta `engine: {gows: {found: true, connected: true}, grpc: {...}}`.

Como cada engine expõe o participante de grupo (`src/apps/chatwoot/waha/engines.ts`):

| Engine | Campo usado como `participant` | Linha |
|---|---|---|
| **GOWS** | `toCusFormat(_data.Info.Sender)` | `engines.ts:127` |
| NOWEB | `message.key.participant` | `engines.ts:71` |
| WEBJS | `message.author` | `engines.ts:180` |
| WPP | `message.author` | `engines.ts:248` |

**Trocar de engine NÃO resolve o LID.** Os quatro caminhos passam pelo mesmo `toCusFormat`
(ou entregam um JID cru que segue para ele), e todos os grupos modernos operam com
`AddressingMode: "lid"`. O que muda entre engines:

- **GOWS** é a recomendação oficial da WAHA para a app Chatwoot (*"`WHATSAPP_DEFAULT_ENGINE=GOWS` -
  Recommended engine"*) e é a única que expõe `SenderAlt` no payload — **é a que melhor nos serve**;
- **NOWEB** exige *Store* habilitado para a API de LIDs e para `/contacts` funcionarem
  (a matriz da doc marca `✔️*` com nota *"Store must be enabled"*), e sofre `rate-overlimit` em
  `GET /groups` sem Store;
- **WEBJS/WPP** rodam navegador — mais pesados, e `SupportsAllChatForMessage(): false`.

**Recomendação: ficar em GOWS.** A troca de engine é custo sem benefício para este problema.

### 15. FATO VERIFICADO — Licença não é obstáculo

- Esta instância: `GET /api/version` → `{"version":"2026.4.2","engine":"GOWS","tier":"PLUS",...}`.
  Já é **PLUS**.
- Todos os controllers relevantes (`groups.controller.ts`, `lids.controller.ts`,
  `contacts.controller.ts`) e **toda a app Chatwoot** (`src/apps/chatwoot/`) estão no branch **`core`,
  público**. Não encontrei nenhum guard de licença (`grep` por `WAHA_PLUS`/`PlusGuard`/`isPlus` no
  `src/`: zero ocorrências).
- A partir de **`2026.6.1`** a WAHA passou a ser 100% grátis e open source, sem imagem Plus separada
  e sem tiers pagos (os tiers viraram uma "Community tier" opcional).

**Nenhum endpoint necessário para resolver os dois sintomas é exclusivo de versão paga.**

---

## Tabela de endpoints — referência de consulta

Legenda: 🟢 = já usamos no ChatSPX · 🔴 = disponível e **não** usamos · Engines: W=WEBJS, P=WPP, N=NOWEB, G=GOWS

### Grupos

| # | Método | Path | Params | Resposta | Engines | Uso |
|---|---|---|---|---|---|---|
| 1 | GET | `/api/{session}/groups` | `limit`, `offset`, `sortBy=id\|subject`, `sortOrder=asc\|desc`, `exclude=participants` | array de grupos (schema por engine; GOWS traz `Participants[]` com `PhoneNumber`) | W P N G | 🟢 (payload descartado) |
| 2 | GET | `/api/{session}/groups/count` | — | `{"count": 78}` | W P N G | 🔴 |
| 3 | GET | `/api/{session}/groups/{id}` | — | objeto do grupo | W P N G | 🔴 |
| 4 | GET | `/api/{session}/groups/{id}/participants/v2` | — | `[{id, pn, role}]` — **`pn` = telefone** | W P N G | 🔴 **★** |
| 5 | GET | `/api/{session}/groups/{id}/participants` | — | formato cru do engine (`JID`,`PhoneNumber`,`LID`,`IsAdmin`,`IsSuperAdmin`,`DisplayName`) | W P N G | 🔴 |
| 6 | GET | `/api/{session}/groups/{id}/picture` | `refresh=false` | `{"url": "https://pps.whatsapp.net/..."}` (ou `null`) | W P N G | 🔴 |
| 7 | GET | `/api/{session}/groups/{id}/invite-code` | — | string do código | W P N G | 🔴 |
| 8 | GET | `/api/{session}/groups/join-info` | `code` (URL-encoded) | info do grupo (por engine) | W P N G | 🔴 |
| 9 | GET | `/api/{session}/groups/{id}/settings/security/info-admin-only` | — | `{"adminsOnly": true}` | W P N G | 🔴 |
| 10 | GET | `/api/{session}/groups/{id}/settings/security/messages-admin-only` | — | `{"adminsOnly": true}` | W P N G | 🔴 |

<details>
<summary>Endpoints de escrita de grupo (listados por completude — <b>não usar nesta rodada</b>)</summary>

| Método | Path | Efeito |
|---|---|---|
| POST | `/api/{session}/groups` | criar grupo |
| DELETE | `/api/{session}/groups/{id}` | apagar (só WEBJS/WPP) |
| POST | `/api/{session}/groups/{id}/leave` | sair do grupo |
| POST | `/api/{session}/groups/refresh` | ressincronizar grupos do servidor |
| POST | `/api/{session}/groups/join` | entrar via convite |
| PUT | `/api/{session}/groups/{id}/subject` \| `/description` | renomear / descrever |
| PUT/DELETE | `/api/{session}/groups/{id}/picture` | trocar / remover foto |
| POST | `/api/{session}/groups/{id}/participants/add` \| `/remove` | adicionar / remover membro |
| POST | `/api/{session}/groups/{id}/admin/promote` \| `/demote` | promover / rebaixar |
| POST | `/api/{session}/groups/{id}/invite-code/revoke` | invalidar convite |
| PUT | `/api/{session}/groups/{id}/settings/security/*` | travar edição / envio a admins |

Sobre `POST /groups/refresh`: a doc alerta — *"⚠️ Do not call it frequently, it can lead to
`rate-overlimit` error. Usually groups API has all up-to-date information."* **Não precisamos dele**:
o `GET /groups` já traz dado atualizado.
</details>

### LIDs e contatos

| # | Método | Path | Params | Resposta | Engines | Uso |
|---|---|---|---|---|---|---|
| 11 | GET | `/api/{session}/lids` | `limit=100`, `offset=0` | `[{lid, pn}]` | W P N* G | 🟢 |
| 12 | GET | `/api/{session}/lids/count` | — | `{"count": 2757}` | W P N* G | 🔴 |
| 13 | GET | `/api/{session}/lids/{lid}` | `@`→`%40` ou só número | `{lid, pn}` — `pn: null` se não achar | W P N* G | 🟢 |
| 14 | GET | `/api/{session}/lids/pn/{phone}` | idem | `{lid, pn}` — `lid: null` se não achar | W P N* G | 🔴 **(inverso)** |
| 15 | GET | `/api/contacts` | `session`, `contactId` (aceita `@c.us` **e `@lid`**) | `{id, name, pushname}` | W P N* G | 🔴 |
| 16 | GET | `/api/contacts/all` | `session`, `limit`, `offset`, `sortBy`, `sortOrder` | array de contatos | W P N* G | 🔴 |
| 17 | GET | `/api/contacts/check-exists` | `session`, `phone` | `{numberExists, chatId}` | W P N G | 🟢 |
| 18 | GET | `/api/contacts/profile-picture` | `session`, `contactId`, `refresh` | `{profilePictureURL}` | W P N G | 🔴 |

`N*` = NOWEB exige **Store** habilitado.

### Apps (integração Chatwoot) e servidor

| # | Método | Path | Nota | Uso |
|---|---|---|---|---|
| 19 | GET | `/api/apps?session={session}` | lista apps; `?session=` obrigatório | 🔴 |
| 20 | POST | `/api/apps` | cria a app Chatwoot | 🟢 (`create_chatwoot_app`) |
| 21 | PUT | `/api/apps/{appId}` | **atualizar config/templates sem recriar** | 🔴 **★** |
| 22 | DELETE | `/api/apps/{appId}` | remover | 🔴 |
| 23 | GET | `/api/version` | `{version, engine, tier, browser, platform}` | 🔴 |
| 24 | GET | `/api/server/status` | uptime | 🔴 |
| 25 | GET | `/api/server/environment` | ⚠️ **devolve segredos em claro** (API key, senhas) — tratar como endpoint sensível | 🔴 |
| 26 | GET | `/api/sessions` / `/api/sessions/{name}` | config, `me.id`, `me.lid`, `me.jid`, webhooks | 🟢 |

### Eventos (webhook)

| # | Evento | Dispara quando | Engines | Uso |
|---|---|---|---|---|
| 27 | `group.v2.join` | você entra/é adicionado | W P N G | 🔴 |
| 28 | `group.v2.leave` | você sai/é removido | W P N G | 🔴 |
| 29 | `group.v2.participants` | alguém entra/sai/muda papel | W P N G | 🔴 **★** |
| 30 | `group.v2.update` | metadados do grupo mudam | W P N G | 🔴 |
| 31 | `message` / `message.any` | mensagem recebida (traz `SenderAlt`+`PushName`) | W P N G | 🟢 |

---

## O que a WAHA já nos dá e não estamos usando

> Esta é a seção-chave. Tudo abaixo está **disponível hoje**, nesta instância, nesta versão,
> sem upgrade de licença e sem trocar de engine.

### 🥇 1. O telefone de todo participante de grupo — em três lugares diferentes

| Fonte | Campo | Custo | Observação |
|---|---|---|---|
| Webhook da mensagem | `_data.Info.SenderAlt` | **zero** — já vem no payload | precisa cortar `:{device}` |
| `GET /groups/{id}/participants/v2` | `pn` | 1 request por grupo | já em `@c.us`, pronto para usar |
| `GET /groups` | `Participants[].PhoneNumber` | 1 request para **todos** os grupos | formato `@s.whatsapp.net` |

**598/598 (100%) resolvidos** na medição real. O `RefreshGroupsJob` **já faz** a terceira chamada
e **descarta a resposta** — o dado que resolve o sintoma A passa pelo nosso processo hoje e é jogado
no lixo.

### 🥈 2. A lista de integrantes, com papel de admin — pronta, um GET

`GET /api/{session}/groups/{id}/participants/v2` devolve, por participante: identificador (`id`),
**telefone (`pn`)** e **papel (`role`: `participant` / `admin` / `superadmin` / `left`)`**.
É literalmente a matéria-prima do sintoma B, em um único request, com formato estável entre engines.

A variante v1 (`/participants`) acrescenta `IsAdmin` / `IsSuperAdmin` separados, caso se queira a
distinção crua do engine.

### 🥉 3. O nome exibível, sem chamada extra

`_data.Info.PushName` vem **no próprio webhook** da mensagem (`"Sentinela"` no payload capturado).
Para participantes que ainda não falaram no grupo, `GET /api/contacts?contactId={lid}` devolve
`{name, pushname}` — e aceita LID diretamente como `contactId`.

### 4. Foto do grupo e avatar do participante

- `GET /groups/{id}/picture` → URL real do CDN do WhatsApp (validado: retornou uma URL
  `pps.whatsapp.net` funcional).
- `GET /contacts/profile-picture?contactId={id}` → avatar de cada participante (aceita `refresh` para
  furar o cache de 24h).

Hoje a conversa de grupo no ChatSPX não tem foto nem avatares. Ambos estão a um GET de distância.

### 5. Eventos para manter a lista viva (sem polling)

`group.v2.participants` avisa **em tempo real** quem entrou, saiu, foi promovido ou rebaixado —
com `type` e só os participantes alterados. `group.v2.update` avisa mudança de nome/descrição.
**A sessão `Simplex` tem `config.webhooks: []`** — não assinamos nenhum. Qualquer modelagem de
"grupo como entidade" que não use esses eventos vai nascer desatualizada.

### 6. Metadados do grupo que nem sabemos que existem

Do payload real: `Name`, `NameSetAt`, `Topic`/`TopicSetAt` (descrição), `GroupCreated`,
`IsAnnounce` (só admins falam), `IsLocked` (só admins editam), `IsEphemeral` + `DisappearingTimer`,
`IsJoinApprovalRequired`, `MemberAddMode`, `Suspended`, `IsParent`/`LinkedParentJID` (comunidades),
`AddressingMode`. Tudo disponível em `GET /groups` / `GET /groups/{id}`.

### 7. Lookup reverso telefone → LID

`GET /api/{session}/lids/pn/{phone}`. Hoje só usamos a direção LID→PN. O inverso resolve o caso
"tenho o contato no Chatwoot, quero casar com o participante do grupo" sem varrer a lista inteira.

### 8. Override de templates da app — e o `PUT /api/apps/{appId}`

`config.templates` permite reescrever qualquer chave de locale **por app**, e o
`PUT /api/apps/{appId}` permite fazer isso **sem recriar a app** (hoje só chamamos `POST`). O caminho
mais curto para tirar o LID da tela **não passa por deploy de Ruby** — passa por um PUT.

⚠️ Com a ressalva do Achado 12: o template controla o **formato**, não o **valor**. Dá para remover a
linha do participante inteira, não para exibir "só o nome".

### 9. Overrides globais de idioma

`WAHA_APPS_CHATWOOT_LANGUAGES_FOLDER` monta uma pasta de YAMLs que sobrescreve os locales para
**todas** as apps da instância — útil se quisermos padronizar o formato de grupo para a frota inteira
em vez de app por app. **Não está configurado** nesta instância.

### 10. `config.ignore.groups`

A sessão tem `config.ignore: {status: true, groups: false, channels: false, broadcast: false}`.
Existe um botão para **ignorar grupos por completo** no nível da sessão. Não é a solução que queremos,
mas é bom saber que a alavanca existe (e que hoje está desligada — grupos entram).

---

## Lacunas / o que não consegui verificar

1. **A instância que atende a Tozi.** Inspecionei `waha.simplexsolucoes.com.br` (a do `.env` desta VM).
   O grupo *"TI TOZI - Inovação"* (`556696571379-1634750731@g.us`) **existe nesta sessão**, o que é um
   forte indício de ser a mesma origem — mas **não confirmei** que o dump do briefing veio daqui.
   A blindagem proíbe tocar a `.109`.
2. **`(GROUP)` maiúsculo — NÃO EXPLICADO.** O locale atual gera `(Grupo)`/`(Group)`. Nenhuma versão
   histórica do `en-US.yaml` que consegui inspecionar tem `'GROUP'`. Hipótese principal: nome de
   contato congelado por versão antiga (a app **não** renomeia contatos existentes). **Verificável no
   banco** — fora do meu escopo.
3. **Estado da app nesta sessão é ambíguo.** `GET /api/apps?session=Simplex` mostra a app `chatwoot`
   (id `spx`) com **`enabled: false`**, e `config.webhooks: []`. Se a app está desabilitada e não há
   webhook, **por qual caminho as mensagens desta sessão chegam ao ChatSPX?** Não consegui responder
   com GETs. Pode haver outra instância WAHA, outra app, ou um receptor externo. **Isso é território
   do W1/W3 e é importante** — muda quem precisa ser reconfigurado.
4. **Taxa de resolução em cenários adversos.** Meus 100% vêm de grupos onde a conta participa há
   tempo. Não testei grupo recém-criado, membro que nunca interagiu, ou logo após troca de servidor
   WAHA (cenário do `runbook-waha-migration-lid-warmup.md`).
5. **Formato do webhook vs. formato da API.** O payload de mensagem que capturei veio de
   `GET /chats/overview` (`lastMessage`). A doc indica que o evento `message` tem a mesma estrutura,
   mas **não capturei um webhook ao vivo** — não configurei webhook (seria escrita).
6. **`ParticipantCount: 0`** no objeto de grupo enquanto `Participants[]` tem 3 itens. Campo
   aparentemente não populado pelo GOWS. **Não usar** esse campo; contar o array.
7. **Comportamento quando `pn` é desconhecido** em `participants/v2` — não encontrei nenhum caso na
   amostra (todos resolvidos). Presumo `pn: null`, por simetria com `/lids/{lid}`, mas **não
   verifiquei**.
8. **Não li o Swagger da instância** (`WHATSAPP_SWAGGER_ENABLED=true`), que teria o `ChatWootAppConfig`
   exato desta versão. Está protegido por basic auth; preferi não usar credenciais além do necessário.
   Fica como fonte adicional se alguém precisar do schema canônico.

---

## Implicações para a solução

**O que isto HABILITA:**

- **Sintoma A tem duas soluções de custo muito diferente.** A barata (`PUT /api/apps/{appId}` com
  `templates: {"whatsapp.group.message": "{{{text}}}"}`) tira o LID da tela hoje, sem deploy, mas
  perde o nome do autor. A completa exige assumirmos a formatação da mensagem de grupo — e aí temos
  todos os ingredientes (`SenderAlt`, `PushName`, `participants/v2`).
- **Sintoma B é quase só trabalho de UI.** O backend de dados **já existe** na WAHA:
  `participants/v2` dá lista + telefone + papel; `/groups/{id}/picture` e
  `/contacts/profile-picture` dão as imagens; `group.v2.participants` mantém tudo sincronizado.
  Não precisamos inventar sincronização — precisamos consumir e modelar.
- **O `RefreshGroupsJob` pode virar o alicerce sem custo adicional de rede.** Ele já chama
  `GET /groups`; basta parar de descartar a resposta.
- **Casar participante com contato do Chatwoot é viável nos dois sentidos** (`/lids/{lid}` e
  `/lids/pn/{phone}`), com um cache de 2.757 entradas já quente.

**O que isto IMPEDE / restringe:**

- **Mustache não salva o Sintoma A por completo.** A concatenação `Nome (lid)` acontece em código
  TypeScript **antes** do template. Quem quiser "só o nome" tem que sair do caminho da app da WAHA
  para mensagens de grupo — decisão arquitetural, não configuração.
- **Trocar de engine é esforço perdido.** GOWS é o recomendado, é o único com `SenderAlt`, e nenhuma
  outra engine resolve o LID sozinha.
- **Esperar o upstream não é plano.** Issue #1493 aberta há 9 meses, sem milestone.
- **Sem assinar webhooks, nada de tempo real.** A sessão hoje tem `webhooks: []`; qualquer lista de
  integrantes construída agora só se atualiza por polling até que os eventos `group.v2.*` sejam
  assinados.
- **Cuidado com `:{device}`.** `Sender`, `SenderAlt` e `PhoneNumber` vêm com sufixo de device
  (`:69@...`). Consumir sem cortar reproduz um bug que a própria WAHA já teve.
- **Formatos de sufixo divergem entre endpoints:** `@s.whatsapp.net` (em `GET /groups` e `SenderAlt`)
  vs `@c.us` (em `participants/v2` e `/lids`). Normalizar em um único ponto.
- **`GET /api/server/environment` expõe segredos em claro.** Não logar, não expor, não chamar de
  código de aplicação.

---

## Referências

**Documentação WAHA**
- Grupos — https://waha.devlike.pro/docs/how-to/groups/
- Contatos e API de LIDs — https://waha.devlike.pro/docs/how-to/contacts/
- App Chatwoot — https://waha.devlike.pro/docs/apps/chatwoot/
- Apps (visão geral e API) — https://waha.devlike.pro/docs/apps/about/
- Receber mensagens (campos `from`/`to`/`participant`, chat IDs) — https://waha.devlike.pro/docs/how-to/receive-messages/
- Engines — https://waha.devlike.pro/docs/how-to/engines/
- Changelog — https://waha.devlike.pro/docs/overview/changelog/
- Integração legada via n8n (marcada como superada pela app) — https://waha.devlike.pro/docs/integrations/chatwoot/

**Código-fonte WAHA** (repo público `devlikeapro/waha`, branch `core`)
- `src/apps/chatwoot/consumers/waha/base.ts:374-390` — monta `Nome (id@lid)` e renderiza `whatsapp.group.message`
- `src/apps/chatwoot/contacts/WhatsAppContactInfo.ts:152-166` — monta `Nome do grupo (Grupo)`
- `src/core/utils/jids.ts:149-172` — `toCusFormat()`, a causa-raiz do LID preservado
- `src/apps/chatwoot/waha/engines.ts:64-250` — extração de `participant` por engine
- `src/core/utils/ids.ts:11-38` — `parseMessageIdSerialized()`, formato `fromMe_chat_msgId_participant`
- `src/apps/chatwoot/i18n/locales/pt-BR.yaml` e `en-US.yaml` — todos os templates
- `src/apps/chatwoot/i18n/templates.ts:30,37` — chaves `whatsapp.group.message`, `whatsapp.contact.group.suffix`
- Locales: https://github.com/devlikeapro/waha/tree/core/src/apps/chatwoot/i18n/locales

**Issues upstream**
- [#1493](https://github.com/devlikeapro/waha/issues/1493) — **aberta** — telefone em vez de `@lid` em grupo (nosso caso exato)
- [#1369](https://github.com/devlikeapro/waha/issues/1369) — nome do contato acima da mensagem em grupo
- [#1245](https://github.com/devlikeapro/waha/issues/1245) — nome do grupo em vez do id no contato
- [#1173](https://github.com/devlikeapro/waha/issues/1173) — `phone_number should be in e164 format` em grupo (GOWS)
- [#1359](https://github.com/devlikeapro/waha/issues/1359) — display name do agente não aparece em grupo
- [#1767](https://github.com/devlikeapro/waha/issues/1767) — menções em grupo (resolvida em `2026.1.2`)

**Código ChatSPX** (este repo)
- `app/services/waha/api_service.rb:221-233` — `create_chatwoot_app`, o `POST /api/apps`
- `app/controllers/api/v1/accounts/waha_connections_controller.rb:83-91` — config enviada, **sem `templates`**
- `app/services/waha/api_service.rb:92-109` — `get_lid_phone_number`, `get_lids_list`, `get_groups`
- `app/jobs/waha/refresh_groups_job.rb` — chama `GET /groups` e descarta a resposta
- `config/schedule.yml:76-99` — agendamento dos jobs WAHA

**Requests reais executados** (todos GET, instância `waha.simplexsolucoes.com.br`, 2026-07-27)
- `/api/version` · `/api/server/status` · `/api/server/environment` · `/api/sessions` · `/api/sessions/Simplex`
- `/api/apps?session=Simplex` · `/api/Simplex/groups?limit=1` · `?limit=40` · `/api/Simplex/groups/count`
- `/api/Simplex/groups/{id}/participants` · `/participants/v2` · `/picture`
- `/api/Simplex/lids` · `/lids/count` · `/lids/{lid}` · `/lids/pn/{phone}`
- `/api/contacts?session=Simplex&contactId={lid}` · `/api/Simplex/chats/overview?limit=40`
- `/api/Simplex/chats/{groupId}/messages?limit=3`
