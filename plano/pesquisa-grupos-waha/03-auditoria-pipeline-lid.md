# W3 — Auditoria do pipeline LID existente no ChatSPX

> Worker: W3 (arqueologia + auditoria) · Data: 2026-07-27 · VM: 192.168.8.232 (homologação)
> Branch: `homologacao` @ `d985beeafd` · Escopo: **somente leitura** (código, git, logs, SELECT, GET WAHA)

---

## Resumo executivo

O ChatSPX tem uma máquina de normalização de LID razoavelmente sofisticada — e **ela está
essencialmente desligada na prática**. A normalização inline (`Public::Api::V1::InboxesController`)
é guardada por um early-return que exige `source_id.end_with?('@lid')`
(`inboxes_controller.rb:37`), mas **100% dos `contact_inboxes` de inboxes WAHA nesta VM têm
`source_id` = UUID** (30/30 — query abaixo). O receptor externo nunca envia `source_id`; envia
`identifier`. Resultado: o controller nunca dispara, e quem salva o 1:1 hoje é só o par
`ResolveLidSweepJob` (cron horário) → `ResolveLidJob`, que pega o LID pelo `contact.identifier`.

Para **grupo**, o quadro é pior e o motivo é estrutural, não um bug de regex: o contato do grupo
tem `identifier = <id>@g.us` e **nenhum dos caminhos de LID olha para `@g.us`** — `waha_lid?`,
`whatsapp_user_jid?`, `needs_resolution?`, `stuck_contact_inboxes` e `waha_effective_phone_for`
todos filtram exclusivamente por `@lid`/`@c.us`. Mais fundo: a mensagem de grupo entra por
`Public::Api::V1::Inboxes::MessagesController` com `sender: @contact_inbox.contact`
(`messages_controller.rb:81`) — **o remetente é o contato-grupo, não o participante**. O Chatwoot
não tem onde guardar "quem falou", então o receptor externo resolve isso concatenando
`👥 *Nome (lid@lid)*` **dentro do `content`** — provado por SELECT (548 mensagens no banco).

O achado com maior alavancagem: **`GET /api/{session}/groups`, que o `RefreshGroupsJob` já chama a
cada 30 min, retorna `Participants[]` com `LID` E `PhoneNumber` no mesmo objeto** — 932 pares
LID→PN prontos em 78 grupos, medidos ao vivo hoje. O job **descarta a resposta inteira**
(`refresh_groups_job.rb:18`: `service.get_groups(session_name)` sem atribuição) e o sistema depois
paga um round-trip HTTP por LID no `ResolveLidJob` — round-trip que, agora mesmo, está em
retry-loop por timeout. Existe um mapa LID→PN de graça sendo jogado no lixo a cada meia hora.

Não há **nenhuma** tentativa anterior de tratar grupo: `git log -S "@g.us"` retorna exatamente 2
commits, ambos alheios ao problema (desviar a IA de grupos, e um comentário numa regex).

---

## Achados

### 1. FATO — O early-return que mata a normalização: `waha_lid?(source_id)`

`app/controllers/public/api/v1/inboxes_controller.rb:35-37`

```ruby
def normalize_waha_contact_params(source_id:, phone_number:, custom_attributes: nil)
  return { source_id: source_id, phone_number: phone_number } if source_id.blank?
  return { source_id: source_id, phone_number: phone_number } unless waha_lid?(source_id)   # :37
```

com (`inboxes_controller.rb:156-158`):

```ruby
def waha_lid?(source_id)
  source_id.to_s.end_with?('@lid')
end
```

**Toda** a máquina de LID do controller vive atrás dessa linha. Um `source_id` que seja UUID,
`@c.us` ou **`@g.us`** sai imediatamente sem tocar em nada.

### 2. FATO — Na prática o `source_id` NUNCA é um JID: é sempre UUID (30/30)

```sql
SELECT CASE WHEN ci.source_id ~ '^[0-9a-f]{8}-' THEN 'uuid'
            WHEN ci.source_id LIKE '%@c.us' THEN 'c.us'
            WHEN ci.source_id LIKE '%@lid'  THEN 'lid'
            WHEN ci.source_id LIKE '%@g.us' THEN 'g.us'
            ELSE 'outro' END AS formato, count(*)
FROM contact_inboxes ci JOIN inboxes i ON i.id=ci.inbox_id
WHERE i.waha_session_name IS NOT NULL AND i.waha_session_name <> ''
GROUP BY 1;
```

```
 formato | count
---------+-------
 uuid    |    30
```

Causa: `app/controllers/public/api/v1/inboxes/contacts_controller.rb:8`

```ruby
source_id = params[:source_id] || SecureRandom.uuid
```

O receptor externo (o "chatwoot app" embutido na WAHA) **não manda `source_id`** — manda
`identifier` (o JID) e deixa o Rails gerar UUID. Consequência: o achado #1 dispara sempre.
A normalização inline do controller é, hoje, **código morto** — inclusive para 1:1.

> Prova complementar: `contact_inboxes` com `source_id LIKE '%@lid'` = **0**; com `'%@g.us'` = **0**;
> com `'%@c.us'` = **0**. Já `contacts.identifier LIKE '%@g.us'` = **36** e
> `contacts.identifier LIKE '%@lid'` = **1**.

**Ressalva de honestidade:** 30 registros é amostra de homologação. NÃO CONFIRMADO para a Tozi PROD
(.109) — proibido por blindagem. Mas o padrão (`identifier` = JID, `source_id` = UUID) é o mesmo
formato observado no `contact_inbox 4258` que está em retry AGORA, e nos 36 contatos de grupo.

### 3. FATO — A mensagem de grupo não tem como carregar o participante

`app/controllers/public/api/v1/inboxes/messages_controller.rb:78-88`

```ruby
def message_params
  {
    account_id: @conversation.account_id,
    sender: @contact_inbox.contact,        # :81  ← SEMPRE o contato do contact_inbox
    content: permitted_params[:content],
    inbox_id: @conversation.inbox_id,
    echo_id: permitted_params[:echo_id],
    source_id: permitted_params[:source_id],
    message_type: :incoming
  }
end
```

e `permitted_params` (`:70-72`) só aceita `:content, :echo_id, :source_id`. **Não existe campo de
participante/autor** na API pública. Como o `contact_inbox` de um grupo aponta para o contato-grupo,
toda mensagem de grupo tem `sender = "TI TOZI - Inovação"`.

O receptor contorna isso escrevendo o autor **no texto**:

```sql
SELECT count(*) FROM messages WHERE content LIKE '%@lid%';  -- 548
```

Amostra real (`messages.id = 34084`, `conversation_id = 2446`, `message_type = 0`):

```
content: 👥 *Walisson (60756640940218@lid)*
         (linha em branco)
         Vish
         `🗓️ Hoje, 02 de mai. • 18:26 BRT`
source_id: (vazio)
content_attributes: {}
additional_attributes: {}
```

O `*...*` é markdown — é por isso que aparece em **negrito** na UI. O `U+200E` citado no briefing
está de fato presente (`👥 *‎Rogerio José Da Silva (229480102662169@lid)*`, msg 33966), confirmando
origem em payload cru do WhatsApp.

### 4. FATO — `(GROUP)` / `(Grupo)` está no `contacts.name` no banco, e não existe no código Rails

```sql
SELECT count(*) FILTER (WHERE name LIKE '%(GROUP)') AS caps,   -- 24
       count(*) FILTER (WHERE name LIKE '%(Group)') AS en,     --  9
       count(*) FILTER (WHERE name LIKE '%(Grupo)') AS pt      --  3
FROM contacts;
```

`grep -rn "(Grupo)\|(Group)" app/ lib/ enterprise/ config/` → **zero** resultados (o emoji `👥` só
aparece em `categoryEmptyStateContent.js:45`, help center). **Confirma e reforça o briefing.**

Pista temporal forte: as variantes mudaram com o tempo — `(GROUP)` maiúsculo em grupos cuja última
mensagem é de 2025-08 a 2026-02; `(Grupo)` em pt nos ativos até 2026-06. Isso é assinatura de um
componente externo versionado, não de código nosso.

> **Convergência com o W1** (`01-cadeia-ingestao.md`, lido após eu fechar este achado): são **dois
> produtores externos distintos** — `👥 *Nome (lid@lid)*` vem da **WAHA Chatwoot App**
> (`src/apps/chatwoot/consumers/waha/base.ts:385`, `participant = \`${name} (${participant})\``), e
> `(GROUP)` caixa-alta vem da **Evolution API**
> (`chatwoot.service.ts:737`, hardcoded). A WAHA usa `(Group)`/`(Grupo)` via i18n, nunca `(GROUP)`.
> Isso explica exatamente a distribuição temporal que medi: os `(GROUP)` são contas migradas
> Evolution→WAHA cujo `contacts.name` **nunca é reescrito** (o
> `ContactInboxWithContactBuilder#find_contact` só busca contato existente, `:65-72`, e nunca faz
> `update` de nome) — o sufixo fica congelado no banco. Duas investigações independentes chegaram à
> mesma conclusão a partir de evidências diferentes.

Exemplo (`contacts.id = 1963`):
```
name        | Simplex - Uptime (Grupo)
identifier  | 120363403758104643@g.us
phone_number| (null)
custom_attr | {"waha_whatsapp_chat_id": "120363403758104643@g.us"}
sources     | 1267cce8-… [inbox=17] | d1e34dd1-… [inbox=41] | 4425e302-… [inbox=42] | 5ae81747-… [inbox=43]
```
Quatro `contact_inboxes` com UUID diferente, mesmo contato — deduplicado por `identifier` via
`ContactInboxWithContactBuilder#find_contact_by_identifier` (`:96-100`).

### 5. FATO — `sanitize_waha_contact_name` (a linha ~186/187) só limpa o sufixo no FIM ABSOLUTO

`app/controllers/public/api/v1/inboxes_controller.rb:183-196`

```ruby
def sanitize_waha_contact_name(name, phone_number = nil)
  return name if name.blank?
  cleaned = name.gsub(/@(c\.us|s\.whatsapp\.net|lid|g\.us)\z/, '')   # :187  ← \z = fim da string
  return "+#{cleaned}" if cleaned.match?(/\A\d{10,15}\z/) && phone_number.blank?   # :190
  return phone_number if phone_number.present? && cleaned.gsub(/\D/,'') == phone_number.gsub(/\D/,'')
  cleaned
end
```

Ela age **apenas sobre `contact_attributes[:name]`**, chamada em um único lugar
(`contacts_controller.rb:16`), no `create` do contato. Executei a função sobre os casos reais do dump:

| entrada | saída |
|---|---|
| `"229480102662169@lid"` | `"+229480102662169"` |
| `"Rogerio Jose Da Silva (229480102662169@lid)"` | **inalterado** |
| `"Angela Tozi (260330953380002@lid)"` | **inalterado** |
| `"TI TOZI - Inovacao (GROUP)"` | **inalterado** |
| `"120363403758104643@g.us"` | `"120363403758104643"` |

Conclusões, e aqui **divirjo em parte do briefing**:

- A linha 187 é sim uma bifurcação real, mas **não é a chave do Sintoma A do dump**. O
  `(lid@lid)` do dump está no `content` da mensagem (achado #3), e essa função nunca toca em
  `content`. Ela só entraria em cena se o receptor mandasse o LID como `name` do contato.
- O `\z` a torna inútil para qualquer formato `Nome (jid)` — que é exatamente o formato que o
  receptor usa. Se um dia o participante virar contato próprio com esse nome, o LID passa direto.
- **Bug colateral:** um LID de 10-15 dígitos vira um falso telefone. `"229480102662169@lid"` →
  `"+229480102662169"`, indistinguível de um E.164 real na UI. (0 ocorrências hoje no banco:
  `name ~ '^\+\d{15}$'` = 0 — risco latente, não incidente ativo.)

### 6. FATO — `Waha::ApiService`: timeout de 8 s é menor que a resposta real da WAHA em sessão FAILED

`app/services/waha/api_service.rb:12-18`

```ruby
@base_url = ENV.fetch('WAHA_API_URL', 'http://localhost:3000')
@api_key  = ENV.fetch('WAHA_API_KEY', nil)
# Keep below Rack::Timeout (15s) so Net::ReadTimeout fires first…
@timeout  = 8
```

Aplicado a `read_timeout` e `open_timeout` (`:264-265`). **Não há retry no cliente** — o retry vive
nos jobs. Tratamento de erro (`:289-332`):

- `Net::OpenTimeout`/`Net::ReadTimeout` → `ConnectionError`
- `SocketError`/`ECONNREFUSED` → `ConnectionError`
- 401 → `AuthenticationError`; 404 → `NotFoundError`; **422 → `Error` genérico**
- 200 com body vazio → `{}` (silencioso)

Medição ao vivo hoje (GET, leitura):

```
GET /api/sessions?all=true                     → 200 em 0,29 s
GET /api/simplexteste/lids/…%40lid             → 422 em 10,33 s
GET /api/simplexteste/lids?limit=3&offset=0    → 422 em 10,32 s
    {"error":"Session status is not as expected…","status":"FAILED","expected":["WORKING"]}
```

**A WAHA leva 10,3 s para dizer "sessão FAILED"; nosso timeout é 8 s.** Nunca vemos o 422 — vemos
`Net::ReadTimeout`. Status das 12 sessões: 1 WORKING (`Simplex`), 1 STOPPED, **10 FAILED**.

Consequência observada no worker **hoje** (`journalctl -u chatwoot-worker.1`):

```
13:15:22  Retrying Contacts::ResolveLidJob … after 1 attempts in 5 seconds,
          due to a Waha::ApiService::ConnectionError (WAHA API timeout: Net::ReadTimeout…)
13:15:46  … after 2 attempts in 15 seconds …
13:16:24  … after 3 attempts in 30 seconds …
13:17:14  … after 4 attempts in 60 seconds …
13:18:34  … after 5 attempts in 120 seconds …
13:20:55  … after 6 attempts in 300 seconds …
```

Cada tentativa custa ~17 s de worker (2 chamadas × 8 s de timeout) e o ciclo reinicia a cada hora
pelo sweep. Alvo: `contact_inbox 4258` (`source_id` = UUID, `identifier` = `81820414494285957058@lid`).

`Waha::RefreshGroupsJob` na mesma janela: **23.422 ms** para varrer as sessões (uma responde, dez
estouram timeout).

### 7. FATO — `get_groups` já entrega o mapa LID→PN completo, e nós jogamos fora

`app/services/waha/api_service.rb:108-110`

```ruby
def get_groups(session_name)
  get("/api/#{session_name}/groups")
end
```

`app/jobs/waha/refresh_groups_job.rb:16-19`

```ruby
service = Waha::ApiService.new
session_names.each do |session_name|
  service.get_groups(session_name)                                   # :18  ← retorno DESCARTADO
  Rails.logger.info("[RefreshGroupsJob] Refreshed groups for session: #{session_name}")
```

O comentário do job (`:10-11`) explicita a intenção: *"WAHA populates LID mappings when groups are
fetched"* — a chamada é feita **só pelo efeito colateral no cache interno da WAHA**.

Payload real medido hoje (`GET /api/Simplex/groups`, 200 em 0,72 s, 240 KB):

```
78 grupos · 78 com Participants não-vazio · 932 participantes
932 participantes com LID **e** PhoneNumber no mesmo objeto (100%)
AddressingMode: {'lid': 78}   ·   DisplayName preenchido: 0   ·   ParticipantCount: 0 (campo zerado)
```

Primeiro grupo, recortado:

```json
{
  "JID": "120363023843937267@g.us",
  "Name": "Password Mídia",
  "AddressingMode": "lid",
  "IsAnnounce": false, "IsLocked": false,
  "Participants": [
    {"JID":"112652781121720@lid","PhoneNumber":"556699634471@s.whatsapp.net",
     "LID":"112652781121720@lid","IsAdmin":false,"IsSuperAdmin":false,"DisplayName":"","Error":0},
    {"JID":"163492342579288@lid","PhoneNumber":"556692223844@s.whatsapp.net",
     "LID":"163492342579288@lid","IsAdmin":true,"IsSuperAdmin":false,"DisplayName":"","Error":0}
  ],
  "ParticipantCount": 0, "MemberAddMode": "admin_add"
}
```

Ou seja: **lista de integrantes + flag de admin + LID→PN, tudo já disponível, já sendo buscado a
cada 30 min, e integralmente descartado.** Note também `PhoneNumber` no formato
`…@s.whatsapp.net` — que `whatsapp_user_jid?` (`inboxes_controller.rb:160-162`, só `@c.us`)
**rejeitaria**.

### 8. FATO — Não existe cache LID→PN nosso. Nenhum. Nem Redis, nem tabela.

`grep -rn "Rails.cache" app/ lib/ enterprise/ | grep -i "waha\|lid"` retorna só dois cooldowns:

- `app/jobs/waha/message_status_sync_job.rb:12-15` — `waha_msg_status_sync:<conv_id>`, TTL 3 s
- `app/jobs/waha/inbound_reconciler_job.rb:42-45` — `waha_inbound_reconciler:inbox:<id>`, TTL 2 min

Não há chave, TTL nem tabela de LID→PN. O "cache LID→PN" citado em toda a documentação é o cache
**interno da WAHA**, sobre o qual não temos controle nem visibilidade. Toda resolução é um
round-trip HTTP síncrono. Isso é a raiz do achado #6.

### 9. FATO — `ResolveLidJob`: sofisticado, mas cego para `@g.us`

`app/jobs/contacts/resolve_lid_job.rb`

Gate de entrada (`:43-47`):

```ruby
def needs_resolution?(contact_inbox, contact)
  contact_inbox.source_id.to_s.end_with?('@lid') ||
    contact.identifier.to_s.end_with?('@lid') ||
    contact.name.to_s.end_with?('@lid')
end
```

É **este** OR (o ramo `identifier`) que faz o 1:1 funcionar hoje, já que o `source_id` é UUID
(achado #2). Nenhum ramo olha `@g.us`.

Fonte do LID (`:58-64`): `source_id` se `@lid`, senão `contact.identifier`. Para um contato de
grupo, `identifier` é `…@g.us` → seria passado como se fosse LID ao endpoint `/lids/{lid}`. Não
chega lá porque `needs_resolution?` já barrou.

Atalho barato (`:51-56`): `pn_from_custom_attributes` só aceita `waha_whatsapp_jid` terminando em
`@c.us`. Para grupo o campo é `waha_whatsapp_chat_id = …@g.us` → não serve.

Backoff (`:6`): `[5,15,30,60,120,300,600]`, 7 tentativas, `queue_as :high`.
Guard anti-ruído (`:26-31`): `return if lid.blank?`, senão `raise LidNotResolvable`.

Três casos de merge (`:92-117`), todos bem documentados e testados: A) já existe `contact_inbox` com
`source_id == pn`; B) telefone já pertence a outro contato do account; C) caminho feliz inline.
Limpeza de resíduo pós-merge em `clear_residual_lid` (`:181-187`) — o `ContactMergeAction` faz
`deep_merge` e o contato base **herda** o `@lid` do mergee se tinha campo vazio.

### 10. FATO — `ResolveLidSweepJob`: a rede de segurança, também cega para `@g.us`

`app/jobs/contacts/resolve_lid_sweep_job.rb:44-54`

```ruby
ContactInbox.where(inbox_id: waha_inbox_ids).joins(:contact)
  .where('contact_inboxes.source_id LIKE :lid OR contacts.identifier LIKE :lid OR contacts.name LIKE :lid',
         lid: '%@lid')
```

Teto de 1.000 por rodada, excedente logado (`:33-35`) — bom padrão, sem truncamento silencioso.
Cron `15 * * * *`, fila `:scheduled_jobs` (`config/schedule.yml:88-91`).

Evidência de que roda e de que hoje só há 1 preso (o do achado #6):

```
jul 27 13:15:06  [ResolveLidSweepJob] presos=1 reenfileirados=1 restantes=0 teto=1000
```

O `LIKE '%@lid'` exige terminação exata. Um `contact.name` como
`"Rogerio José Da Silva (229480102662169@lid)"` **não é varrido** (termina em `)`), nem um
`identifier` `@g.us`.

### 11. FATO — `ContactInboxWithContactBuilder`: migração `@lid`→PN com N+1 latente

`app/builders/contact_inbox_with_contact_builder.rb:20`

```ruby
migrated = find_and_migrate_waha_lid_to_pn if waha_api_inbox? && source_id.present?
```

Roda em **toda** criação de contato em inbox WAHA (após o `find_by(source_id:)` falhar, `:17`).

`:125-142`:

```ruby
def find_and_migrate_waha_lid_to_pn
  target_phone = target_phone_for_waha_match
  return if target_phone.blank?
  inbox.contact_inboxes.where('source_id LIKE ?', '%@lid').find_each do |ci|   # :129
    contact = ci.contact                                                        # ← N+1
    effective_phone = waha_effective_phone_for(contact)
    next unless effective_phone.present? && phones_match?(effective_phone, target_phone)
    …
    ci.update!(source_id: source_id)                                            # :136
```

**Performance (medido nesta VM):**

```
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM contact_inboxes
  WHERE inbox_id = 8 AND source_id LIKE '%@lid';

Bitmap Heap Scan  (actual time=5.614..5.619 rows=0)
  Filter: (source_id ~~ '%@lid')
  Rows Removed by Filter: 3010
  Buffers: shared hit=163 read=4
```

O índice `index_contact_inboxes_on_inbox_id_and_source_id` cobre o `inbox_id`, mas o leading
wildcard força filtro linear sobre **todas** as linhas do inbox (3.010 na maior inbox local; 4.312
`contact_inboxes` no total). ~5,6 ms por criação de contato, escalando linearmente com o tamanho do
inbox — e **retornando 0 linhas em 100% dos casos hoje**, já que não existe nenhum `source_id @lid`
(achado #2). É custo puro. Se um dia houver muitos `@lid`, o `find_each` + `ci.contact` vira N+1.

**Armadilha:** `ci.update!(source_id: source_id)` (`:136`) sobrescreve o `@lid` pelo `source_id`
novo — que hoje é um **UUID**. Ou seja, este caminho pode *apagar* a marcação `@lid` do
`contact_inbox`, deixando o rastro só no `identifier`. Plausível explicação para os 0 `@lid` em
`contact_inboxes` conviverem com `identifier @lid`. (HIPÓTESE — não reproduzi.)

`waha_effective_phone_for` (`:160-166`) e `target_phone_for_waha_match` (`:144-151`) só reconhecem
`@c.us`. `@g.us` e `@s.whatsapp.net` não existem para eles.

### 12. FATO — `BrazilPhoneNormalizer`: onde é e onde NÃO é aplicado

`app/services/contacts/brazil_phone_normalizer.rb` — adiciona o 9º dígito em `+55` com 10 dígitos
pós-DDI, **exceto fixo** (primeiro dígito 2-5, `:16` e `:60-64`).

**Aplicado em:**
- `app/models/contact.rb:233` — callback `prepare_phone_number_attribute`, em todo save com mudança de `phone_number`
- `inboxes_controller.rb:148-154` (`normalize_waha_phone_number`) — **morto na prática** (achado #2)
- `resolve_lid_job.rb:84-90` — caminho vivo
- `contact_inbox_with_contact_builder.rb:114,156,171`
- `contacts_controller`, `whatsapp_validation_job`, `contactable_inboxes_service`, `campaigns/whatsapp/list_loader_service`, `meta/lead_ads`, `kanban/public_form_submission_service`, `spx/tozi/disparo_lead_job`

**NÃO aplicado em (relevante para grupo):**
- Em nada que venha de `@g.us` — o contato-grupo tem `phone_number` NULL, o callback não roda
- No `PhoneNumber` que vem em `Participants[]` do `get_groups` (formato `…@s.whatsapp.net`) — hoje nem lido
- No `voter` do `PollVoteService` (achado #14)
- No `content` das mensagens

> Nota: existe um segundo normalizador, `app/services/whatsapp/phone_normalizers/brazil_phone_normalizer.rb`,
> com spec próprio. Duplicação pré-existente; não investiguei divergência de comportamento. NÃO CONFIRMADO.

### 13. FATO — Helpers de front `isUnresolvedLid` / `getSafeContactName` são código morto desde o dia 1

Criados em `2548a34903` (25/03/2026), `app/javascript/dashboard/helper/commons.js:129` e `:138`.

```
$ grep -rn "isUnresolvedLid\|getSafeContactName" app/javascript/
app/javascript/dashboard/helper/commons.js:129:export const isUnresolvedLid = sourceId => {
app/javascript/dashboard/helper/commons.js:138:export const getSafeContactName = contact => {
app/javascript/dashboard/helper/commons.js:148:    isUnresolvedLid(sourceId) &&
```

**Três ocorrências, todas dentro do próprio arquivo de definição. Zero importadores.** A mensagem
do commit anuncia *"Frontend: helpers isUnresolvedLid/getSafeContactName mascaram LID na UI"* — eles
nunca foram plugados em componente nenhum. E mesmo se fossem: `getSafeContactName` só mascara
quando o nome casa `/^[a-z]+-[a-z]+-\d+$/` (placeholder do Haikunator) — não trata `Nome (lid@lid)`.

### 14. FATO — `PollVoteService` guarda o LID cru do votante

`app/services/waha/poll_vote_service.rb:127-129`

```ruby
def voter
  (vote[:from] || vote[:participant]).to_s
end
```

Persistido sem normalização em `content_attributes` (`:142`):
`{'poll_message_id' => …, 'selected_options' => […], 'voter' => voter}` e usado como chave de
dedupe em `latest_vote_message` (`:184`). O comentário em `:57-61` reconhece que o WAMID chega em
forma `@lid` (`"true_<lid>@lid_<MSGID>"`) enquanto guardamos `@c.us`.

É **a única menção a `participant` em todo o backend** — e vem do payload da WAHA, não de modelo nosso.

### 15. FATO — `WahaMessageResolvable` e os outros serviços: `@g.us` funciona por acidente

`app/services/messages/waha_message_resolvable.rb:176-188` (`chat_id`):
1. `contact.custom_attributes['waha_whatsapp_chat_id']` → para grupo devolve `…@g.us` ✓ (acidente feliz)
2. fallback `contact_inbox.source_id` se contém `@` → UUID não tem `@`, cai fora
3. último recurso `"#{phone}@c.us"` → grupo tem phone NULL → produz `"@c.us"` (lixo)

Mesmo padrão em `Waha::InboundReconcilerJob#chat_id_for` (`:126-138`) e
`Waha::MessageStatusSyncService#chat_id` (`:210-217`).

Já `Waha::OutboundSpecialMessageService#candidate_digits` (`:112-121`) explicitamente **exclui** `@g.us`:

```ruby
return str.split('@').first.to_s.gsub(/\D/, '') if /@(c\.us|s\.whatsapp\.net|lid)\z/.match?(str)
```

→ para um grupo, levanta `"destinatário sem número válido"` (`:97`). Enquete/localização/vCard
**não funcionam em grupo**.

### 16. FATO — Detecção de grupo existe em UM lugar só, e é para desviar a IA

`enterprise/app/services/captain/behavior/router_service.rb:36-49`, do commit `d787b46212`
(17/05/2026, Paulo Seze):

```ruby
def conversation_is_group?
  return true if @conversation.additional_attributes&.dig('type') == 'group'
  contact = @conversation.contact
  return false unless contact
  return true if contact.identifier.to_s.end_with?('@g.us')                       # :42
  custom = contact.custom_attributes || {}
  return true if custom['waha_whatsapp_chat_id'].to_s.end_with?('@g.us')          # :45
  return true if custom['waha_whatsapp_jid'].to_s.end_with?('@g.us')              # :46
  false
end
```

Só é consultado sob `skip_groups?` (`:69-73`). **Confirma o briefing: o sistema sabe desviar a IA de
grupos, mas não modela grupo.**

**Correção ao commit `d787b46212`:** ele afirma que `additional_attributes['type'] == 'group'` é *"o
sinal padrão do Chatwoot"*. Neste fork, `grep -rn "'group'" app/ enterprise/ lib/` encontra essa
string **apenas nesse arquivo** (mais um comentário não relacionado em `internal_channel.rb:24`).
Não há produtor nem outro consumidor. E no banco:

```sql
SELECT conv.additional_attributes::text, count(*) FROM conversations conv
JOIN contacts c ON c.id=conv.contact_id WHERE c.identifier LIKE '%@g.us' GROUP BY 1;
--  {}  → 85   (+4 com apenas orphan_alerted_at)
```

**Nenhuma conversa de grupo tem `type: 'group'`.** Se o upstream usa essa convenção, é NÃO
CONFIRMADO aqui — mas o campo está livre e seria o lugar natural para marcar.

### 17. FATO — Arqueologia de git: zero tentativas anteriores de tratar GRUPO

```
$ git log --all --oneline -S "@g.us" -- app/ enterprise/ lib/
d787b46212 fix(captain): detectar grupo via JID WAHA, nao so additional_attributes
01c8ecfa88 fix: contact phone/email not showing + remove @c.us from names
```

**Dois commits em toda a história.** O primeiro é o gate da IA (achado #16); o segundo só menciona
`@g.us` dentro da regex/comentário do `sanitize_waha_contact_name`. **Nenhuma linha jamais foi
escrita para modelar grupo, participante ou lista de integrantes.** Afirmação categórica.

Linha do tempo dos commits pedidos:

| commit | data | problema que atacava | funcionou? | dívida que sobrou |
|---|---|---|---|---|
| `b86bc3a4ab` "verificação de lid" | 17/02/26 | 1ª aparição do LID. Nasce `normalize_waha_contact_params` no controller público + rake de backfill (`lib/tasks/contacts_whatsapp_lid_backfill.rake`, 144 linhas) + `contactable_inboxes_service` | Parcial | Nasceu já atrás do gate `source_id.end_with?('@lid')` — que o receptor não alimenta (#2) |
| `01c8ecfa88` "contact phone/email not showing + remove @c.us from names" | 31/03/26 | Nome do contato exibindo JID cru; `camelcaseKeys` quebrando `phone_number` na store Vue | Sim, para `"5511…@c.us"` | `\z` na regex (#5); LID vira falso `+telefone`; nada para `Nome (jid)` |
| `06ede7dd32` "dedup de conversas + retry de LID" | 18/03/26 | LID não resolvia na 1ª tentativa → contato/conversa duplicados. Nasce `ResolveLidJob` (81 linhas) e o enfileiramento no controller. Remove índice unique que não funcionava com subquery no PG | Sim | Retry pendurado no controller — que hoje não roda (#2). Índice unique de dedup nunca voltou |
| `2548a34903` "resolver LID definitivamente com retry agressivo e refresh de grupos" | 25/03/26 | Backoff de 8 h era lento demais → 5 s-600 s/7x, fila `:high`, broadcast ActionCable, merge via `ContactMergeAction`. Nasce `get_groups` + `RefreshGroupsJob` | Sim para 1:1 | **"definitivamente" não foi**: `ddab9d387a` teve que voltar 3 meses depois. `get_groups` nasce com o retorno descartado (#7). Helpers de front nascem mortos (#13) |
| `ddab9d387a` "mescla LID em conflito de telefone + re-sweep" | 30/06/26 | Migração `api.chatspx.app`→`wapi.chatspx.app` zerou o cache da WAHA; jobs esgotaram 7 tentativas e morreram sem reagendamento. Nasce `ResolveLidSweepJob` + runbook + 4 specs | Sim — é o que sustenta o 1:1 hoje | Sweep também cego para `@g.us` (#10). Sem cache local, o problema-raiz continua (#8) |
| `42e356b8eb` "silencia ruído de LID vazio + guard blocked? nil" | 09/07/26 | ~3.482 eventos/dia no GlitchTip de `ResolveLidJob` em LID degenerado + ~1.380/dia de `NoMethodError` em `blocked?` de conversa órfã. Nasce `LidNotResolvable` + `excluded_exceptions` | Sim para o sintoma nomeado | Silenciou a exceção **errada** — ver #18 |

### 18. FATO/HIPÓTESE — A observabilidade silencia a exceção que não é mais o problema

`config/initializers/sentry.rb:10-11`

```ruby
config.excluded_exceptions += ['Rack::Timeout::RequestTimeoutException', 'Waha::ApiService::LidNotResolvable']
```

`LidNotResolvable` (`api_service.rb:10`) é levantada em `resolve_lid_job.rb:31` quando a WAHA
responde mas não conhece o LID. **Mas o erro que o worker está gerando agora é
`Waha::ApiService::ConnectionError`** (achado #6) — que **não** está excluído e sobe ao GlitchTip a
cada tentativa, 7 por LID por hora por sessão FAILED. Com 10 sessões FAILED, isso é volume.

HIPÓTESE (não confirmada): parte do volume atual do GlitchTip nos projetos WAHA é esse
timeout, não `LidNotResolvable`. **Não consegui confirmar** — ver Lacunas.

Log de aviso do controller (`inboxes_controller.rb:59`):
`"WAHA LID resolved to null for … (inbox_id=…)"` — **zero ocorrências** em 3 dias de journal,
consistente com o achado #2 (o método nunca chega lá).

### 19. FATO — Cobertura de testes: o caminho crítico está descoberto

`spec/services/waha/api_service_spec.rb` (7.454 bytes) cobre exatamente:
`#send_location`, `#send_contact_vcard`, `#send_text_with_vcard`, `#build_vcard`, `#send_list`,
`#send_poll`, `#send_text`.

**Não cobertos: `get_lid_phone_number`, `get_lids_list`, `get_groups`, `check_contact_exists`,
`create_chatwoot_app`, `get_messages`** — ou seja, todo o pipeline de LID e de grupo.

`spec/jobs/contacts/resolve_lid_job_spec.rb` (4 contextos, bem escritos): **todos** os fixtures
setam `custom_attributes: {'waha_whatsapp_jid' => '5511999999999@c.us'}`, o que faz o job resolver
pelo atalho `pn_from_custom_attributes` (`:51-56`) e **nunca exercitar a chamada HTTP**. O caminho
`resolve_lid_via_waha` → `get_lid_phone_number` → fallback `get_lids_list` **não tem teste algum**.

`spec/controllers/public/api/v1/inbox/contacts_controller_spec.rb` (51 linhas): zero menção a
waha/lid/normalize/sanitize. `spec/builders/contact_inbox_with_contact_builder_spec.rb`: zero
menção a waha/lid.

**Fixtures/cassettes de payload WAHA: NÃO EXISTEM.** `find spec/ -iname "*waha*" -o -iname "*cassette*"`
retorna apenas o diretório `spec/services/waha`. `spec/fixtures/` não tem nada de WAHA. **Não há
nenhum payload de grupo salvo no repositório** — o JSON do achado #7 (colhido ao vivo hoje) é, até
onde vi, o primeiro payload de grupo real documentado neste projeto.

Nenhum spec em todo o repo exercita mensagem de grupo. As 3 ocorrências de `@g.us` em spec estão em
`spec/enterprise/services/captain/behavior/router_service_spec.rb:44-57` — e testam apenas que a IA
**pula** o grupo.

### 20. FATO — Divergências doc × código

| Doc | Afirma | Realidade |
|---|---|---|
| `docs/waha-lid-normalizacao.md:25` | *"Ao receber `contact_id` ou `source_id` terminando em `@lid`, o controller público chama a WAHA"* | Verdadeiro como código, **falso como comportamento**: nenhum `source_id` termina em `@lid` (#2). A doc descreve um caminho morto e **omite completamente** o `ResolveLidJob`/`SweepJob`, que é o que realmente funciona |
| `docs/waha-lid-normalizacao.md:39-47` "Arquivos principais" | Lista só `api_service.rb` e `inboxes_controller.rb` | Faltam `resolve_lid_job.rb`, `resolve_lid_sweep_job.rb`, `refresh_groups_job.rb`, `contact_inbox_with_contact_builder.rb`. Doc de 47 linhas escrita antes de metade do sistema existir |
| `docs/waha-lid-normalizacao.md:20` | *"'Get all groups' podem ajudar a popular o mapeamento de LIDs"* | Subestima brutalmente: `get_groups` **entrega o mapa pronto** (#7), não só "ajuda a popular" |
| `docs/runbook-waha-migration-lid-warmup.md:22-24` | Incidente `api.chatspx.app` → `wapi.chatspx.app` | O `.env` desta VM aponta para `https://waha.simplexsolucoes.com.br` — **um terceiro host**, não citado em doc nenhuma. Os comandos `curl` do runbook (`$WAHA_API_URL`) funcionam, mas a narrativa está desatualizada |
| `docs/runbook-waha-migration-lid-warmup.md:118` | *"Critério de sucesso: as três contagens tendem a 0"* | Contagens hoje: `ci_source_id=0`, `contact_identifier=1`, `contact_name=0`. **O critério não detecta grupo**: 36 `identifier @g.us` passariam como "sucesso" |
| `docs/runbooks/waha-anti-oom-plan.md:1` | VM `cyaws (100.49.191.224)`, 17 sessões / 14 WORKING | Host atual é outro; sessões hoje: 12 total, **1 WORKING, 10 FAILED, 1 STOPPED**. Doc de 27/05 desatualizada |
| `deployment/runbook-waha-inbound-reconciler.md:8-10` | Pré-requisito PENDENTE: índice unique parcial em `messages(inbox_id, source_id)` | Continua pendente. Somado a #3 (100% das incoming WAHA sem `source_id`), a dedup do reconciler para grupo depende **inteiramente** da heurística content+timestamp |
| `docs/waha-failure-reporting.md` | Descreve contrato do `chatwoot-waha-app` externo | Coerente com o código. **Confirma que existe um app externo com contrato próprio** — o suspeito nº 1 do achado #4 |

---

## VEREDITO — por que uma mensagem de GRUPO não passa pela normalização de LID

Sete bifurcações, na ordem em que o payload as encontra. As três primeiras são fatais sozinhas.

**B1 — O contato do grupo nasce com `source_id` UUID.**
`app/controllers/public/api/v1/inboxes/contacts_controller.rb:8` — `params[:source_id] || SecureRandom.uuid`.
O receptor manda o JID em `identifier`, não em `source_id`. Evidência: 30/30 UUID (#2).

**B2 — Early-return por `source_id` que não termina em `@lid`.**
`app/controllers/public/api/v1/inboxes_controller.rb:37` — `return … unless waha_lid?(source_id)`,
com `waha_lid?` = `end_with?('@lid')` (`:156-158`). Um UUID sai aqui. Um `@g.us` também sairia.
**Esta é a bifurcação central, e ela já mata o 1:1 também.**

**B3 — A mensagem não tem campo para o participante.**
`app/controllers/public/api/v1/inboxes/messages_controller.rb:81` — `sender: @contact_inbox.contact`;
`permitted_params` (`:70-72`) aceita só `content`, `echo_id`, `source_id`. Mesmo que B1 e B2 fossem
resolvidas, **não há onde escrever o LID do participante** para depois resolvê-lo. Por isso o
receptor o embute no `content` (#3) — e por isso o LID aparece na UI mesmo com o nome já resolvido.

**B4 — Se B1/B2 fossem corrigidas, `@g.us` ainda seria rejeitado em cascata:**
- `whatsapp_user_jid?` (`inboxes_controller.rb:160-162`) → só `@c.us`; rejeita `@g.us` **e** o
  `…@s.whatsapp.net` que vem no `Participants[]` do `get_groups`
- `needs_resolution?` (`resolve_lid_job.rb:43-47`) → três testes, todos `@lid`
- `pn_from_custom_attributes` (`resolve_lid_job.rb:51-56`) → só `@c.us`
- `stuck_contact_inboxes` (`resolve_lid_sweep_job.rb:51-53`) → `LIKE '%@lid'` nos três campos
- `waha_effective_phone_for` / `target_phone_for_waha_match`
  (`contact_inbox_with_contact_builder.rb:160-166`, `:144-151`) → só `@c.us`

**B5 — O único ponto de limpeza textual é cego para o formato usado.**
`sanitize_waha_contact_name` (`inboxes_controller.rb:187`) ancora em `\z`; `"Nome (lid@lid)"`
termina em `)`. E ela nunca vê `content` — só `contact_attributes[:name]`.

> **Confirmação independente:** o W1 (`01-cadeia-ingestao.md`), partindo do código do **receptor
> externo** e não do nosso, chegou às mesmas B1/B2/B3: *"contato de grupo vem com
> `identifier = <id>@g.us` e sem `source_id` (o Rails gera UUID), por isso a normalização LID→PN de
> `inboxes_controller.rb` nunca roda em grupo"*. Ele acrescenta o dado que eu não tinha: a
> concatenação `${name} (${participant})` acontece **antes** de chegar ao Rails, e `toCusFormat`
> (`src/core/utils/jids.ts:159`) deixa o `@lid` passar sem resolver. Ou seja: **B3 não é só falta de
> campo nosso — o receptor já perdeu a separação entre nome e LID na origem.** Isso reforça a
> dívida 6: a app WAHA permite override de template (`config.templates` em `POST /api/apps`), o que
> some com o `👥` mas **não** com o `(@lid)`, porque o template recebe `participant` já concatenado.

**B6 — Não é outro controller.** Descartei a hipótese: `Webhooks::WahaController`
(`webhooks/waha_controller.rb`, rota `POST /webhooks/waha/:session_name`) só trata **votos de
enquete** e delega a `Webhooks::WahaEventsJob` (17 linhas). O inbound de conversa — 1:1 e grupo —
entra **pela mesma rota pública** `Public::Api::V1::Inboxes::*`. Não há bifurcação de roteamento;
a bifurcação é de **formato de dado** (B1/B2).

**B7 — Sem cache local, mesmo corrigido, o caminho seria caro e frágil.**
Sem cache (#8), cada participante de cada mensagem de grupo custaria um round-trip de até 8 s
(#6). Um grupo de 100 pessoas destruiria a fila `:high`. **Qualquer solução de grupo precisa
persistir o mapa antes de resolver por demanda** — e o mapa já vem de graça no `get_groups` (#7).

---

## Dívidas e armadilhas (o que uma implementação de grupos vai quebrar se ignorar)

1. **Não "consertar" `waha_lid?` para aceitar `@g.us`.** O `@g.us` **não é um LID** — é o
   endereço do chat. Passá-lo a `GET /api/{session}/lids/{id}` é semanticamente errado e vai
   gerar 404/422 em loop com o backoff de 7 tentativas (`resolve_lid_job.rb:6`). O LID a resolver
   é o do **participante**, que hoje não chega ao Rails.

2. **Não mexer em `sanitize_waha_contact_name` sem cuidar do falso `+telefone`.** Trocar `\z` por
   busca global faz `"Nome (229480102662169@lid)"` virar `"Nome (229480102662169)"`, mas
   `"229480102662169@lid"` sozinho já vira hoje `"+229480102662169"` (`:190`), indistinguível de um
   E.164 real. Qualquer relaxamento da âncora amplia essa superfície. Guardar o LID em campo
   próprio antes de limpar texto.

3. **`ContactInboxWithContactBuilder#find_and_migrate_waha_lid_to_pn` roda em toda criação de
   contato em inbox WAHA** (`:20`) e faz varredura linear `LIKE '%@lid'` (`:129`, 5,6 ms / 3.010
   linhas hoje, N+1 latente em `ci.contact`). Se grupos passarem a criar um contato por
   participante, essa função será chamada N vezes por grupo. **Precisa de um guard por tipo de JID
   ou de um índice apropriado antes de qualquer feature de grupo.** Pior: `ci.update!(source_id: source_id)`
   (`:136`) pode substituir um `@lid` por um UUID, escondendo o registro do `SweepJob`.

4. **`ResolveLidSweepJob` tem teto de 1.000/rodada** (`:23`). Persistir participantes vai multiplicar
   candidatos por ordens de grandeza. O log de excedente existe (`:33-35`) mas **ninguém monitora**.
   Reavaliar teto e frequência (hoje `15 * * * *`) junto com a feature.

5. **O timeout de 8 s (`api_service.rb:17`) é menor que a resposta real da WAHA em sessão FAILED
   (10,3 s medidos).** Isso não é hipotético: há um retry-loop rodando agora (#6). Uma feature de
   grupo que chame a WAHA por participante vai **multiplicar** esse loop. Ou sobe o timeout, ou
   trata sessão FAILED antes de chamar (`get_session(name)['status'] == 'WORKING'`), ou — melhor —
   não chama por participante (item 6).

6. **`get_groups` já entrega o mapa completo e é descartado** (`refresh_groups_job.rb:18`).
   932 pares LID→PN + `IsAdmin` + `Name` do grupo em uma chamada de 0,72 s / 240 KB, a cada 30 min.
   **Ignorar isso e implementar resolução por participante sob demanda é o erro mais caro
   disponível.** Atenção: `PhoneNumber` vem como `…@s.whatsapp.net`, formato que **nenhum** helper
   atual reconhece (todos testam `@c.us`); e `DisplayName` vem vazio (0/932) — o nome do
   participante **não** está aqui, precisa vir de outra fonte.

7. **`ParticipantCount` vem 0 em 100% dos grupos** enquanto `Participants[]` tem os dados. Não usar
   esse campo como fonte de verdade; contar o array.

8. **`Waha::OutboundSpecialMessageService#candidate_digits` (`:115`) rejeita `@g.us`** →
   `"destinatário sem número válido"` (`:97`). Enquete, localização e vCard **quebram em grupo hoje**.
   Se a feature de grupo habilitar esses botões na UI, o erro aparece para o agente.

9. **`Waha::InboundReconcilerJob` reinjeta o `body` cru** (`:144-146`, `:98-111`). Se ligado
   (`WAHA_RECONCILER_ENABLED`, hoje OFF) em conta com grupo, as mensagens reinjetadas virão **sem**
   o prefixo `👥 *Nome (...)*` que o receptor adiciona → **duas formatações diferentes na mesma
   conversa**, e a dedup por content+timestamp (`:89-96`, janela ±900 s) **não vai casar** porque o
   texto difere do que o receptor gravou. Risco alto de duplicata. O próprio job já comenta que
   "GOWS #1968 returns empty/422 for some groups" (`:11-12`).

10. **`PollVoteService#voter` (`:127-129`) guarda o LID cru** e o usa como chave de dedupe
    (`:184`). Se a normalização de LID passar a rodar em grupo, votos antigos (chave `@lid`) e
    novos (chave `@c.us`) deixam de casar → mensagens de voto duplicadas na conversa.

11. **Helpers de front `isUnresolvedLid`/`getSafeContactName` (`commons.js:129,138`) são código
    morto** (#13). Ou plugar, ou apagar — mas não presumir que já protegem a UI. E não protegem o
    formato `Nome (lid@lid)`, nem tocam em `content`.

12. **`additional_attributes['type'] = 'group'` está livre e é o slot natural** para marcar a
    conversa. O `RouterService` (`:37`) **já lê esse campo**. Setá-lo é a mudança de menor risco
    para tornar grupo detectável server-side — mas confira: nenhuma conversa de grupo o tem hoje
    (85 com `{}`), e o Captain hoje depende do fallback `@g.us` do `identifier`. Se alguém "limpar"
    o `identifier` do contato-grupo achando que é lixo LID, **o gate da IA cai e a Clara volta a
    responder em grupo** — o bug que `d787b46212` consertou.

13. **Zero cobertura de teste no caminho HTTP.** `resolve_lid_job_spec` sempre resolve pelo atalho
    de `custom_attributes` (#19). Não existe fixture nem cassette de payload WAHA no repositório.
    Qualquer refactor do `resolve_lid_via_waha` / `get_lids_list` sai **sem rede**.

14. **`docs/waha-lid-normalizacao.md` descreve o caminho morto e omite o vivo** (#20). Quem ler a
    doc para implementar grupo vai instrumentar o controller — e não vai acontecer nada.

15. **A observabilidade está silenciando a exceção errada** (`sentry.rb:11` exclui
    `LidNotResolvable`; o ruído atual é `ConnectionError`). Antes de medir o impacto de qualquer
    mudança de grupo, arrumar isso — senão o sinal fica enterrado.

---

## Lacunas / o que não consegui verificar

- **GlitchTip: NÃO CONSEGUI ACESSAR.** `mcp__glitchtip__glitchtip_issues` (status `unresolved` e
  `all`) retorna `"Either token or session ID is required"` — o MCP existe mas está sem credencial
  nesta sessão. Não levantei nenhum número real de erro. As frequências do commit `42e356b8eb`
  (3.482/dia e 1.380/dia) são citação do commit message, **não medição minha**.

- **`log/production.log` é inútil** (630 bytes, última escrita jan/2026). Os logs reais vão para
  journald (`chatwoot-web.1.service`, `chatwoot-worker.1.service`). Consegui o achado #6 via
  `journalctl -g`, mas a varredura de 30 dias por `Started POST "/public` **estourou timeout**
  (150 s) sem resultado — e a janela de 2 dias retornou `-- No entries --`. Isto é esperado: com 10
  de 12 sessões FAILED, **esta VM praticamente não recebe inbound WAHA**. **Não observei uma
  requisição real do receptor externo**; tudo sobre o formato do payload dele é inferência a partir
  do estado do banco (achados #2, #3, #4).

- **Produção (Tozi .109) não foi tocada** (blindagem). O dump do usuário é de lá. Todas as
  contagens são de homologação e podem não representar a frota. Especificamente: NÃO CONFIRMADO que
  na Tozi o `source_id` também seja sempre UUID.

- **Não li o código do receptor externo** (`chatwoot-waha-app`, dentro do container WAHA). Ele é o
  autor mais provável de `👥`, `(GROUP)` e do `(lid@lid)` no `content`, mas **não tenho prova
  direta** — só a ausência das strings no nosso repo e a evolução do formato ao longo do tempo
  (#4). Identificar o autor é tarefa do W1.

- **`lib/tasks/contacts_whatsapp_lid_backfill.rake`** (144 linhas, de `b86bc3a4ab`) — citado no
  runbook, não auditado em profundidade por caber melhor em outro escopo.

- **Divergência entre `Contacts::BrazilPhoneNormalizer` e
  `Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer`** (dois normalizadores, dois specs) — não
  comparei comportamento. NÃO CONFIRMADO se são equivalentes.

---

## Implicações para a solução

**Habilita:**

1. **O mapa LID→PN já existe e é grátis** (#7). Persistir `Participants[]` do `get_groups`
   (LID, PhoneNumber, IsAdmin, JID do grupo) resolve, de uma só tacada: o Sintoma B (lista de
   integrantes), a resolução de LID **sem round-trip** e a origem dos dados para exibir o
   participante por mensagem. `RefreshGroupsJob` já roda a cada 30 min — a mudança mínima é
   **parar de descartar o retorno**.
2. **O `identifier` `@g.us` já é chave de dedup estável** (`find_contact_by_identifier`,
   builder `:96-100`) — 36 contatos-grupo consistentes, com múltiplos `contact_inboxes` apontando
   para o mesmo contato. O modelo "contato = grupo" **já funciona**; falta o participante.
3. **`additional_attributes['type']` está livre e o Captain já o lê** (#16, dívida 12).
4. **Ganho visível mais barato**: o LID no texto é uma string no `content`. Uma limpeza de exibição
   (front) ou de ingestão (regex sobre `content` para extrair autor → `content_attributes`) tira o
   ruído da tela **sem** tocar em nada do pipeline de LID. Não requer WAHA, não requer migration.

**Impede / obriga a cuidado:**

5. **Não dá para "ligar" a normalização existente em grupo.** Ela está atrás de dois gates que o
   receptor não alimenta (B1/B2) e de um modelo de mensagem que não tem participante (B3). É
   preciso **mudar o contrato de ingestão** (receptor mandar o LID do participante em campo
   estruturado) **ou** parsear o que ele já manda no `content`. Não há terceira via dentro do
   Rails atual.
6. **Contato por participante é caro e perigoso** (dívidas 3, 4, 5). Se cada participante virar
   `Contact`, cada mensagem de grupo dispara o builder com varredura linear + possível round-trip.
   Preferir uma tabela própria de participantes (ou `custom_attributes` no contato-grupo) a
   reaproveitar `contacts`/`contact_inboxes`.
7. **Sessão FAILED é o estado normal desta VM hoje** (10/12). Qualquer teste de feature de grupo
   precisa usar a sessão `Simplex` (a única WORKING) — e qualquer código novo que chame a WAHA
   precisa tolerar 10 s de resposta ou checar status antes.
8. **Sem fixture de payload de grupo no repo** (#19). O JSON do achado #7 deveria virar a primeira
   fixture (`spec/fixtures/waha/groups.json`), anonimizado — é a base de teste que não existe.

---

## Referências

**Código (todos verificados nesta branch, `d985beeafd`):**
- `app/services/waha/api_service.rb` — `:10` LidNotResolvable, `:17` timeout=8, `:92-95` get_lid_phone_number, `:101-106` get_lids_list, `:108-110` get_groups, `:221-233` create_chatwoot_app, `:258-293` request, `:295-332` handle_response
- `app/controllers/public/api/v1/inboxes_controller.rb` — `:35-75` normalize_waha_contact_params, `:37` early-return, `:59` log null, `:84-94` extract_pn_from_custom_attributes, `:96-109` resolve_lid_to_pn, `:112-146` merge_waha_lid_contact_inbox_to_pn, `:148-154` normalize_waha_phone_number, `:156-158` waha_lid?, `:160-162` whatsapp_user_jid?, `:164-173` schedule_lid_retry, `:183-196` sanitize_waha_contact_name (`:187` regex)
- `app/controllers/public/api/v1/inboxes/contacts_controller.rb` — `:8` SecureRandom.uuid, `:9-13`, `:16`, `:18-22`
- `app/controllers/public/api/v1/inboxes/messages_controller.rb` — `:70-72` permitted_params, `:78-88` message_params (`:81` sender)
- `app/controllers/webhooks/waha_controller.rb` — `:9-18` (só poll votes)
- `app/builders/contact_inbox_with_contact_builder.rb` — `:17`, `:20`, `:96-100`, `:108-118`, `:120-122`, `:125-142` (`:129` LIKE, `:136` update), `:144-151`, `:160-166`
- `app/jobs/contacts/resolve_lid_job.rb` — `:6` backoff, `:26-31` guard, `:43-47` needs_resolution?, `:51-56`, `:58-64`, `:66-76`, `:92-117` merge_or_update, `:181-187` clear_residual_lid
- `app/jobs/contacts/resolve_lid_sweep_job.rb` — `:23` teto, `:33-35` log, `:44-54` stuck_contact_inboxes
- `app/jobs/waha/refresh_groups_job.rb` — `:8` fila, `:12-23` (`:18` retorno descartado)
- `app/jobs/waha/inbound_reconciler_job.rb` — `:11-12` comentário grupos, `:37-39` gate, `:89-96` dedup, `:98-111` inject, `:126-138` chat_id_for, `:144-146` extract_content
- `app/jobs/waha/message_status_sync_job.rb` — `:12-15` cooldown
- `app/services/messages/waha_message_resolvable.rb` — `:176-188` chat_id
- `app/services/waha/outbound_special_message_service.rb` — `:90-108` chat_id, `:112-121` candidate_digits (`:115` regex sem @g.us)
- `app/services/waha/poll_vote_service.rb` — `:57-61` comentário LID, `:127-129` voter, `:142`, `:184`
- `app/services/contacts/brazil_phone_normalizer.rb` — `:16` landlines, `:26-32`, `:60-64`
- `app/models/contact.rb:229-234` — callback de normalização
- `enterprise/app/services/captain/behavior/router_service.rb` — `:32-49` conversation_is_group?, `:69-73` skip_groups?
- `app/javascript/dashboard/helper/commons.js` — `:129` isUnresolvedLid, `:138-155` getSafeContactName (sem importadores)
- `config/schedule.yml:79-100` — crons WAHA
- `config/initializers/sentry.rb:10-11` — excluded_exceptions

**Docs auditadas:** `docs/waha-lid-normalizacao.md`, `docs/runbook-waha-migration-lid-warmup.md`,
`docs/waha-failure-reporting.md`, `docs/runbooks/waha-anti-oom-plan.md`,
`deployment/runbook-waha-inbound-reconciler.md`

**Commits:** `b86bc3a4ab` (17/02), `06ede7dd32` (18/03), `2548a34903` (25/03), `01c8ecfa88` (31/03),
`d787b46212` (17/05), `ddab9d387a` (30/06), `42e356b8eb` (09/07), `af53584c25` (07/07),
`c02dfaa024`/`cfeb6f4d4f`, `6a905e0680`

**Relatórios irmãos consultados:** `plano/pesquisa-grupos-waha/01-cadeia-ingestao.md` (W1 — origem
externa das strings; convergência registrada nos achados #4 e no veredito).

**Specs:** `spec/services/waha/api_service_spec.rb`, `spec/jobs/contacts/resolve_lid_job_spec.rb`,
`spec/jobs/contacts/resolve_lid_sweep_job_spec.rb`,
`spec/enterprise/services/captain/behavior/router_service_spec.rb:44-57`

**Medições ao vivo (2026-07-27, somente GET / SELECT):**
- `GET https://waha.simplexsolucoes.com.br/api/sessions?all=true` → 200 / 0,29 s / 12 sessões (1 WORKING)
- `GET /api/Simplex/groups` → 200 / 0,72 s / 240 KB / 78 grupos / 932 participantes com LID+PhoneNumber
- `GET /api/simplexteste/lids/…` → 422 / 10,33 s (sessão FAILED)
- `journalctl -u chatwoot-worker.1.service --since "3 days ago" -g "ResolveLid|RefreshGroups|LID"`
- SELECTs em `chatwoot_production` @ localhost (contagens de `contacts`, `contact_inboxes`,
  `messages`, `conversations`; `EXPLAIN ANALYZE` do `LIKE '%@lid'`)
- Payload bruto salvo em `<scratchpad>/groups.json` (fora do repositório, não commitado)
