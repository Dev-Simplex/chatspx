# W4 — Diagnóstico empírico em homologação: o dado real, o payload real, a resposta real da WAHA

> Executado em 2026-07-27 na VM `192.168.8.232` (homologação). **Somente leitura**: banco em sessão
> PostgreSQL com `default_transaction_read_only=on` (bloqueio verificado), WAHA somente `GET`,
> zero SSH para outras VMs, zero mensagens enviadas.
> Telefones, LIDs e tokens mascarados. Coordenador: W4.

---

## 🔴 VEREDITO

**O texto `👥 Nome (id@lid)` está GRAVADO NO BANCO, dentro de `messages.content`.
Não é montado no front-end, nem pelo Rails. Quem monta é a *app `chatwoot` que roda DENTRO
da WAHA* — um plugin da própria WAHA que escreve no Chatwoot pela API pública.**

Evidência crua, direto do banco (telefones/LIDs mascarados por mim; o resto é literal):

```
-[ RECORD 1 ]------+---------------------------------------------
id                 | 34084
conversation_id    | 2446
inbox_id           | 43
message_type       | 0            (incoming)
sender_type        | Contact
sender_id          | 1963         (o CONTATO-GRUPO, não a pessoa)
source_id          |              (VAZIO)
content            | 👥 *Walisson (6075*****0218@lid)*            +
                   |                                              +
                   | Vish                                         +
                   | `🗓️ Hoje, 02 de mai. • 18:26 BRT`
content_attributes | {}           (VAZIO — zero metadado de participante)
created_at         | 2026-05-02 23:17:01.233711
```

Bytes exatos do campo `content` (repr Python, `\n` reais):

```python
'👥 *Walisson (6075*****0218@lid)*\n\nVish\n`🗓️ Hoje, 02 de mai. • 18:26 BRT`'
'👥 *Ederson Ricieri Davi (7406*****4948@lid)*\n\npara vc ir para multiseg'
'👥 *‎Rogerio José Da Silva (2294*****2169@lid)*\n\nquando cheegar quero ver umas coisa no fw com vc'
```

Escala: **548 mensagens** com `@lid` dentro de `content`, **543** com o emoji `👥` (U+1F465) dentro
de `content`, e **0 (zero)** com qualquer LID em `content_attributes`.

E o `(GROUP)` do Sintoma A? **Também está no banco**, em `contacts.name`:

```
id | 24 | account_id | 3
name       | TI TOZI - Inovação (GROUP)
identifier | 5566*****1379-1634750731@g.us
```

---

## Resumo executivo

1. O produtor das strings é a **app `chatwoot` da WAHA** (plugin interno da WAHA, endpoint
   `GET /api/apps?session=...`), não o ChatSPX. Ela posta em inboxes `Channel::Api` usando o
   `inboxIdentifier` da API pública — confirmei que os identificadores batem com o banco.
2. **O Rails não monta nada disso.** `grep` por `👥`, `(GROUP)`, `(Grupo)` e `Reagiu com` em
   `app/ lib/ enterprise/` retorna **zero** (só emoji picker e Help Center). Confirma o briefing.
3. **A WAHA JÁ SABE o telefone de todo mundo.** Testei os dois LIDs reais do dump do usuário:
   ambos resolvem instantaneamente para telefone. O mapa LID→PN tem **2757 entradas** populadas.
   O dado não falta — ele é ignorado por quem monta o texto.
4. **O Sintoma B é FÁCIL.** Um único `GET /api/{session}/groups/{id}/participants` devolve os 12
   integrantes do grupo TI TOZI **com telefone, LID e flag de admin** já resolvidos. Foto do grupo e
   avatar do participante também estão disponíveis por GET.
5. **Isto é uma REGRESSÃO datada, não um defeito eterno.** Até ago/2025 o mesmo produtor gravava
   `**+55 (66) 9***-**22 - Vilso Tozi:**` — com telefone formatado. A partir de dez/2025 passou a
   gravar `👥 *Nome (LID@lid)*`. O WhatsApp virou LID-first e o plugin não acompanhou.
6. **Há um caminho de configuração já existente e não usado.** A config da app `chatwoot` da WAHA
   aceita **templates Mustache** (`chatwoot.to.whatsapp.message.text`, com variáveis tipo
   `{{{chatwoot.sender.name}}}`). Se existir a chave simétrica de entrada, o Sintoma A vira uma
   mudança de configuração — sem tocar em código. **Isto é a pista de maior valor do relatório.**
7. Efeito colateral grave descoberto: as mensagens do formato novo vêm **sem `source_id`**
   (as antigas tinham `WAID:...`). Sem WAID não há reply/editar/apagar para essas mensagens.
8. `Waha::RefreshGroupsJob` está **quebrado nesta VM hoje** (422 e timeout) — e, mesmo quando
   funciona, **descarta** a resposta que contém exatamente os participantes que faltam na UI.

---

## Achados

### 1. FATO VERIFICADO — Configuração real da WAHA nesta VM

`.env:265-267`:

```
WAHA_API_URL=https://waha.simplexsolucoes.com.br
WAHA_API_KEY=2f80****  (32 caracteres — mascarado)
```

Lidas em `app/services/waha/api_service.rb:13-14`. Header de auth: `X-Api-Key`
(`app/services/waha/api_service.rb:275`). Timeout de 8s (`api_service.rb:17`).

`GET /api/version` → HTTP 200:

```json
{"version":"2026.4.2","engine":"GOWS","tier":"PLUS","browser":null,"platform":"linux/x64","worker":{"id":null}}
```

**Engine em uso: GOWS, tier PLUS, versão 2026.4.2.**

`GET /api/sessions?all=true` → 12 sessões. Apenas **uma** está `WORKING`:

| sessão | status |
|---|---|
| **Simplex** | **WORKING** |
| HMX_Consorcio | STOPPED |
| simplexteste, spx*, simplex_desenvolvimento, Realizare_financeiro, Realizare_plantao, Realizare_adm, Realizare_locacao, Recepcao, Password_0800, password_3531, Plantao24h | FAILED |

⚠️ **Contradiz parcialmente a premissa do dispatch:** não existe sessão "Tozi" nesta instância WAHA.
A instância `waha.simplexsolucoes.com.br` é a da **Simplex**. Porém o grupo **"TI TOZI - Inovação"
existe aqui** (a Simplex participa dele), então consegui fazer o diagnóstico completo com dado real.

⚠️ `*` A sessão `spx` **não existe na WAHA**, apesar de estar configurada na inbox 42 — ver Achado 9.

---

### 2. FATO VERIFICADO — O `(GROUP)` está gravado em `contacts.name`, e a variante muda com a época

36 contatos têm `identifier` terminando em `@g.us`. **24 deles têm `(GROUP)` literal no `name`.**
Ao agrupar por variante do sufixo e cruzar com a data de criação, aparece o padrão que decide a questão:

| variante gravada | n | primeiro | último |
|---|---|---|---|
| `(GROUP)` | 24 | 2025-07-24 | 2025-08-25 |
| `(Grupo)` | 3 | 2025-11-29 | 2026-02-11 |
| `(Group)` | 9 | 2025-12-02 | 2025-12-02 |

**Por que isso é prova:** se o sufixo fosse aplicado na renderização, *todos* os 36 apareceriam com
a mesma variante hoje. Eles diferem por janela temporal porque a string foi **congelada no `name` no
momento da criação**, por um produtor cuja versão/locale mudou ao longo do tempo.

Dump integral do contato do grupo da Tozi (`SELECT` direto, sem edição):

```
id                    | 24
account_id            | 3
name                  | TI TOZI - Inovação (GROUP)
identifier            | 5566*****1379-1634750731@g.us
phone_number          | (vazio)
email                 | (vazio)
additional_attributes | {}
custom_attributes     | {"nao_envia_menu": "Sim"}
created_at            | 2025-07-24 20:45:49.558338
updated_at            | 2025-08-23 11:59:12.660358
```

Nenhum metadado de grupo. **Os 36 contatos-grupo estão 100% sem `phone_number`** (36/36).
12 deles têm apenas `custom_attributes = {"waha_whatsapp_chat_id": "...@g.us"}` — nada de participantes.

---

### 3. FATO VERIFICADO — O LID está em `messages.content`; `content_attributes` está vazio

Contagem sobre 32.944 mensagens do banco:

| métrica | valor |
|---|---|
| `content LIKE '%@lid%'` | **548** |
| `content` contém `👥` (U+1F465) | **543** |
| `content_attributes LIKE '%@lid%'` | **0** |
| `content_attributes LIKE '%@g.us%'` | **0** |

Distribuição por inbox — **todas as inboxes envolvidas são `Channel::Api`**, nenhuma é
`Channel::Whatsapp`:

| inbox_id | nome | channel_type | waha_session_name | conv | msgs c/ LID | de | até |
|---|---|---|---|---|---|---|---|
| 17 | spx | Channel::Api | (vazio) | 2405 | 325 | 2025-12-03 | 2025-12-04 |
| 43 | simplexteste | Channel::Api | simplexteste | 2446 | 70 | 2026-03-15 | 2026-05-02 |
| 17 | spx | Channel::Api | (vazio) | 2377 | 64 | 2025-12-05 | 2026-02-23 |
| 17 | spx | Channel::Api | (vazio) | 2417 | 30 | 2026-02-11 | 2026-02-11 |
| 42 | spx | Channel::Api | spx | 2436 | 13 | 2026-02-28 | 2026-03-03 |
| 43 | simplexteste | Channel::Api | simplexteste | 2454/2451/2449/2450 | 34 | 2026-03-12 | 2026-03-20 |
| 41 | teste | Channel::Api | (vazio) | 2429 | 8 | 2026-02-19 | 2026-02-23 |

`Channel::Api` = mensagem **injetada de fora** pela API do Chatwoot. O ChatSPX é o receptor, não o autor.

**Sobre `sender_id`:** todas as mensagens de grupo têm `sender_type=Contact` e `sender_id` = o
**contato-grupo** (ex.: 1963 = "Simplex - Uptime (Grupo)"). Ou seja, do ponto de vista do modelo de
dados, **quem falou foi o grupo**, não a pessoa. A identidade do participante existe *apenas* como
texto dentro do `content`. É por isso que a UI não tem como exibir o autor real: o dado estruturado
não existe.

---

### 4. FATO VERIFICADO — Reação e citação também carregam o LID, e o texto é pt-BR

```
id                 | 32957
content            | 👥 *Paulo Moggi (2094*****2717@lid)*        +
                   |                                             +
                   | *Reagiu com* 🤨
content_attributes | "{\"in_reply_to\":32956,\"in_reply_to_external_id\":null, ...}"
```

Dois detalhes que importam:

- **`*Reagiu com*` está em português.** `grep -rn "Reagiu com" app/ lib/ enterprise/ config/` = **zero
  resultados**. Logo, a tradução vem de fora — e casa exatamente com o `locale: "pt-BR"` que
  encontrei na config da app WAHA (Achado 6). É a mesma mão que escreveu `(Grupo)`.
- `content_attributes` aqui é uma **string JSON escapada**, não um objeto. No universo das mensagens
  com LID: 509 `object` / 39 `string`. Sinal de produtor externo serializando de forma inconsistente.

---

### 5. FATO VERIFICADO — Regressão datada: antes o telefone vinha resolvido

Classifiquei os formatos de prefixo em todas as mensagens *inbound* de conversas de grupo:

| formato gravado | n | primeiro | último | com `WAID:` | sem `source_id` |
|---|---|---|---|---|---|
| **D)** `**+55 (66) 9999-9999 - Nome:**` | 4830 | 2025-07-24 | 2025-08-27 | **4830** | 0 |
| **F)** sem prefixo | 151 | 2025-07-24 | 2026-03-19 | 149 | 2 |
| **A)** `👥 *Nome (LID@lid)*` | 513 | 2025-12-03 | 2026-05-02 | **0** | **513** |

Exemplo real do formato antigo, mesma conversa do grupo TI TOZI:

```
id        | 17049
source_id | WAID:3ACA7733ACF4704497E1
content   | **+55 (66) 9***-**22 - Vilso Tozi:**
```

**Duas regressões simultâneas** ao virar o formato:

1. **Perdeu o telefone** — passou a imprimir o LID cru. Coincide com a migração do WhatsApp para
   endereçamento LID-first (o grupo TI TOZI está com `AddressingMode: "lid"` — ver Achado 7).
2. **Perdeu o `source_id`** — 513/513 sem WAID. Sem WAID, **não há como responder, editar ou apagar**
   essas mensagens pelo caminho da WAHA (`api_service.rb:54-65` dependem de `messageId`).

O item 2 não estava no briefing e é um dano colateral relevante.

---

### 6. 🎯 FATO VERIFICADO — O culpado: a app `chatwoot` roda DENTRO da WAHA e tem templates configuráveis

`GET /api/apps?session=simplexteste` → HTTP 200 (tokens mascarados por mim):

```json
[{
  "id": "chatwoot-simplexteste",
  "session": "simplexteste",
  "app": "chatwoot",
  "config": {
    "linkPreview": "OFF",
    "locale": "pt-BR",
    "url": "https://chatspx.app",
    "accountId": 3,
    "accountToken": "GsTs****",
    "inboxId": 43,
    "inboxIdentifier": "1a4q****"
  },
  "enabled": true
}]
```

**Prova de ponta-a-ponta da cadeia causal.** Cruzei o `inboxIdentifier` da app com o banco:

| app WAHA | `inboxId` | `inboxIdentifier` (app) | inbox no banco | identifier no banco | bate? |
|---|---|---|---|---|---|
| `chatwoot-simplexteste` | 43 | `1a4q****` | 43 = simplexteste | `1a4q****` | ✅ |
| `spx` (sessão Simplex) | 2 | `1owS****` | 2 = simplex_996571379 | `1owS****` | ✅ |

A inbox 2 é **exatamente onde estão as 8 conversas do grupo TI TOZI** (contato 24). Fecha o circuito:
a app da WAHA escreve, via API pública do Chatwoot, nas inboxes onde as strings aparecem.

**🔑 A descoberta de maior valor — a config aceita templates Mustache.** Varri as 12 sessões e
9 apps `chatwoot` trazem um bloco `templates`:

```json
"templates": {
  "chatwoot.to.whatsapp.message.text":
      "*{{{chatwoot.sender.name}}}*:\n{{{ content }}}",
  "chatwoot.to.whatsapp.message.media.caption":
      "{{#singleAttachment}}\n{{#content}}\n*{{{chatwoot.sender.name}}}*:\n{{{ content }}}\n{{/content}}\n{{/singleAttachment}}"
}
```

Repare no **padrão de nomenclatura direcional**: `chatwoot.to.whatsapp.*`. Note também que o
template de saída usa exatamente o mesmo estilo do que vemos na entrada (`*Nome*:` + `\n` + conteúdo)
— é a assinatura da mesma engine de template.

**HIPÓTESE FORTE, NÃO CONFIRMADA:** existe a chave simétrica `whatsapp.to.chatwoot.*` que controla
o texto de entrada — e é ela que hoje resolve para `👥 *{{nome}} ({{lid}})*`. **Se confirmada, o
Sintoma A é resolvido por configuração (`PUT /api/apps`), sem uma linha de código no ChatSPX.**
Não confirmei porque: (a) só posso emitir GET, (b) o Swagger da WAHA (`/api-json`, `/swagger-json`,
`/openapi.json`) responde **HTTP 401** — usa autenticação própria, não a `X-Api-Key`.
**Esta é a verificação nº 1 a fazer na próxima rodada** (doc oficial da WAHA ou fonte do plugin).

Outras observações da varredura de apps:
- A app da sessão `Simplex` (id `spx`, inbox 2) está **`enabled: false`** — explica por que as
  conversas do TI TOZI param em ago/2025. Ela aponta para `chat.simplexsolucoes.com.br` (produção
  Simplex), **não** para homologação. Não toquei nela.
- Existe também uma app `calls` na sessão `Simplex` (rejeita chamadas com mensagem automática).
- **Todas** as 9 apps `chatwoot` têm `locale: "pt-BR"` — consistente com `(Grupo)` e `*Reagiu com*`.

---

### 7. 🎯 FATO VERIFICADO — A WAHA entrega os participantes prontos, com telefone e admin

`GET /api/Simplex/groups?limit=200` → HTTP 200, **78 grupos**, 240 KB, **932 participantes** no total.
O grupo da Tozi está lá, com JID idêntico ao `identifier` do contato 24:

```json
{
  "JID": "5566*****79-1634750731@g.us",
  "Name": "TI TOZI - Inovação",
  "OwnerJID": "2677*****9653@lid",
  "OwnerPN": "5566*****79@s.whatsapp.net",
  "AddressingMode": "lid",              ← A RAIZ DO PROBLEMA
  "GroupCreated": "2021-10-20T14:25:31-03:00",
  "CreatorCountryCode": "BR",
  "IsAnnounce": false, "IsLocked": false, "IsEphemeral": false,
  "MemberAddMode": "admin_add",
  "ParticipantCount": 0,                ← campo não populado (bug do GOWS); use len(Participants)
  "Participants": [ ... 12 itens ... ]
}
```

**Schema do participante** (`GET /api/{session}/groups/{groupId}/participants` — o endpoint EXISTE
nesta versão e retorna HTTP 200):

| campo | tipo | vem preenchido? |
|---|---|---|
| `JID` | string | ✅ `2294*****2169@lid` |
| `PhoneNumber` | string | ✅ **`5566*****91@s.whatsapp.net`** |
| `LID` | string | ✅ |
| `IsAdmin` | bool | ✅ |
| `IsSuperAdmin` | bool | ✅ |
| `DisplayName` | string | ❌ **sempre vazio** neste engine |
| `Error` | int | ✅ (0) |
| `AddRequest` | null | — |

Os 12 participantes do TI TOZI (mascarados), **cada um com telefone resolvido**:

| # | LID | PhoneNumber | Admin | SuperAdmin |
|---|---|---|---|---|
| 1 | `2294*****2169@lid` | `5566*****91` | ✅ | |
| 2 | `2245*****7943@lid` | `5566*****22` | | |
| 3 | `1151*****8050@lid` | `5566*****40` | ✅ | |
| 4 | `2677*****9653@lid` | `5566*****79` | ✅ | ✅ |
| 5 | `2603*****0002@lid` | `5566*****60` | ✅ | |
| 6 | `2718*****3995@lid` | `5566*****20` | ✅ | |
| 7 | `1019*****6617@lid` | `5566*****59` | | |
| 8 | `2313*****1107@lid` | `5566*****60` | | |
| 9 | `2167*****6073@lid` | `5566*****29` | | |
| 10 | `1800*****7644@lid` | `5566*****29` | | |
| 11 | `1096*****0162@lid` | `5566*****42` | | |
| 12 | `2363*****0482@lid` | `5566*****00` | | |

**Resposta direta à pergunta do dispatch: o Sintoma B é FÁCIL.** Um único GET traz nome do grupo,
dono, data de criação, 12 participantes com telefone, LID e flag de admin. O que **não** vem é o
nome de exibição do participante (`DisplayName` vazio) — mas isso se resolve com o Achado 8.

Bônus verificados (todos HTTP 200):
- `GET /api/{session}/groups/{groupId}` → mesmo objeto completo, um grupo só.
- `GET /api/{session}/groups/{groupId}/picture` → `{"url":"https://pps.whatsapp.net/..."}` — **foto do grupo disponível**.
- `GET /api/{session}/chats?limit=2` → lista de chats com `id` e `name`.

---

### 8. 🎯 FATO VERIFICADO (TESTE DECISIVO) — A WAHA resolve os LIDs do dump do usuário

Este era o teste que o dispatch pediu para não deixar de fazer. Usei os **dois LIDs reais** do dump:

```
GET /api/Simplex/lids/count
→ {"count":2757}                                              [HTTP 200]

GET /api/Simplex/lids/229480102662169@lid      (Rogerio José Da Silva)
→ {"lid":"2294*****2169@lid","pn":"5566*****91@c.us"}        [HTTP 200] ✅ RESOLVE

GET /api/Simplex/lids/260330953380002@lid      (Angela Tozi)
→ {"lid":"2603*****0002@lid","pn":"5566*****60@c.us"}        [HTTP 200] ✅ RESOLVE
```

**Conclusão do teste decisivo: o problema é NOSSO (no sentido amplo — do lado que monta o texto),
não da WAHA.** O mapa LID→PN tem **2757 entradas populadas** e responde de imediato. O telefone
sempre esteve a um GET de distância. Quem monta o `👥 Nome (LID@lid)` simplesmente não faz essa
chamada — imprime o identificador técnico cru.

Confirmação cruzada: o telefone `5566*****91` retornado aqui é **exatamente** o `PhoneNumber` do
participante nº 1 na lista do grupo (Achado 7). Duas rotas independentes, mesmo resultado.

**E o nome?** `GET /api/contacts?session=Simplex&contactId=5566*****91@c.us` → HTTP 200:

```json
{"id":"5566*****91@c.us","name":"Rogerio Jose","pushname":"‎Rogerio José Da Silva"}
```

Dois achados aqui:
- O `pushname` é **`‎Rogerio José Da Silva`** — e começa com **U+200E (LEFT-TO-RIGHT MARK)**.
  É o mesmo caractere invisível que o briefing detectou no dump da UI. **Confirma que o nome exibido
  vem do `pushname` do WhatsApp**, propagado literalmente pela app da WAHA.
- Existe também `name` ("Rogerio Jose"), o nome da agenda — mais limpo que o `pushname`.
- `GET /api/contacts/profile-picture?...` → HTTP 200 com URL: **avatar do participante disponível**.
- `GET /api/contacts/about?...` → HTTP 501 "not implemented by 'GOWS' engine".
- ⚠️ `GET /api/contacts?session=Simplex&limit=2` (sem `contactId`) → **HTTP 500**, bug do GOWS:
  `TypeError: Cannot read properties of undefined (reading 'split') at toJID`. Ou seja, **não dá para
  listar contatos em massa** neste engine — só um a um por `contactId`.

---

### 9. FATO VERIFICADO — `RefreshGroupsJob` está quebrado hoje E joga fora o dado que falta

Duas falhas independentes, uma de configuração e uma de design.

**(a) Está falhando agora.** Logs do `journalctl -u chatwoot-worker.1` de hoje (2026-07-27):

```
13:00:40 WARN [RefreshGroupsJob] Failed to refresh groups for spx:
         WAHA API error (422): Session "spx" does not exist
13:00:35 WARN [RefreshGroupsJob] Failed to refresh groups for simplexteste:
         WAHA API timeout: Net::ReadTimeout with #<TCPSocket:(closed)>
```

- A inbox 42 aponta para a sessão `spx`, que **não existe** na WAHA → 422 em toda execução.
- A sessão `simplexteste` **estoura o timeout de 8s** (`api_service.rb:17`). Coerente com o que medi:
  `/groups` devolve 240 KB e é lento. **O timeout é curto demais para este endpoint.**

Volume em 24h: **384** linhas de `RefreshGroupsJob` e **1776** de `Contacts::ResolveLidJob`
(este último também morrendo em `Waha::ApiService::ConnectionError: WAHA API timeout` após esgotar
os retries). Há um custo de ruído e de CPU rodando sem entregar valor.

**(b) Mesmo funcionando, descarta o essencial.** `app/jobs/waha/refresh_groups_job.rb:17-19`:

```ruby
session_names.each do |session_name|
  service.get_groups(session_name)        # ← retorno IGNORADO
  Rails.logger.info("[RefreshGroupsJob] Refreshed groups for session: #{session_name}")
```

O job faz o GET **apenas pelo efeito colateral** de aquecer o cache LID→PN dentro da WAHA, e
**descarta a resposta** — que é justamente o payload com os 12 participantes, telefones, LIDs e
flags de admin do Achado 7. O dado que falta na UI passa por dentro deste processo e é jogado fora
a cada 30 minutos. Confirma e reforça a observação do briefing.

---

### 10. FATO VERIFICADO — O Rails não monta nenhuma dessas strings

```
grep -rn $'\U0001F465' app/ lib/ enterprise/ config/locales
  → app/javascript/dashboard/components-next/HelpCenter/.../categoryEmptyStateContent.js:45  (ícone)
  → app/javascript/shared/components/emoji/emojisGroup.json:2603                             (emoji picker)

grep -rn "(GROUP)\|(Grupo)"  app/ lib/ enterprise/   → 0 resultados
grep -rn "Reagiu com\|Reagiu" app/ lib/ enterprise/ config/ → 0 resultados
```

**Confirma o briefing integralmente.** Nem o backend nem o front-end produzem `👥`, `(GROUP)` ou
`*Reagiu com*`. Combinado com os Achados 2, 3 e 6, a autoria é da app `chatwoot` da WAHA.

⚠️ **Correção a uma hipótese do briefing:** o briefing levanta o n8n/receptor externo como
"principal suspeito". A evidência aponta para **a app `chatwoot` embutida na própria WAHA** —
que é externa ao Rails, mas **não** é o n8n. Não encontrei nenhum indício de n8n neste caminho.

---

### 11. FATO VERIFICADO — Dimensionamento do problema neste banco

| métrica | valor |
|---|---|
| Inboxes com `waha_session_name` preenchido | **2** (id 42 `spx`, id 43 `simplexteste`, ambas account 3) |
| `contact_inboxes` com `source_id LIKE '%@lid'` | **0** |
| `contact_inboxes` com `source_id LIKE '%@g.us'` | **0** |
| `contact_inboxes` com `source_id LIKE '%@c.us'` | **0** |
| `contact_inboxes` total | 4312 |
| `contacts` com `identifier` `@g.us` | **36** (todos sem `phone_number`) |
| `contacts` com `identifier` `@lid` | **1** (id 2021, "preso": sem telefone, nome = o próprio número) |
| `contacts` com `(GROUP)` no `name` | **24** |
| `messages` com `@lid` no `content` | **548** |

**Achado estrutural importante:** `contact_inboxes.source_id` **nunca** carrega o JID nesta VM.
Para as inboxes `Channel::Api` (4281 de 4312 registros) o `source_id` é um **UUID** gerado pela API
pública do Chatwoot — ex.: `cad3393e-f1bb-456a-81d4-94f9a4fc3699`. O JID do grupo vive **só** em
`contacts.identifier`. Isso invalida qualquer estratégia de detectar grupo por `contact_inbox.source_id`
neste ambiente, e explica por que `enterprise/app/services/captain/behavior/router_service.rb:33-46`
faz a detecção por `contact.identifier` / `custom_attributes` — foi a escolha correta.

O único contato "preso" em `@lid` (id 2021) tem `name` igual ao próprio LID
(`81820414494285957058`) e `custom_attributes = {"waha_whatsapp_lid": ..., "waha_whatsapp_chat_id": ...}`.
É o alvo dos `ResolveLidJob` que estão falhando por timeout (Achado 9).

---

## Lacunas / o que não consegui verificar

1. **NÃO CONFIRMADO — a chave de template do sentido WhatsApp→Chatwoot.** É a lacuna mais importante,
   porque é ela que decide se o Sintoma A se resolve por config ou por código. Só observei
   `chatwoot.to.whatsapp.message.text` e `.media.caption`. Bloqueado por: só posso emitir GET, e o
   Swagger da WAHA responde **401** (`/api-json`, `/swagger-json`, `/openapi.json` — auth própria,
   não a `X-Api-Key`). **Próximo passo:** doc oficial da WAHA sobre a app Chatwoot, ou credencial do
   Swagger, ou inspeção do plugin no container.
2. **NÃO CONFIRMADO — o comportamento da instância WAHA da Tozi produção.** O dispatch proíbe SSH e
   acesso a `.109`, e a sessão da Tozi não existe nesta instância. Todo o diagnóstico foi feito com o
   grupo TI TOZI visto pelo lado da **Simplex**. O padrão do texto é idêntico ao do dump do usuário
   (mesmos LIDs, mesmo formato), então considero a extrapolação sólida — mas ela é uma extrapolação.
3. **NÃO VERIFICADO — se a versão da WAHA na Tozi produção é a mesma (2026.4.2/GOWS/PLUS).** Se for
   mais antiga, o schema de participantes pode diferir.
4. **`DisplayName` vem vazio** em 100% dos participantes que inspecionei — não consegui determinar se
   é limitação do engine GOWS ou se depende de sincronização de contatos. O nome está disponível por
   outra rota (`GET /api/contacts?contactId=...`), mas isso é **1 request por participante**, e a
   listagem em massa está quebrada (HTTP 500, Achado 8).
5. **Não testei nenhum endpoint que só exista como POST**, conforme a regra. Em particular, não
   validei se há um POST de resolução de LID em lote — apenas registro a possibilidade.
6. **`log/production.log` está praticamente vazio** (630 bytes, última escrita jan/2026). Os logs
   reais vão para o **journald** (`chatwoot-web.1` / `chatwoot-worker.1`) — foi de lá que tirei o
   Achado 9. Um `grep` em `log/*.log` sozinho daria falso negativo; registro para os outros workers.
7. **Não determinei quando exatamente a app da WAHA mudou de formato.** Há um vão sem mensagens de
   grupo entre 2025-08-27 e 2025-12-03; a virada aconteceu em algum ponto dessa janela.

---

## Implicações para a solução

### O que a evidência HABILITA

1. **O Sintoma A pode ser uma correção de configuração, não de código.** Se a hipótese do Achado 6 se
   confirmar, ajustar o template de entrada da app `chatwoot` (via `PUT /api/apps`) remove o
   `(LID@lid)` de todas as sessões — sem tocar no ChatSPX, sem deploy, sem migration.
   **É de longe o menor caminho para o ganho visível que o briefing pede na pergunta 6.**
   Custo de verificação: uma leitura de doc. Recomendo fortemente que seja a próxima ação.
2. **O Sintoma B é barato.** Os participantes vêm prontos com telefone + admin em **um** GET já
   implementado no cliente (`get_groups`, `api_service.rb:108`). Falta apenas (a) um método
   `get_group_participants`, (b) persistência, (c) UI. Não há bloqueio técnico e não depende da WAHA
   mudar nada.
3. **Enriquecimento visual disponível de graça:** foto do grupo (`/groups/{id}/picture`) e avatar do
   participante (`/contacts/profile-picture`) — ambos HTTP 200 verificados.
4. **`RefreshGroupsJob` já é o lugar natural** para materializar participantes: ele já faz o GET certo,
   no intervalo certo; hoje só falta **não descartar a resposta** (`refresh_groups_job.rb:18`).
   Corrigir os dois bugs do Achado 9 (sessão `spx` inexistente + timeout de 8s) é pré-requisito.

### O que a evidência IMPEDE ou complica

5. **Corrigir só no front-end não resolve.** O texto está **persistido** em 548 mensagens e em 24
   nomes de contato. Uma limpeza na renderização mascara o histórico, mas o dado continua sujo — e
   toda mensagem nova continua chegando suja. **A correção tem que ser na origem** (app da WAHA);
   um `regex` de exibição serve, no máximo, como paliativo para o passado.
6. **Não dá para atribuir mensagem antiga ao participante de forma estruturada.** `sender_id` aponta
   para o contato-grupo e `content_attributes` está vazio (Achado 3). Reconstruir a autoria histórica
   exigiria **parsear o texto** — frágil, e sujeito às 3 variantes de formato do Achado 5.
7. **Mensagens do formato novo não têm `source_id`.** Isso quebra reply/editar/apagar via WAHA para
   grupos (`api_service.rb:54-65`). É um problema **independente** do LID e deve entrar no escopo —
   provavelmente na mesma correção de configuração da app.
8. **Modelar grupo como contato é o que já existe de fato** (36 contatos `@g.us`, sem telefone).
   Qualquer proposta de modelagem (pergunta 4 do briefing) precisa conviver com esses 36 registros e
   com o `router_service.rb` que já detecta grupo por `identifier`.
9. **Atenção operacional:** a instância WAHA `waha.simplexsolucoes.com.br` é **compartilhada** —
   9 apps `chatwoot` de **5 accounts diferentes** (3, 4, 5, 85, 92), várias apontando para
   `chat.simplexsolucoes.com.br` (**produção**). Alterar template/config nessa instância **afeta
   produção**. Foi por isso que me limitei a GET. Qualquer mudança aqui exige janela e autorização
   explícita — não é uma alteração "de homologação".

---

## Referências

**Código (verificado nesta VM):**
- `app/services/waha/api_service.rb:13-14` — leitura de `WAHA_API_URL` / `WAHA_API_KEY`
- `app/services/waha/api_service.rb:17` — timeout de 8s (curto demais para `/groups`)
- `app/services/waha/api_service.rb:54-65` — `edit_message` / `delete_message` dependem de `messageId`
- `app/services/waha/api_service.rb:92-110` — `get_lid_phone_number`, `get_lids_list`, `get_groups`
- `app/services/waha/api_service.rb:221-233` — `create_chatwoot_app` (POST `/api/apps`)
- `app/services/waha/api_service.rb:275` — header `X-Api-Key`
- `app/jobs/waha/refresh_groups_job.rb:17-19` — descarta o retorno de `get_groups`
- `enterprise/app/services/captain/behavior/router_service.rb:33-46` — detecção de grupo por `identifier`
- `.env:265-267` — configuração da WAHA

**Requests WAHA executados (todos GET, todos HTTP 200 salvo onde indicado):**
- `GET /api/version` · `GET /api/server/version` — 2026.4.2 / GOWS / PLUS
- `GET /api/sessions?all=true` — 12 sessões, 1 WORKING
- `GET /api/apps?session={12 sessões}` — **9 apps `chatwoot` com bloco `templates`**
- `GET /api/Simplex/groups?limit=200` — 78 grupos, 932 participantes
- `GET /api/Simplex/groups/5566*****79-1634750731@g.us`
- `GET /api/Simplex/groups/5566*****79-1634750731@g.us/participants` — 12, com telefone e admin
- `GET /api/Simplex/groups/5566*****79-1634750731@g.us/picture` — URL da foto
- `GET /api/Simplex/lids/count` — 2757
- `GET /api/Simplex/lids?limit=3`
- `GET /api/Simplex/lids/229480102662169@lid` — ✅ resolve
- `GET /api/Simplex/lids/260330953380002@lid` — ✅ resolve
- `GET /api/contacts?session=Simplex&contactId=...` — `name` + `pushname` (com U+200E)
- `GET /api/contacts/profile-picture?...` — URL do avatar
- `GET /api/contacts/about?...` — **HTTP 501** (não implementado no GOWS)
- `GET /api/contacts?session=Simplex&limit=2` — **HTTP 500** (bug do GOWS em `toJID`)
- `GET /api/Simplex/chats?limit=2`
- `GET /api-json`, `/swagger-json`, `/openapi.json` — **HTTP 401** (auth própria do Swagger)
- `GET /api/apps/schema`, `/api/apps/types`, `/api/{session}/apps` — HTTP 404 (não existem)

**Banco (todas as consultas em sessão `default_transaction_read_only=on`):**
`contacts`, `contact_inboxes`, `conversations`, `messages`, `inboxes`, `channel_api`.
Bloqueio de escrita verificado na abertura: `ERROR: cannot execute CREATE TABLE in a read-only transaction`.

**Logs:** `journalctl -u chatwoot-web.1 -u chatwoot-worker.1` (janelas de 1 e 3 dias).
`log/production.log` está inerte (630 bytes) — **não** use só `log/*.log` para investigar WAHA.

---

## Conformidade com as restrições do dispatch

| Restrição | Status |
|---|---|
| Somente a VM 192.168.8.232 | ✅ zero SSH executado |
| WAHA: somente GET | ✅ apenas GET; nenhum POST/PUT/DELETE/PATCH; nenhum `send*`, `start`, `stop`, `restart`, `logout` |
| Endpoint de leitura que só existe como POST | ✅ nenhum foi chamado (nenhum caso encontrado) |
| Banco: somente SELECT | ✅ sessão com `default_transaction_read_only=on`, bloqueio testado |
| Nenhuma mensagem enviada | ✅ |
| Edições restritas a `plano/pesquisa-grupos-waha/` | ✅ apenas este arquivo |
| Sem commit | ✅ |
| Telefones e segredos mascarados | ✅ |
