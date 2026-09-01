# W5 — Modelagem: como representar grupo, participantes e autor de mensagem no domínio do Chatwoot

> Worker 5 · 2026-07-27 · Escopo: **SÓ PESQUISA**. Nenhum arquivo de aplicação foi tocado, nenhuma
> migration escrita, nenhum comando de escrita no banco, nenhum SSH para outra VM.
> Todas as consultas ao banco foram `SELECT` na base local de homologação (`chatwoot_production`
> desta VM `192.168.8.232`).

---

## Resumo executivo

1. **O autor da mensagem de grupo hoje não existe como dado — existe como texto.** As 514 mensagens
   de grupo desta base guardam o participante dentro de `messages.content`, no formato
   `👥 *Nome (<lid>@lid)*\n\n<texto>`. `messages.sender_id` aponta **sempre para o contato-grupo**
   (todas as mensagens de uma conversa de grupo têm o mesmo sender). Não há campo estruturado
   nenhum. Qualquer solução começa por criar esse campo.
2. **Descobri a origem das duas strings do briefing, e são DUAS origens diferentes** (isso
   **contradiz** a premissa implícita do briefing de que uma só integração monta as duas):
   `(GROUP)` no nome do contato vem do **Evolution API** (literal `${group.subject} (GROUP)` no
   fonte deles), fóssil de jul–ago/2025; `👥 *...*` na mensagem vem do **template de linguagem
   `whatsapp.group.message` do WAHA Chatwoot App**, default desde WAHA `2025.9.5`. As janelas
   temporais no banco batem exatamente.
3. **Fase 0 é configuração, não código.** O template `whatsapp.group.message` é editável no WAHA.
   Isso reduz o custo de "parar o sangramento" a ~zero — mas **não** resolve, porque o
   `{{{participant}}}` da WAHA continua carregando o LID (issue WAHA #1493, **aberta desde
   out/2025**, bloqueada pela #993). Quem tem de resolver LID→telefone somos nós.
4. **O upstream já escolheu um caminho, e é o meu Achado 12 vira recomendação:** o PR
   [chatwoot#13361](https://github.com/chatwoot/chatwoot/pull/13361) (aberto, 51 arquivos,
   +2244/−141, parado desde jan/2026) adiciona `conversations.group/group_title/group_source_id` +
   tabela `group_contacts` + `Message#sender` apontando para o **Contact do participante**,
   resolvido por um parâmetro novo `sender_identifier` na API pública. O co-fundador do Chatwoot
   escreveu publicamente a direção preferida. **Alinhar nossa modelagem a esse desenho é de graça e
   evita divergência futura.**
5. **A identidade do próprio grupo já está quebrada, antes de participante.** 100% (114/114) dos
   `contact_inboxes` de grupo desta base usam **UUID aleatório** como `source_id`, não o JID
   `@g.us`. Consequência medida: "TI TOZI - Inovação (GROUP)" tem **9 contact_inboxes e 8
   conversas** para o mesmo grupo. Modelar participante sem consertar isso é construir no pântano.
6. **O estrago colateral já aconteceu, não é hipótese:** nesta base **15 pesquisas CSAT e 2 NPS
   foram disparadas dentro de conversas de grupo** (uma com `external_error: "404 Not Found"`).
   Nenhum builder de CSAT/NPS/greeting/out-of-office tem qualquer noção de grupo. E o guard de
   grupo do Captain **está desligado por padrão** (`skip_groups` é config-gated).
7. **Recomendação:** híbrido faseado — **Fase 0** (template WAHA + strip no ingest, dias) →
   **Fase 1** (`content_attributes.group_sender` + render no front + guards CSAT/NPS/Captain,
   1–2 semanas, zero migration) → **Fase 2** (flag `group` + `group_source_id` na conversa,
   espelhando o PR upstream, conserta a fragmentação) → **Fase 3** (`group_contacts` +
   `Message#sender` = participante, só quando LID→PN estiver resolvido). Detalhe e justificativa
   na seção "Recomendação".

---

## Achados

### Parte I — O terreno atual

#### Achado 1 — FATO: os campos livres existem e chegam ao front de graça, mas a API de entrada não os aceita

Schema (`db/schema.rb`), campos jsonb disponíveis:

| Tabela | Campo | Tipo | Índice? |
|---|---|---|---|
| `contacts` | `additional_attributes` | `jsonb default {}` | não (só GIN em name/email/phone/identifier) |
| `contacts` | `custom_attributes` | `jsonb default {}` | não |
| `contacts` | `identifier` | `string` | **UNIQUE** `(identifier, account_id)` |
| `conversations` | `additional_attributes` | `jsonb default {}` | GIN só em `-> 'user_settings'` |
| `conversations` | `custom_attributes` | `jsonb default {}` | não |
| `messages` | `content_attributes` | `jsonb default {}` | **não** |
| `messages` | `additional_attributes` | `jsonb default {}` | GIN só em `-> 'campaign_id'` |
| `messages` | `sender_type` / `sender_id` | `string`/`bigint` | `index_messages_on_sender_type_and_sender_id` |
| `contact_inboxes` | `source_id` | `text not null` | **UNIQUE** `(inbox_id, source_id)` |

**Serialização — já chega ao front, custo zero:**
- `app/views/api/v1/models/_message.json.jbuilder:9` → `json.content_attributes`
- `app/views/api/v1/models/_message.json.jbuilder:17` → `json.additional_attributes`
- `app/models/message.rb:161` → `push_event_data` faz `attributes.symbolize_keys.merge(...)`, ou
  seja **todas as colunas** (incluindo os dois jsonb) vão no websocket.
- `app/views/api/v1/conversations/partials/_conversation.json.jbuilder:117` →
  `json.additional_attributes conversation.additional_attributes` e `:120` `custom_attributes`.
- `app/presenters/conversations/event_data_presenter.rb:4,15` → o mesmo no payload de webhook de
  saída (que é o que o app externo da WAHA lê).

> **Conclusão prática:** guardar dados de grupo em `content_attributes` / `additional_attributes` /
> `custom_attributes` **não exige nenhuma mudança de serializer** — nem REST, nem websocket, nem
> webhook. Isso derruba boa parte do custo estimado das opções A e D.

**MAS — o caminho de entrada é fechado.** `app/controllers/public/api/v1/inboxes/messages_controller.rb:70-72`:

```ruby
def permitted_params
  params.permit(:content, :echo_id, :source_id)
end
```

e `:78-87`:

```ruby
def message_params
  { account_id: ..., sender: @contact_inbox.contact, content: permitted_params[:content],
    inbox_id: ..., echo_id: ..., source_id: ..., message_type: :incoming }
end
```

`sender` é **hardcoded** no contato do contact_inbox, e `content_attributes` /
`additional_attributes` **não são permitidos**. Ou seja: hoje o receptor externo **não tem como**
mandar o autor do grupo, nem que quisesse. Toda opção (A inclusive) exige tocar neste controller.
É uma mudança de ~4 linhas, mas não é zero.

#### Achado 2 — FATO: `Message#sender` é polimórfico e aceita, na prática, 4 tipos

`app/models/message.rb:141` → `belongs_to :sender, polymorphic: true, optional: true`. **Não há
validação de tipo permitido.** Os tipos efetivamente usados no código:

| `sender_type` | Onde aparece |
|---|---|
| `Contact` | `app/actions/contact_merge_action.rb:50`, `app/services/search_service.rb:154` |
| `User` | `app/listeners/automation_rule_listener.rb:285`, `app/models/message.rb:519` |
| `AgentBot` | `app/models/message.rb:240,404` |
| `Captain::Assistant` | `app/models/message.rb:240,404`, `enterprise/lib/captain/episode_gate_service.rb:30` |

Um `Contact` "participante" **cabe ali sem nenhuma mudança de modelo** — é o mesmo `sender_type`
que já se usa. O trabalho não está no `Message`, está em (a) criar/achar o Contact do participante
e (b) tudo que hoje assume `message.sender == conversation.contact`.

Consumo do sender que quebraria/mudaria com participantes:
- `app/models/message.rb:165-169` `merge_sender_attributes` — já resolve por polimorfismo, OK.
- `app/services/llm_formatter/conversation_llm_formatter.rb:84-93` — mapeia **qualquer** `Contact`
  para a etiqueta `"User:"`. Com N participantes, a IA vê N humanos colapsados em um só.
- `app/models/message.rb:519` `set_agent_id_from_sender` — só age em `outgoing? && sender_type == 'User'`, imune.
- `app/services/search_service.rb:144-155` — busca "from:" resolve `agent`→User, senão Contact.
  Com participante como sender, a busca por remetente passa a funcionar dentro de grupos (ganho).

#### Achado 3 — FATO: a única detecção de grupo do sistema está desligada por padrão

`enterprise/app/services/captain/behavior/router_service.rb:26-27`:

```ruby
def skip_groups?
  return false unless @config['skip_groups']   # <- config-gated
  conversation_is_group?
end
```

E o spec confirma o comportamento default — `spec/enterprise/services/captain/behavior/router_service_spec.rb:62`:

```ruby
it 'responds to group conversations when skip_groups is not configured' do
  assistant.update!(behavior: { 'router' => {} })
  conversation.update!(additional_attributes: { 'type' => 'group' })
  expect(should_respond?).to be true
end
```

> ⚠️ **Correção ao briefing.** O briefing diz "o sistema sabe **desviar a IA** de grupos". Só sabe
> **se o assistente tiver `router.skip_groups = true` configurado**. O default é **responder no
> grupo**. Além disso, o comentário em `router_service.rb:32` afirma que
> `additional_attributes['type'] == 'group'` é "o sinal padrão do Chatwoot" — **não é**: um
> `grep` em `app/ lib/ enterprise/` mostra que `additional_attributes['type']` só é usado para
> `'tweet'` (`app/models/conversation.rb:285`, `app/services/action_service.rb:109`) e
> `'instagram_direct_message'` (`app/jobs/send_reply_job.rb:47`). Não existe convenção `'group'`
> no Chatwoot upstream — o upstream escolheu uma **coluna booleana** (Achado 12).

Inventário completo do que conhece `@g.us` / `@lid` no repositório (8 arquivos Ruby):

```
app/builders/contact_inbox_with_contact_builder.rb
app/controllers/public/api/v1/inboxes_controller.rb
app/jobs/contacts/resolve_lid_job.rb
app/jobs/contacts/resolve_lid_sweep_job.rb
app/services/contacts/contactable_inboxes_service.rb
app/services/waha/poll_vote_service.rb
enterprise/app/services/captain/behavior/router_service.rb   <- único que diz "isto é grupo"
```

Os outros 7 tratam **LID em 1:1**. **Nada** no core (CSAT, NPS, automações, relatórios,
transcrição, merge) sabe o que é um grupo.

#### Achado 4 — FATO (dado real): o autor está no texto, e o sender é sempre o grupo

```sql
SELECT m.id, m.sender_type, m.sender_id, left(m.content,80)
FROM messages m JOIN conversations cv ON cv.id=m.conversation_id
WHERE cv.contact_id IN (SELECT id FROM contacts WHERE identifier LIKE '%@g.us')
  AND m.message_type=0 ORDER BY m.id DESC LIMIT 6;
```

```
 34084 | Contact | 1963 | 👥 *Walisson (60756640940218@lid)*↵↵Vish↵`🗓️ Hoje, 02 de mai. • 18:26 BRT`
 33968 | Contact | 1963 | 👥 *Ederson Ricieri Davi (74067046604948@lid)*↵↵para vc ir para multiseg
 33966 | Contact | 1963 | 👥 *‎Rogerio José Da Silva (229480102662169@lid)*↵↵quando cheegar quero ver...
```

`sender_id = 1963` para **todas**; contato 1963 = `Simplex - Uptime (Grupo)`,
`identifier = 120363403758104643@g.us`. O formato exato é
`👥 *<Nome> (<lid>@lid)*` + `\n\n` + `<texto>`, às vezes com uma linha final de timestamp em crase.

Dimensão do vazamento nesta base:

| Métrica | Valor |
|---|---|
| Mensagens com prefixo `👥` | **514** (2025-12-03 → 2026-05-02) |
| Mensagens contendo `@lid` no texto | **548**, em **12 conversas** |
| Contatos-grupo (`identifier LIKE '%@g.us'`) | **36** |
| Mensagens em conversas de grupo (por sender_type) | Contact 5 494 · User 3 987 · nulo 299 |

Repare no `User 3 987`: **agentes respondem dentro de grupos ativamente**. Grupo não é caso de
borda aqui, é fluxo de trabalho real.

#### Achado 5 — FATO: a identidade do grupo está quebrada — `source_id` é UUID, e isso fragmenta a conversa

`app/controllers/public/api/v1/inboxes/contacts_controller.rb:8`:

```ruby
source_id = params[:source_id] || SecureRandom.uuid
```

Resultado medido:

```sql
SELECT CASE WHEN ci.source_id LIKE '%@g.us' THEN 'jid'
            WHEN ci.source_id ~ '^[0-9a-f-]{36}$' THEN 'uuid' ELSE 'outro' END, count(*)
FROM contact_inboxes ci JOIN contacts c ON c.id=ci.contact_id
WHERE c.identifier LIKE '%@g.us' GROUP BY 1;
--  uuid | 114        (100%)
```

E a fragmentação que isso produz:

```sql
SELECT c.id, left(c.name,40), count(DISTINCT ci.id) AS cis, count(DISTINCT cv.id) AS convs ...
```

| contato | nome | contact_inboxes | conversas |
|---|---|---|---|
| 170 | Vendas Realizare (GROUP) | **11** | 10 |
| 16 | Infra Data Norte (GROUP) | **10** | 9 |
| 24 | **TI TOZI - Inovação (GROUP)** | **9** | 8 |
| 229 | Kitnete Jaborandis (GROUP) | 8 | 7 |

O contato é reencontrado por `identifier` (`ContactInboxWithContactBuilder#find_contact_by_identifier`,
`app/builders/contact_inbox_with_contact_builder.rb:98-102`), mas como o `source_id` é novo a cada
vez, cria-se **um contact_inbox novo → uma conversa nova**. O grupo do dump do usuário está
literalmente espalhado em 8 conversas.

> **Implicação de modelagem, forte:** qualquer desenho que ancore participantes em
> `contact_inbox.source_id` é inviável hoje. O JID do grupo só existe em `contacts.identifier` e
> em `contacts.custom_attributes['waha_whatsapp_chat_id']`. Isso empurra a favor de um campo
> **`group_source_id` na conversa** (como o upstream fez) e não no contact_inbox.

#### Achado 6 — FATO: já existe um gancho `senderName` no front, mas ele só vale quando NÃO há sender

`app/javascript/dashboard/components-next/message/Message.vue:750-757`:

```js
// If no sender, check for Slack (or other integration) sender info
if (!props.sender) {
  const { senderName, senderAvatarUrl } = props.additionalAttributes || {};
  if (senderName) { return { name: senderName, src: senderAvatarUrl ?? '' }; }
  return { name: t('CONVERSATION.BOT'), src: '' };
}
```

Em mensagem de grupo o `sender` **existe** (é o contato-grupo), então esse ramo **não** é atingido.
Aproveitar o gancho custa uma condição a mais (`|| isGroupMessage`), não zero — mas é o caminho de
menor atrito no front, porque a estrutura `{name, src}` já alimenta avatar e nome.

Existe também `app/javascript/dashboard/helper/commons.js:138` `getSafeContactName(contact)` —
mascara nome quando o `source_id` é `@lid` — mas um `grep` mostra que **essa função não é chamada
em lugar nenhum**. É código morto que já foi escrito pensando neste problema.

#### Achado 7 — FATO: a saída para o grupo é resolvida em dois lugares, e um deles está quebrado

**Texto simples** sai por webhook (`app/listeners/webhook_listener.rb:141-146`, `Channel::Api`) →
app externo da WAHA resolve o destino. O payload leva `meta.sender` = `contact.push_event_data`
(inclui `identifier` `@g.us` e `custom_attributes.waha_whatsapp_chat_id`) e o `contact_inbox`
inteiro — `app/presenters/conversations/event_data_presenter.rb:8,33`. Funciona.

**Mensagens especiais** (botões, lista, enquete, localização, vCard) saem por REST direto:
`app/services/waha/outbound_special_message_service.rb:90-107`:

```ruby
raw    = @conversation.contact_inbox&.source_id.to_s          # UUID para grupo
digits = candidate_digits(raw)
digits = candidate_digits(@conversation.contact&.phone_number.to_s) if digits.blank?  # vazio para grupo
raise Waha::ApiService::Error, "destinatário sem número válido (source_id=#{raw.inspect})" if digits.blank?
```

Nunca consulta `waha_whatsapp_chat_id`. **Portanto: mensagem interativa/enquete/localização/vCard
não pode ser enviada para grupo hoje — levanta exceção.** Compare com
`app/services/messages/waha_message_resolvable.rb:176-188`, que **prefere**
`contact.custom_attributes['waha_whatsapp_chat_id']` e por isso funciona em grupo. Duas
implementações de `chat_id` divergentes no mesmo repositório.

#### Achado 8 — FATO/atenção técnica: `content_attributes` é jsonb mas 2 166 linhas estão gravadas como *string* JSON

```sql
SELECT jsonb_typeof(content_attributes), min(created_at)::date, max(created_at)::date, count(*)
FROM messages WHERE content_attributes IS NOT NULL GROUP BY 1;
--  string | 2025-07-24 | 2026-07-23 |  2166
--  object | 2025-07-24 | 2026-06-11 | 30250
```

Exemplo real (mensagem 35052, dentro de conversa de grupo):
`content_attributes = "{\"nps_survey\":true,\"external_error\":\"404 Not Found\"}"` — string, não objeto.

**HIPÓTESE (não confirmada):** causado por `store :content_attributes, ..., coder: JSON`
(`app/models/message.rb:118`) sobre coluna `jsonb` — o coder serializa para string antes de o tipo
jsonb gravar; caminhos que escrevem o hash direto gravam objeto. As duas formas convivem ao longo
de todo o período, então **não** é resíduo histórico — é dependente do caminho de código.

> **Consequência para a modelagem:** um `content_attributes->'group_sender'` **não é
> consultável de forma confiável em SQL** e um índice GIN sobre ele seria inconsistente. Serve
> para **exibir**, não para **filtrar/relatar**. Isso é um contra real da Opção A que costuma
> passar batido.

### Parte II — Origem das strings (corrige o briefing)

#### Achado 9 — FATO: `(GROUP)` é do **Evolution API**, não da WAHA

Fonte da Evolution API,
`src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts:731-737` (HEAD, baixado via
API do GitHub):

```ts
if (isGroup) {
  const group = await this.waMonitor.waInstances[instance.instanceName].client.groupMetadata(chatId);
  const participantJid = isLid && !body.key.fromMe ? body.key.participantAlt : body.key.participant;
  nameContact = `${group.subject} (GROUP)`;      // <<<<<<<<
```

e o contato do grupo é criado com (`:320-327`):

```ts
data = { inbox_id: inboxId, name: name || phoneNumber, identifier: phoneNumber, avatar_url };
// isGroup=true → SEM phone_number, SEM source_id  → o Chatwoot gera SecureRandom.uuid
```

Isso reproduz **exatamente** o que está no nosso banco: `identifier` = `<jid>@g.us`,
`phone_number` vazio, `source_id` UUID (Achado 5).

**Prova temporal no banco:**

| sufixo do nome | primeiro | último | qtd |
|---|---|---|---|
| `(GROUP)` maiúsculo | 2025-07-24 | 2025-08-25 | 24 |
| `(Group)` camel | 2025-12-02 | 2025-12-02 | 9 |
| `(Grupo)` pt | 2025-11-29 | 2026-02-11 | 3 |

A migration que introduziu a WAHA nativa é `db/migrate/20251202210211_add_waha_session_name_to_inboxes.rb`
— **2025-12-02**, exatamente a fronteira. E o contato do dump do usuário:

```
id=24  name='TI TOZI - Inovação (GROUP)'  identifier='556696571379-1634750731@g.us'
created_at=2025-07-24 20:45:49   updated_at=2025-08-23
custom_attributes={"nao_envia_menu":"Sim"}     <- SEM waha_whatsapp_chat_id
```

Criado em julho/2025, na era Evolution, **nunca renomeado** (tanto Evolution quanto WAHA só
reescrevem o nome se ele estiver vazio ou igual ao chatId). O `(GROUP)` que o usuário vê hoje é um
**fóssil de 1 ano atrás**.

#### Achado 10 — FATO: `👥 *...*` é um **template de linguagem configurável da WAHA**

`devlikeapro/waha` issue [#1369](https://github.com/devlikeapro/waha/issues/1369) (fechada,
completed, 2025-09-23), resposta do mantenedor `@devlikepro`:

> Use this config in language templates
> ```yaml
> whatsapp.group.message: |-
>   👥 *{{{participant}}}*
>
>   {{{text}}}
> ```
> Make sense to use it by default, we'll change it in the next release!

e o changelog dele: `2025.9.5 - ChatWoot - group participant at the top by default`.

As mensagens `👥` do nosso banco começam em **2025-12-03** — coerente.

> **Portanto, respondendo à pergunta 1 do briefing:** ninguém no Rails monta essas strings. São
> **duas integrações externas diferentes, em duas épocas diferentes**. O `👥 *{{{participant}}}*`
> é **editável por configuração na WAHA** — é o botão mais barato que existe neste problema todo.

#### Achado 11 — FATO: a WAHA sabe do problema do LID e **não vai resolver tão cedo**

`devlikeapro/waha` issue [#1493](https://github.com/devlikeapro/waha/issues/1493) —
"[GOWS][Chatwoot] Group participant - show phone number if available instead of @lid" —
**ABERTA desde 2025-10-13**. Linha do tempo:

- `2025.10.3` — mantenedor: "Handle `{device}@lid` in groups" (fecha parcialmente)
- 2025-10-16, `@rafwell`: *"Its not completed. On version 2025.10.3 its showing the name + lid, the expected is show name + phone number"*
- 2025-10-17, `@devlikepro`: *"now it shows the name at least :)"*
- 2025-10-22, `@devlikepro`: **"required https://github.com/devlikeapro/waha/issues/993"** (bloqueada)
- 2026-05-14, `@rafwell`: *"There is some news about that @devlikepro ?"* — **sem resposta até hoje**

Ou seja: o `{{{participant}}}` da WAHA continuará entregando `Nome (lid@lid)`. **A resolução
LID→telefone é responsabilidade nossa**, e já temos a máquina para isso em 1:1
(`Public::Api::V1::InboxesController#resolve_lid_to_pn:99-110`, `Waha::ApiService#get_lid_phone_number`,
`Contacts::ResolveLidJob`) — só nunca foi apontada para o caminho de grupo.

Contraste com a Evolution API, que **já resolve**:
`chatwoot.service.ts:2090-2092` usa `body.key.participantAlt` quando
`body.key.addressingMode === 'lid'`, ou seja, lê o JID de telefone alternativo direto do payload do
Baileys e imprime `**<telefone> - <nome>:**`. A WAHA não expõe esse campo no app Chatwoot dela.

### Parte III — O que o upstream decidiu

#### Achado 12 — FATO: existe um PR upstream com o desenho completo, e a posição oficial está escrita

**Issue [chatwoot#12693](https://github.com/chatwoot/chatwoot/issues/12693)** — "Feature Request:
Integrate WhatsApp Cloud API for Groups" — **ABERTA**, 27 comentários, labels
`feature-request`, `🐗 Need Product Spec`, `💬 channel/whatsapp`.

Posição oficial, `@sojan-official` (co-fundador), 2026-01-06 — vale citar inteiro porque é a
régua para qualquer coisa que a gente fizer:

> *"From our side, the main preference is: keep this incremental. If the PR can avoid disruptive new
> data models and large migrations, it will be significantly easier for us to review, test, and
> iterate. The **"participants" model was already envisioned as the long-term way to track who's
> involved in a conversation (contacts, agents, bots)**, so I'm more inclined toward building on
> that path (and converting the association to polymorphic if needed).*
>
> *A possible direction to prototype with minimal disruption:*
> - *Treat the **first contact who initiates the group message as the "primary" contact** for the conversation (to satisfy current contact requirements).*
> - *Add a **clear flag + minimal attributes on the conversation** to mark it as a group conversation (and store the group identifier).*
> - *Use **conversation participants** to represent the rest of the group members.*
> - *Get the feature working end-to-end first, even if it requires a few explicit "hacks"…*
>
> *What we want to avoid (at least in the first iteration) is introducing a brand new intermediate
> model (e.g., a conversation_contact layer) or reworking the current contact-inbox/conversation
> linkage…"*

> ⚠️ Nota: o `ConversationParticipant` que existe hoje é **de agentes**, não de contatos —
> `db/schema.rb` `conversation_participants(account_id, user_id, conversation_id)` + modelo
> `app/models/conversation_participant.rb:26-28` (`belongs_to :user`). O termo "participante" já
> está **tomado** no domínio. Se formos nomear algo, evitar `participant` puro para não colidir.

**PR [chatwoot#13361](https://github.com/chatwoot/chatwoot/pull/13361)** — "feat(conversations): add
group conversation support", por `@kshmir`. Estado em 2026-07-27: **aberta, não mergeada**,
`base: develop`, 51 arquivos, +2 244/−141, criada 2026-01-25, último evento 2026-07-23 (bot
"idle for over 30 days" pela 2ª vez). `@sojan-official` em 2026-02-28: *"We haven't had a chance to
properly review this yet, especially since it introduces changes to the database schema."*

**Importante para nós:** `@kshmir` escreveu em 2026-02-06:
> *"I'm starting with this and **integrating it with WAHA**, will give feedback about how it works,
> I'm aiming to make it work as closely as possible to the native WhatsApp experience."*

Ou seja: existe alguém de fora fazendo **exatamente o nosso caso** contra o upstream.

**O DDL do PR (transcrito do branch `refs/pull/13361/head`):**

```ruby
# db/migrate/20260124100001_add_group_fields_to_conversations.rb
add_column :conversations, :group,           :boolean, default: false, null: false
add_column :conversations, :group_source_id, :string
add_column :conversations, :group_title,     :string
add_index  :conversations, :group
add_index  :conversations, %i[inbox_id group_source_id], unique: true,
           where: 'group_source_id IS NOT NULL',
           name: 'index_conversations_on_inbox_id_and_group_source_id'
```

```ruby
# db/migrate/20260124100002_create_group_contacts.rb
create_table :group_contacts do |t|
  t.references :account,      null: false, foreign_key: true
  t.references :conversation, null: false, foreign_key: true
  t.references :contact,      null: false, foreign_key: true
  t.timestamps
end
add_index :group_contacts, %i[conversation_id contact_id], unique: true
```

Mudanças de core relevantes (`app/models/conversation.rb` do PR):

```ruby
validates :contact_id,       presence: true, unless: :group?    # <- contact vira opcional em grupo
validates :contact_inbox_id, presence: true, unless: :group?
scope :group_conversations,     -> { where(group: true) }
scope :non_group_conversations, -> { where(group: false) }
has_many :group_contacts, dependent: :destroy_async
has_many :additional_contacts, through: :group_contacts, source: :contact
def includes_contact?(target) ... end
```

E a atribuição de autor (`app/controllers/public/api/v1/inboxes/messages_controller.rb` do PR):

```ruby
def permitted_params
  params.permit(:content, :echo_id, :sender_identifier)     # <- novo
end

def resolve_sender
  return @contact_inbox.contact if permitted_params[:sender_identifier].blank?
  return @contact_inbox.contact unless @conversation.group?
  sender = @conversation.account.contacts.find_by(identifier: permitted_params[:sender_identifier])
  return @contact_inbox.contact if sender.blank?
  return @contact_inbox.contact unless @conversation.includes_contact?(sender)
  sender
end
```

Front do PR: `bubbles/Base.vue` (+27/−2) mostra o nome do remetente na bolha estilo WhatsApp;
`GroupInfo.vue` (+237) e `GroupMembersModal.vue` (+236) para a lista de integrantes com busca e
paginação; `ConversationHeader.vue` mostra contagem de membros.

**Leitura:** o upstream escolheu **exatamente a combinação B + C-na-conversa** da nossa
enumeração — participante É Contact, `Message#sender` aponta para ele, e a lista de integrantes é
uma tabela de junção presa à **conversa** (não à inbox). E deixou o `group_source_id` na conversa,
resolvendo a fragmentação do Achado 5.

#### Achado 13 — HIPÓTESE FRACA / benchmark: a alternativa "tabela nova" foi analisada e descartada publicamente

`@kshmir` publicou um [gist](https://gist.github.com/kshmir/05599f50a5513208ca811ee42b5528c6) com
3 arquiteturas:

| # | Nome | Modelo | Veredicto do autor |
|---|---|---|---|
| 1 | **Contact Participants** | `conversation_contact_participants` + `is_group/group_source_id/group_name/group_metadata` na conversation; `contact_id` opcional | **escolhida** — "minimal disruption" |
| 2 | **Group Entity** | tabelas `groups`, `group_inboxes`, `group_members`; conversation polimórfica (`contactable_type`) | rejeitada — "need to update all places that reference `conversation.contact`" |
| 3 | **Unified Contact** | `contacts.entity_type` (individual/group) + `contact_memberships(parent_contact_id, member_contact_id)` | rejeitada — "contato fica conceitualmente sobrecarregado" |

Vale registrar que a **Proposta 3 é essencialmente o que a Evolution/WAHA já fazem de facto na
nossa base** (grupo é um Contact), só que sem a tabela de membership — ou seja, estamos na versão
degenerada da opção que o autor classificou como a de pior clareza semântica.

#### Achado 14 — FATO: como os concorrentes resolveram (benchmark)

| Solução | Grupo é | Autor da mensagem | Cria Contact do participante? | LID |
|---|---|---|---|---|
| **WAHA Chatwoot App** (nosso hoje) | Contact (`identifier=<jid>@g.us`, sem phone, source_id UUID) | **texto** no `content` via template `whatsapp.group.message` | não | **vaza** (`Nome (lid@lid)`), issue #1493 aberta |
| **Evolution API** | Contact (`identifier=<jid>@g.us`, `name="<subject> (GROUP)"`) | **texto**: `**<telefone> - <nome>:**\n\n<corpo>` (`chatwoot.service.ts:2099`) | **sim** — `createContact(participantJid…)` (`:757-765`), mas **não** usa como sender | **resolve**: usa `key.participantAlt` quando `addressingMode==='lid'` |
| **Chatwoot upstream (PR 13361)** | `conversations.group=true` + `group_source_id` | **`Message#sender` = Contact do participante**, via `sender_identifier` | sim, e usa como sender | fora de escopo do PR (é Cloud API) |
| **Usuário `@dilutedev`** (issue 12693, relato de produção) | "pseudo-contact" com nome/ícone/ID do grupo, via Channel API | prefixo `[John Doe]` acima do texto | não | — |
| **`@nestordavalos`** (issue 12693) | defende usar o canal WhatsApp nativo em vez do Channel API, com papéis/permissões | — | — | — |

**Padrão:** *todo mundo* que integra via API não-oficial faz grupo = pseudo-contato e autor = texto.
Ninguém resolveu bem. A única modelagem estruturada que existe é o PR upstream, e ele ainda não
foi mergeado.

**Um aprendizado direto da Evolution:** ela **cria Contact para cada participante** e mesmo assim
**continua** injetando o nome no texto — pagando o custo da inflação de contatos **sem colher o
benefício**. Se formos criar contatos de participante, temos de ir até o fim e usá-los como
`sender`; a meio caminho é o pior dos mundos.

---

## Parte IV — As opções de modelagem

> Nomenclatura usada abaixo: **contato-grupo** = o Contact que hoje representa o grupo;
> **participante** = o ser humano que escreveu dentro do grupo.

### Opção A — Grupo = Contact (como hoje) + autor por mensagem em `content_attributes`

```jsonc
// messages.content_attributes
{ "group_sender": { "name": "Rogerio José Da Silva",
                    "lid": "229480102662169@lid",
                    "phone": "+5566...",          // quando resolvido
                    "avatar_url": "https://..." } }
```

- **Migrations:** nenhuma.
- **O que muda:** `permitted_params` + `message_params` no controller público
  (`app/controllers/public/api/v1/inboxes/messages_controller.rb:70-87`, ~6 linhas); strip do
  prefixo `👥 *...*` do `content` na ingestão; render no front (`Message.vue` + bolha).
- **Serialização:** **zero** (Achado 1).
- **Risco de quebrar core:** muito baixo. `content_attributes` é bolsa de gato já usada por
  CSAT, NPS, flows, translations.
- **Busca/filtros/relatórios:** ❌ **ruim** — não indexável, e ainda por cima o campo tem
  gravação inconsistente (Achado 8: 2 166 linhas são string JSON). Não dá para "filtrar mensagens
  do Rogério" nem relatar por participante.
- **Contagem de contatos:** ✅ **nenhum impacto** (nenhum Contact novo).
- **IA/Captain:** melhora indireta — dá para o formatter montar `"<Nome>: <texto>"` em vez de
  `"User: 👥 *Nome (lid@lid)* texto"`. Exige tocar
  `app/services/llm_formatter/conversation_llm_formatter.rb:84`.
- **Automações/Flow:** neutro. As condições rodam sobre `message.content`/labels; limpar o
  `content` do prefixo até **melhora** matching de keyword.
- **Merge de contatos:** ✅ imune (não há contato de participante para merjar).
- **Reversibilidade:** ✅ **total** — é só parar de escrever a chave.
- **Não resolve:** lista de integrantes; @menção; atribuição por pessoa; fragmentação do grupo
  em N conversas (Achado 5).

### Opção B — Participante é Contact e vira `Message#sender`

- **Migrations:** nenhuma **obrigatória** (o polimorfismo já aceita Contact — Achado 2); na prática
  quer `conversations.group` para saber quando aplicar.
- **O que muda:** ingestão passa a resolver/criar o Contact do participante e passar
  `sender_identifier` (padrão upstream); front já sabe renderizar `sender` (avatar/nome vêm de
  `push_event_data`).
- **Risco de quebrar core:** ⚠️ **médio-alto**, e o ponto mais afiado é este:
  `app/builders/contact_inbox_with_contact_builder.rb:125-146` (`find_and_migrate_waha_lid_to_pn`)
  varre **todos** os `contact_inboxes` com `source_id LIKE '%@lid'` da inbox a cada contato novo e,
  se casar telefone, faz `ci.update!(source_id: source_id)` — **reescrevendo o `source_id` do
  contact_inbox do participante** quando a mesma pessoa abrir um 1:1. Pode ser feature (unifica
  pessoa) ou bug (destrói o vínculo de participante), dependendo de como o participante for
  ancorado. Além disso o `find_each` vira O(N) por contato criado.
- **Busca/filtros:** ✅ **ótimo** — `index_messages_on_sender_type_and_sender_id` já existe;
  `SearchService#parse_from_param` (`app/services/search_service.rb:144-155`) passa a funcionar
  dentro de grupos.
- **Contagem de contatos:** ❌ **infla**. `Contact.resolved_contacts`
  (`app/models/contact.rb:183-187`) conta qualquer contato com email **ou** phone **ou**
  `identifier` não vazio — o participante tem `identifier`, então **entra na lista de Contatos, nos
  exports (`app/jobs/account/contacts_export_job.rb`) e nos públicos de campanha**.
  *Nuance honesta:* **não achei nenhum limite de licenciamento por contato neste fork** —
  `Account#usage_limits` (`app/models/account.rb:221`) e
  `enterprise/.../plan_usage_and_limits.rb:7` limitam **agents, inboxes e Captain
  (documents/responses)**, não contatos. O impacto é **operacional/comercial-percebido** (poluição
  da base, export, audiência de campanha, CRM), **não** cobrança. Medição atual: dos 1 807
  contatos com `identifier LIKE '%@s.whatsapp.net'` (criados pela Evolution), **10 não têm
  conversa nenhuma** — inflação medida baixa (0,5%), mas com volume de grupo baixo.
- **IA/Captain:** ✅ melhora bastante — o formatter passa a distinguir humanos;
  `enterprise/lib/captain/conversation_eval_service.rb:151` e
  `app/services/llm_formatter/conversation_llm_formatter.rb:84` ganham granularidade.
- **Automações/Flow:** ⚠️ **atenção** — `app/listeners/automation_rule_listener.rb:285`
  (`message.sender_type == 'User'`) segue OK, mas regras que assumem
  `message.sender == conversation.contact` mudam de comportamento.
- **Merge de contatos:** ⚠️ `ContactMergeAction#merge_messages`
  (`app/actions/contact_merge_action.rb:50`) faz
  `Message.where(sender: mergee).update_all(sender_id: base…)` — **funciona e é até desejável**
  (participante e o 1:1 dele viram um contato só, histórico consolidado). O risco é o inverso:
  `ContactIdentifyAction` (`app/actions/contact_identify_action.rb:37-45`) mergeia por
  **phone_number**, então o participante recém-resolvido pode ser fundido com um contato 1:1
  **antes** de a gente querer — e aí o nome do contato 1:1 sobrescreve o nome do grupo, etc.
- **Reversibilidade:** ⚠️ **baixa** — depois que N mensagens apontam para contatos de
  participante, voltar exige `UPDATE` em massa e decidir o que fazer com os contatos criados.

### Opção C — Tabela nova `whatsapp_group_participants`, sincronizada por job

Ancorada em **conversation** (como o upstream) ou em **inbox+group_jid**.

- **Migrations:** 1 tabela (+ provavelmente `conversations.group_source_id` para ancorar).
- **Fonte de dados:** a WAHA **tem** o endpoint —
  `GET /api/{session}/groups/{groupId}/participants/v2` → `[{ "id": "111…@c.us", "role": "participant|admin|superadmin|left" }]`
  (docs WAHA "Groups"). Hoje **não existe** método para isso em `app/services/waha/api_service.rb`
  (o `get_groups` só é chamado como efeito colateral para aquecer o mapa LID→PN em
  `app/jobs/waha/refresh_groups_job.rb`).
- **Risco de quebrar core:** ✅ **baixíssimo** — tabela satélite, nada do core lê.
- **Busca/filtros/relatórios:** ✅ boa base para relatório "quem mais fala no grupo" — **mas só se
  combinada com A ou B**, porque sozinha ela não diz **quem escreveu cada mensagem**.
- **Contagem de contatos:** ✅ **zero impacto** se a tabela guardar `{jid, lid, name, role,
  avatar_url}` sem criar Contact.
- **IA/Automações/Merge:** neutros.
- **Reversibilidade:** ✅ alta (drop table).
- **Custo escondido:** sincronização. Grupo muda de membro sem avisar; precisa de job periódico +
  reconciliação, e a WAHA precisa estar de pé (já temos watchdog e circuit breaker, ver
  `deployment/waha-watchdog/`).
- **Divergência do upstream:** ⚠️ se o PR 13361 entrar com `group_contacts`, teríamos duas
  tabelas concorrentes. Mitigação: **usar o nome e o shape do upstream** (`group_contacts`, com
  `contact_id`) ou aceitar a divergência conscientemente.

### Opção D — Snapshot JSON da lista em `conversation.additional_attributes`

```jsonc
// conversations.additional_attributes
{ "waha_group": { "jid": "1203…@g.us", "subject": "TI TOZI - Inovação",
                  "synced_at": "2026-07-27T10:00:00Z",
                  "participants": [ { "lid": "…@lid", "phone": "+55…", "name": "…", "role": "admin" } ] } }
```

- **Migrations:** nenhuma.
- **Serialização:** **zero** — já vai para REST (`_conversation.json.jbuilder:117`), websocket e
  webhook (`event_data_presenter.rb:4`).
- **Risco de quebrar core:** baixo, **com uma ressalva**: existe índice GIN em
  `conversations ((additional_attributes -> 'user_settings'))`; um blob grande de participantes
  engorda a linha e todo payload de conversa (a conversa inteira trafega em cada
  `conversation.updated`). Grupo de 200 pessoas = payload gordo em toda atualização.
- **Busca/filtros/relatórios:** ❌ ruim (mesma limitação de A).
- **Contagem de contatos:** ✅ zero.
- **Reversibilidade:** ✅ total.
- **Bom para:** MVP visual da lista de integrantes. **Ruim para:** grupos grandes, histórico de
  entrada/saída, qualquer consulta.

### Opção E — Híbrido (o que eu recomendo; ver seção "Recomendação")

`A` (autor por mensagem, agora) **+** `conversations.group/group_source_id` (identidade do grupo,
espelhando o upstream) **+** `D→C` (lista de integrantes: snapshot primeiro, tabela depois)
**+** `B` só na fase final, quando LID→telefone estiver resolvido.

### Opção F — Grupo é uma **Inbox** (descartada, registro para não voltar ao assunto)

Modelar cada grupo como uma inbox própria daria isolamento perfeito de equipe/automação, mas:
`usage_limits[:inboxes]` é limite real de plano (`app/models/account.rb:221`,
`enterprise/.../plan_usage_and_limits.rb:9`), cada inbox exige canal/credencial, e a UI de inboxes
não escala para dezenas de grupos. **Não seguir.**

### Tabela comparativa

Legenda: ✅ bom · ⚠️ atenção · ❌ ruim · — neutro/não se aplica

| Critério | **A** `content_attributes` | **B** participante=Contact+sender | **C** tabela `group_contacts` | **D** snapshot em `conversation` | **E** híbrido faseado |
|---|---|---|---|---|---|
| Migrations | **0** | 0 obrigatória (1 recomendada) | 1 tabela (+1 coluna) | **0** | 1 tabela + 3 colunas, **faseadas** |
| Esforço | **P** (~1 sem) | G (3–6 sem) | M (1–2 sem) | **P** (~3 dias) | M, mas entrega valor na 1ª semana |
| Risco de quebrar core | ✅ muito baixo | ⚠️ **médio-alto** (builder LID, identify/merge) | ✅ baixíssimo | ✅ baixo (payload gordo) | ✅ risco concentrado na fase 3 |
| Serializers a mexer | **nenhum** | nenhum | 1 novo endpoint | **nenhum** | mínimo |
| Diz **quem escreveu cada msg** | ✅ | ✅ | ❌ | ❌ | ✅ (fase 1) |
| Dá a **lista de integrantes** | ❌ | parcial (só quem falou) | ✅ | ✅ | ✅ (fase 2/3) |
| Busca / filtro por autor | ❌ (jsonb não indexado + gravação inconsistente) | ✅ (índice já existe) | ⚠️ (só agregado) | ❌ | ✅ (fase 3) |
| Relatórios por participante | ❌ | ✅ | ⚠️ | ❌ | ✅ (fase 3) |
| **Contagem de contatos** | ✅ **não infla** | ❌ **infla** (entra em `resolved_contacts`, export, campanhas) | ✅ não infla | ✅ não infla | ✅ só infla na fase 3, conscientemente |
| Impacto comercial/licenciamento | — | ⚠️ **percebido**, não cobrado (não há limite de contatos neste fork) | — | — | controlado |
| IA / Captain | ✅ melhora (texto limpo) | ✅✅ melhor (autor distinto) | — | — | ✅✅ |
| Automações / Flow | ✅ melhora matching | ⚠️ muda semântica de `sender` | — | — | ✅ com guards explícitos |
| Merge de contatos | ✅ imune | ⚠️ identify por telefone pode fundir cedo demais | ✅ imune | ✅ imune | ⚠️ tratado na fase 3 |
| Reversibilidade | ✅ total | ❌ baixa | ✅ alta (drop) | ✅ total | ✅ até a fase 2 |
| Alinhado ao upstream (PR 13361) | parcial | ✅ **é o desenho deles** | ✅ (mesmo nome/shape) | ❌ | ✅ |
| Conserta fragmentação (Achado 5) | ❌ | ❌ | ✅ se usar `group_source_id` | ❌ | ✅ (fase 2) |

---

## Riscos e efeitos colaterais investigados no código

### R1 — CSAT e NPS disparando em grupo: **já aconteceu** (FATO)

```sql
SELECT count(*) FILTER (WHERE m.content_type=9)                            AS csat_em_grupo,
       count(*) FILTER (WHERE m.content_attributes::text LIKE '%nps_survey%') AS nps_em_grupo
FROM messages m JOIN conversations cv ON cv.id=m.conversation_id
JOIN contacts c ON c.id=cv.contact_id WHERE c.identifier LIKE '%@g.us';
--  csat_em_grupo=15   nps_em_grupo=2
```

Uma delas gravada com `content_attributes = {"nps_survey":true,"external_error":"404 Not Found"}` —
tentou enviar e falhou. E `nps_responses` tem **2 linhas** cujo `contact_id` é um contato-grupo.

Nenhum guard existe:
- `app/listeners/csat_survey_listener.rb:3-13` → dispara em `conversation.resolved?`.
- `app/services/csat_survey_service.rb:26-30` → `conversation_allows_csat?` só exclui **tweet**.
- `app/listeners/nps_survey_listener.rb:2-15` → idem, só checa `inbox.nps_survey_enabled?`.
- `app/services/message_templates/hook_execution_service.rb:26-46` → Greeting e Out-of-Office
  também só excluem tweet e campanha. **Mensagem de boas-vindas cai no grupo inteiro.**

> Este é o argumento mais forte para a Fase 1 ter um **predicado `conversation.group?` de primeira
> classe**: hoje não existe um lugar único para perguntar "isso é grupo?", e por isso ninguém
> pergunta.

### R2 — Captain respondendo em grupo: o router **não basta** (FATO)

Confirmado no Achado 3: `skip_groups` é opt-in. Nesta base não há mensagem
`sender_type='Captain::Assistant'` em conversa de grupo — mas isso é sorte de configuração, não
proteção. Além disso a detecção lê `contact.identifier` / `custom_attributes` — e o contato-grupo
**do dump (id 24) não tem `waha_whatsapp_chat_id`**, só o `identifier`; se algum grupo chegar sem
`identifier` populado, a detecção falha silenciosamente.

**Insuficiente também porque:** mesmo bloqueando a resposta, o Captain continua **lendo** o texto
sujo. `app/services/llm_formatter/conversation_llm_formatter.rb:84-93` etiqueta todo Contact como
`"User:"` — a IA recebe `User: 👥 *Rogerio José Da Silva (229480102662169@lid)* quando cheegar…`.
Isso contamina resumo, avaliação (`enterprise/lib/captain/conversation_eval_service.rb:151`) e
sugestão de label (`lib/captain/label_suggestion_service.rb:72`).

### R3 — Merge / identify de contatos (FATO + risco projetado)

- `ContactMergeAction` (`app/actions/contact_merge_action.rb`) move `conversations`, `messages`
  (por `sender`, `:50`), `notes`, `nps_responses`, `csat_survey_responses` e faz `deep_merge` de
  `additional_attributes`/`custom_attributes` com **preferência para o base**. Se um dia um grupo
  for mergeado com outro contato, `waha_whatsapp_chat_id` pode ser sobrescrito.
- `ContactIdentifyAction:37-45` mergeia por `identifier`, `email` **e `phone_number`**. Na
  Opção B, o participante ganha telefone quando o LID for resolvido → **merge automático** com o
  contato 1:1 da mesma pessoa. Isso é o comportamento desejado (histórico unificado), **mas** é
  irreversível e acontece sem intervenção.
- `ContactInboxWithContactBuilder#find_and_migrate_waha_lid_to_pn:125-146` — descrito no risco da
  Opção B: reescreve `source_id` de contact_inbox `@lid`. Com participantes ancorados em
  contact_inbox, isso os sequestra.

### R4 — Automações / Flow disparando por mensagem de grupo (FATO)

`app/listeners/automation_rule_listener.rb:38-45` (`message_created`) e `:403-407`
(`ignore_message_created_event?`) filtram: automação própria, activity, auto-reply de e-mail,
mensagem gerada por flow (`content_attributes['flow_id']`) e tráfego de NPS. **Nada sobre grupo.**
`run_flows`/`run_keyword_flows` (`:97-122`) rodam normalmente numa conversa de grupo.

Riscos concretos: (a) o prefixo `👥 *Nome (lid@lid)*` está **dentro do `content`**, então uma regra
de keyword `contains "parar"` pode casar com um nome; (b) `OPT_OUT_KEYWORDS` (`:6`) — se alguém no
grupo escrever "PARAR", o **grupo inteiro** é descadastrado; (c) flows de boas-vindas/LGPD
disparam para o grupo.

### R5 — Relatórios e contagem (FATO, impacto médio)

- **Conversas:** cada grupo conta como conversa normal, e com a fragmentação do Achado 5 conta
  **8–11× a mais** do que deveria. Isso já distorce os números hoje, independente de participante.
- **Contatos:** `Contact.resolved_contacts` (`app/models/contact.rb:183-187`) inclui contatos-grupo
  (têm `identifier`), então os 36 grupos **já estão contados como contatos** na tela de Contatos e
  no export.
- **Agentes:** `app/builders/v2/reports/outgoing_messages_count_builder.rb:22` conta
  `sender_type='User'` — as 3 987 respostas de agente em grupo entram normalmente. Correto.
- **Primeira resposta / SLA:** `app/listeners/reporting_event_listener.rb:194` usa
  `sender_type='User'`. Em grupo, "primeira resposta" fica semanticamente estranha (respondeu a
  quem?), mas não quebra.

### R6 — Envio de saída para o grupo (FATO — bug já existente)

Achado 7: texto simples funciona (webhook → app externo); **interativo/enquete/localização/vCard
levanta exceção** porque `Waha::OutboundSpecialMessageService#chat_id:90-107` só olha
`contact_inbox.source_id` (UUID) e `contact.phone_number` (vazio), ignorando
`custom_attributes['waha_whatsapp_chat_id']` que `Messages::WahaMessageResolvable#chat_id:176-188`
usa corretamente. **Correção de 3 linhas, independente de toda a modelagem** — vale como quick win.

### R7 — Normalização brasileira do nono dígito aplicada a participantes (FATO + risco)

`Contacts::BrazilPhoneNormalizer` (`app/services/contacts/brazil_phone_normalizer.rb`) adiciona o
"9" quando o número BR tem 10 dígitos pós-`+55`, **exceto fixo** (primeiro dígito 2–5,
`LANDLINE_FIRST_DIGITS:16`). Hoje ela roda em: criação de contato
(`ContactInboxWithContactBuilder#find_contact_by_phone_number:105-116`), normalização de LID
(`Public::Api::V1::InboxesController#normalize_waha_phone_number:147-153`) e `ResolveLidJob`.

Se participantes virarem Contact (Opção B), **eles passam pela mesma normalização** — o que é bom
(dedup com o 1:1) e perigoso (números antigos de DDDs sem o 9 podem colidir com um contato
existente). Estado atual da base: **apenas 1** telefone duplicado em toda a base
(`GROUP BY phone_number, account_id HAVING count(*)>1` → 1) — a normalização está funcionando bem
hoje, e o volume de participantes ainda é zero.

### R8 — `getSafeContactName` é código morto (FATO)

`app/javascript/dashboard/helper/commons.js:129-156` define `isUnresolvedLid` e
`getSafeContactName`, feitos exatamente para mascarar LID na UI. `grep` em `app/javascript/` mostra
**zero chamadas** fora do próprio arquivo. Alguém já começou este trabalho e parou.

---

## Recomendação

**Opção E — híbrido faseado, alinhado ao PR upstream 13361.**

Por quê, em uma frase: *A tem o melhor custo/benefício imediato e é 100% reversível; o desenho
final tem de ser o do upstream (B+C na conversa), senão a gente diverge e paga merge caro depois;
e o passo caro (participante=Contact) depende de uma coisa que ainda não temos — LID→telefone
confiável — então ele vai por último.*

### Fase 0 — Parar o sangramento · custo ≈ 0 · dias

| | |
|---|---|
| **Entrega ao usuário** | O `(lid@lid)` some do texto visível. O nome do participante continua aparecendo. |
| **Exige** | (a) editar o template de linguagem da WAHA `whatsapp.group.message` (Achado 10) — **configuração, não código**; (b) uma limpeza dos nomes fósseis `(GROUP)` → `(Grupo)` ou remoção do sufixo, opcional; (c) **quick win independente:** corrigir `OutboundSpecialMessageService#chat_id` para preferir `waha_whatsapp_chat_id` (R6). |
| **NÃO resolve** | as 514 mensagens **já gravadas** com o LID (ficam no histórico); a lista de integrantes; nada estrutural. |
| **Pegadinha** | o `{{{participant}}}` da WAHA é **atômico** — não dá para pedir só o nome. Se o template mandar só `{{{text}}}`, perde-se o autor. **Verificar com W1/W2 se a WAHA expõe variáveis separadas**; se não expuser, Fase 0 vira "strip no ingest" (abaixo) em vez de config. |

### Fase 1 — Autor estruturado por mensagem (Opção A) · 1–2 semanas · **zero migration**

| | |
|---|---|
| **Entrega** | Cada mensagem de grupo mostra **nome + avatar do participante** na bolha, estilo WhatsApp. Texto limpo. CSAT/NPS/greeting param de cair no grupo. Captain para de ler lixo. |
| **Exige** | 1. Predicado único `Conversation#group?` (por ora lendo `contact.identifier.end_with?('@g.us')`), usado por **todos** os guards — resolve R1, R2, R4 num lugar só.<br>2. `permit(:content_attributes)` ou `:group_sender` no controller público (`messages_controller.rb:70-87`) **+** strip do prefixo `👥 *...*` do `content` na ingestão.<br>3. Resolver LID→telefone **no caminho de grupo**, reusando o que já existe para 1:1 (`resolve_lid_to_pn`, `Waha::ApiService#get_lid_phone_number`, `Contacts::ResolveLidJob`).<br>4. Render: estender o ramo `additionalAttributes.senderName` de `Message.vue:750-757` para valer também quando há sender e a conversa é grupo (Achado 6); ativar o `getSafeContactName` morto (R8).<br>5. Guards: `csat_survey_service.rb:26`, `nps_survey_listener.rb:4`, `hook_execution_service.rb:26,42`, `automation_rule_listener.rb:403`, e ligar `skip_groups` por padrão no Captain.<br>6. `conversation_llm_formatter.rb:84` passa a emitir `"<Nome do participante>: <texto>"`. |
| **NÃO resolve** | lista de integrantes; busca/relatório por participante (jsonb não indexável — Achado 8); a fragmentação do grupo em N conversas. |
| **Reversível?** | Sim, integralmente. |

**Escolha deliberada:** guardar em `content_attributes.group_sender` (e **não** em
`additional_attributes`) porque `content_attributes` já é o balde de metadado-de-conteúdo do
Chatwoot e o front já o recebe. Mas **assumir desde já que é campo de exibição, nunca de consulta.**

### Fase 2 — Identidade do grupo de primeira classe · 1 semana · 1 migration pequena

| | |
|---|---|
| **Entrega** | Um grupo = **uma** conversa (fim dos 8–11 duplicados). Header mostra "Grupo · N membros". Lista de integrantes visível (snapshot). |
| **Exige** | 1. **Copiar o DDL do upstream, literalmente**: `conversations.group:boolean`, `group_source_id:string`, `group_title:string` + índice único parcial `(inbox_id, group_source_id) WHERE group_source_id IS NOT NULL` (Achado 12). Isso mata a fragmentação do Achado 5 na raiz.<br>2. `Conversation#group?` deixa de ser heurística e passa a ler a coluna.<br>3. Novo método `Waha::ApiService#get_group_participants(session, group_id)` → `GET /api/{session}/groups/{groupId}/participants/v2`.<br>4. Job periódico grava snapshot em `conversation.additional_attributes['waha_group']` (**Opção D**) — serialização de graça.<br>5. Backfill: popular `group`/`group_source_id` nas 36 conversas-grupo existentes a partir de `contacts.identifier`; decidir política de consolidação das conversas duplicadas (**merge é destrutivo — decisão de produto, não técnica**). |
| **NÃO resolve** | busca/filtro por participante; atribuição; @menção; histórico de entrada/saída de membros. |
| **Reversível?** | Sim (as colunas podem ficar sem uso; o snapshot é descartável). |
| **Ganho estratégico** | A partir daqui estamos **no mesmo shape do PR 13361**. Se o upstream mergear, nosso merge é quase trivial. |

### Fase 3 — Participante como Contact (Opção B + C) · 3–6 semanas · **só depois de a Fase 1 provar que o LID resolve**

| | |
|---|---|
| **Entrega** | Busca "mensagens do Rogério"; relatório por participante; avatar/histórico compartilhados com o 1:1 da mesma pessoa; base para @menção e atribuição. |
| **Exige** | 1. Tabela `group_contacts(account_id, conversation_id, contact_id)` com unique `(conversation_id, contact_id)` — **mesmo nome e shape do upstream**.<br>2. `sender_identifier` no controller público, com o mesmo `resolve_sender` do PR (busca por `contacts.identifier` + `conversation.includes_contact?`).<br>3. Blindar `find_and_migrate_waha_lid_to_pn` (`contact_inbox_with_contact_builder.rb:125-146`) contra sequestrar contact_inbox de participante.<br>4. Política explícita de merge: quando o participante ganha telefone, `ContactIdentifyAction` funde com o 1:1 — **decidir se é automático ou fila de revisão**.<br>5. Decidir a marcação dos contatos de participante (`custom_attributes['origin']='group_participant'`?) para poder **excluí-los de exports e públicos de campanha** — mitigação direta da inflação. |
| **NÃO resolve** | envio de mensagem interativa para grupo (é R6, resolver na Fase 0); permissões/papéis de admin do grupo; grupos com centenas de membros (paginação já prevista pelo upstream, 100/página). |
| **Reversível?** | **Não** na prática. Por isso é a última. |
| **Gatilho de GO** | só entrar se, ao fim da Fase 1, a taxa de LID resolvido para telefone for alta. Se o LID continuar irresolvível (issue WAHA #993), participante=Contact cria contatos sem telefone que **nunca** consolidam com o 1:1 — aí a Fase 3 só traz o custo (inflação) sem o benefício (histórico unificado). **Foi exatamente esse erro que a Evolution API cometeu** (Achado 14). |

### O que eu **não** recomendo, e por quê

- **Pular direto para a Fase 3.** É o que o instinto pede ("faz direito de uma vez"), mas o
  benefício central de participante=Contact é consolidar com o 1:1, e isso **depende do telefone**,
  que depende do LID, que a WAHA não resolve (Achado 11). Sem isso, é inflação pura.
- **Inventar tabela/naming próprios** (ex.: `whatsapp_group_participants`). O upstream já publicou
  `group_contacts` + `conversations.group*`. Divergir custa merge caro para sempre e não compra nada.
- **Usar `additional_attributes['type'] = 'group'`** como sinal. O comentário no
  `router_service.rb:32` sugere que é padrão do Chatwoot — **não é** (Achado 3). O upstream usa
  coluna booleana.
- **Grupo como Inbox** (Opção F) — bate em limite de plano.
- **Esperar o upstream mergear.** O PR está parado desde jan/2026, com dois alertas de
  inatividade e uma resposta de "não tivemos chance de revisar". Alinhar sim, esperar não.

---

## Lacunas / o que não consegui verificar

1. **NÃO CONFIRMADO — quais variáveis o template `whatsapp.group.message` da WAHA aceita além de
   `{{{participant}}}` e `{{{text}}}`.** A doc pública (`waha.devlike.pro/docs/apps/chatwoot/`)
   remete a `src/apps/chatwoot/i18n/locales` do **WAHA Plus**, que é fonte fechada. Se existir
   `{{{participant.name}}}` separado do id, a Fase 0 resolve sozinha. **Isso é do escopo do W1/W2
   e é a incógnita mais barata de fechar** — vale um GET na instância WAHA de homologação.
2. **NÃO CONFIRMADO — se o ambiente do dump do usuário (Tozi PROD, `.109`) tem exatamente os mesmos
   dados.** Todas as minhas medições são da base **desta VM de homologação**. Os padrões batem
   (existe `TI TOZI - Inovação (GROUP)` id=24 aqui), mas a última mensagem `👥` local é de
   **2026-05-02** e o dump do usuário é de **hoje, 27/07**. Portanto os números (514 msgs, 36
   grupos, 15 CSAT, 2 NPS) valem para homologação e são **indicativos**, não medidos, para produção.
   Não tenho autorização para SSH em `.109` — por desenho.
3. **NÃO CONFIRMADO — se a WAHA envia `source_id` na criação do contato-grupo.** Deduzi que não
   (100% UUID, e a Evolution comprovadamente não envia), mas não observei um POST real. Confirmar
   com W1/W3 fecharia a causa raiz da fragmentação com certeza total.
4. **NÃO CONFIRMADO — a causa exata do double-encoding de `content_attributes`** (Achado 8). O
   fato (2 166 linhas string) é medido; a atribuição ao `store ..., coder: JSON` é hipótese.
5. **Não medi o custo de sincronização de participantes** (quantas chamadas/dia ao
   `/groups/{id}/participants/v2` para N grupos, e o impacto no circuit breaker já existente da
   WAHA). Fica para a Fase 2.
6. **Não avaliei o app móvel.** Todas as afirmações de front são sobre `app/javascript/dashboard`.
   O mobile consome os mesmos jbuilders, então A e D chegam lá também — mas o **render** é outro
   código, fora deste repositório.
7. **Não li o diff completo do front do PR 13361** (`GroupInfo.vue`, `GroupMembersModal.vue`,
   `bubbles/Base.vue`) — só a lista de arquivos e o descritivo. Se formos para a Fase 2/3, ler
   esses 500 linhas antes de escrever qualquer coisa nossa economiza dias.

---

## Implicações para a solução

**Habilita:**
- Um ganho visível em **dias**, sem tocar em banco (Fase 0 + strip de prefixo).
- Um caminho estruturado que **não briga com o core** e que, se o upstream mergear, converge em vez
  de conflitar.
- Um lugar único para perguntar "isso é grupo?" — que hoje não existe e é a causa direta de os
  15 CSAT e 2 NPS terem caído em grupos.

**Impede / condiciona:**
- Enquanto o LID não resolver para telefone, **participante=Contact é ruim negócio**. A decisão de
  Fase 3 é **condicional a uma métrica**, não a um cronograma.
- Enquanto o `source_id` do grupo for UUID, **nenhum relatório sobre grupos é confiável** — o mesmo
  grupo aparece 8–11 vezes. A Fase 2 é pré-requisito de qualquer conversa sobre métrica de grupo.
- `content_attributes` **não é** substrato para filtro/relatório (Achado 8). Quem prometer
  "filtrar por participante" na Fase 1 vai ter de voltar atrás.

**Decisões que precisam de dono (não são técnicas):**
1. As 8–11 conversas duplicadas por grupo: **consolidar (destrutivo) ou deixar e só parar de criar
   novas?**
2. Contatos de participante entram nos públicos de campanha e no export de contatos, ou são
   marcados e excluídos?
3. Quando o participante ganhar telefone e casar com um contato 1:1 existente: **merge automático
   ou fila de revisão?**

---

## Referências

**Código deste repositório** (`/home/chatwoot/chatwoot`, branch `homologacao`)
- `app/models/message.rb:118` (store content_attributes), `:141` (sender polimórfico), `:161`
  (push_event_data), `:240,404` (tipos de sender), `:519`
- `app/models/contact.rb:50-54` (validações), `:152-165` (push_event_data), `:183-187`
  (`resolved_contacts`)
- `app/models/conversation.rb:285` (`additional_attributes['type']=='tweet'`)
- `app/models/conversation_participant.rb:19-28` (participante = **User**, nome já tomado)
- `db/schema.rb` — `contacts`, `contact_inboxes`, `conversations`, `messages`, `conversation_participants`
- `app/controllers/public/api/v1/inboxes/contacts_controller.rb:8` (`SecureRandom.uuid`)
- `app/controllers/public/api/v1/inboxes/messages_controller.rb:70-72,78-87` (sender hardcoded)
- `app/controllers/public/api/v1/inboxes_controller.rb:35-75` (normalização LID), `:99-110`
  (`resolve_lid_to_pn`), `:112-145` (merge LID→PN), `:181-196` (`sanitize_waha_contact_name`)
- `app/builders/contact_inbox_with_contact_builder.rb:98-116`, `:125-146`
- `app/actions/contact_merge_action.rb:36-50`, `app/actions/contact_identify_action.rb:31-45`
- `app/listeners/csat_survey_listener.rb:3-13`, `app/services/csat_survey_service.rb:22-30`
- `app/listeners/nps_survey_listener.rb:2-15`
- `app/services/message_templates/hook_execution_service.rb:18-46`
- `app/listeners/automation_rule_listener.rb:6`, `:38-45`, `:97-122`, `:285`, `:403-415`
- `app/listeners/webhook_listener.rb:141-146`; `app/presenters/conversations/event_data_presenter.rb:2-38`
- `app/services/waha/outbound_special_message_service.rb:90-107` (chat_id quebrado p/ grupo)
- `app/services/messages/waha_message_resolvable.rb:176-188` (chat_id correto)
- `app/services/llm_formatter/conversation_llm_formatter.rb:84-93`;
  `enterprise/lib/captain/conversation_eval_service.rb:151`; `lib/captain/label_suggestion_service.rb:72`
- `app/services/contacts/brazil_phone_normalizer.rb:7-33`
- `app/services/search_service.rb:144-155`; `app/builders/v2/reports/outgoing_messages_count_builder.rb:22`;
  `app/listeners/reporting_event_listener.rb:194`
- `app/models/account.rb:221`; `enterprise/app/models/enterprise/account/plan_usage_and_limits.rb:7-16`
- `enterprise/app/services/captain/behavior/router_service.rb:14-48`;
  `spec/enterprise/services/captain/behavior/router_service_spec.rb:33-67`
- `app/views/api/v1/models/_message.json.jbuilder:9,17`;
  `app/views/api/v1/conversations/partials/_conversation.json.jbuilder:117,120`
- `app/javascript/dashboard/components-next/message/Message.vue:750-757`;
  `app/javascript/dashboard/helper/commons.js:129-156` (código morto)
- `db/migrate/20251202210211_add_waha_session_name_to_inboxes.rb` (marco temporal WAHA)

**Consultas ao banco** (SELECT, base local `chatwoot_production` da VM 192.168.8.232, 2026-07-27)
- 36 contatos-grupo; 114 contact_inboxes de grupo, **100% UUID**; TI TOZI = 9 CI / 8 conversas
- 514 mensagens com prefixo `👥` (2025-12-03 → 2026-05-02); 548 com `@lid`, em 12 conversas
- sender em conversas de grupo: Contact 5 494 · User 3 987 · nulo 299
- **15 CSAT + 2 NPS disparados em grupo**; 2 `nps_responses` com `contact_id` de grupo
- sufixos: `(GROUP)` 24× (jul–ago/2025) · `(Group)` 9× (dez/2025) · `(Grupo)` 3× (nov/2025–fev/2026)
- `jsonb_typeof(content_attributes)`: object 30 250 · **string 2 166**
- 1 807 contatos com `identifier LIKE '%@s.whatsapp.net'`, **10 sem conversa**
- 1 telefone duplicado em toda a base

**Chatwoot upstream**
- Issue [#12693](https://github.com/chatwoot/chatwoot/issues/12693) — *Integrate WhatsApp Cloud API for Groups* — **ABERTA**, `🐗 Need Product Spec`. Posição oficial de `@sojan-official` (2026-01-06).
- PR [#13361](https://github.com/chatwoot/chatwoot/pull/13361) — *feat(conversations): add group conversation support* — **ABERTA**, 51 arquivos, +2244/−141, parada desde jan/2026.
- Gist de `@kshmir`: [3 alternativas de arquitetura](https://gist.github.com/kshmir/05599f50a5513208ca811ee42b5528c6)
- Issue [#10996](https://github.com/chatwoot/chatwoot/issues/10996) — *WhatsApp Group Messages* — fechada **`not_planned`** (fev/2025)
- Issue [#316](https://github.com/chatwoot/chatwoot/issues/316) — *[Feature] group conversations* — fechada `completed` (out/2023) → entregou `conversation_participants` (**agentes**), não grupos de cliente
- Issue [#13389](https://github.com/chatwoot/chatwoot/issues/13389) — *add Official WhatsApp Groups API* — fechada (jan/2026), duplicada de #12693

**WAHA**
- Issue [#1369](https://github.com/devlikeapro/waha/issues/1369) — *Contact name in groups above message* — **fechada/completed**, origem do template `👥 *{{{participant}}}*`, default desde `2025.9.5`
- Issue [#1493](https://github.com/devlikeapro/waha/issues/1493) — *Group participant — show phone number instead of @lid* — **ABERTA desde out/2025**, bloqueada pela [#993](https://github.com/devlikeapro/waha/issues/993), sem resposta desde mai/2026
- Issue [#1767](https://github.com/devlikeapro/waha/issues/1767) — *Mentions support for group messages* — **entregue** (`@all` e `@123@lid`)
- Issue [#1173](https://github.com/devlikeapro/waha/issues/1173) — *'phone_number should be in e164 format' → 'Contact not found' (group messages)*
- Docs: [Chatwoot App](https://waha.devlike.pro/docs/apps/chatwoot/) · [Groups API](https://waha.devlike.pro/docs/how-to/groups/) (`GET /api/{session}/groups/{groupId}/participants/v2` → `[{id, role}]`, role ∈ `left|participant|admin|superadmin`)

**Evolution API** (benchmark — fonte lida diretamente do HEAD via API do GitHub)
- `src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts:290-330` (`createContact`, `isGroup`),
  `:726-800` (criação do contato-grupo e do participante), `:731-737` (**`${group.subject} (GROUP)`**),
  `:2087-2100` e `:2269-2280` (prefixo `**<telefone> - <nome>:**` e uso de `key.participantAlt` quando `addressingMode === 'lid'`)
- Issues correlatas: [#1811](https://github.com/EvolutionAPI/evolution-api/issues/1811),
  [#1834](https://github.com/EvolutionAPI/evolution-api/issues/1834),
  [#319](https://github.com/EvolutionAPI/evolution-api/issues/319),
  [#1166](https://github.com/EvolutionAPI/evolution-api/issues/1166)
