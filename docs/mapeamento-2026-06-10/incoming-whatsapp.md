# Mapeamento — Fluxo de entrada de mensagem WhatsApp Cloud (webhook → registro)

> Área: `incoming-whatsapp` · Data: 2026-06-10 · Branch lida: `paulao` (working tree local)
> Tudo abaixo é leitura real do código deste fork (app/ + enterprise/), com referências `arquivo:linha`.

---

## 1. Visão geral do pipeline

```
Meta Cloud API
  └─ POST /webhooks/whatsapp/:phone_number            config/routes.rb:665
      └─ Webhooks::WhatsappController#process_payload  app/controllers/webhooks/whatsapp_controller.rb:4-13
          └─ Webhooks::WhatsappEventsJob (queue :low)  app/jobs/webhooks/whatsapp_events_job.rb
              └─ Whatsapp::IncomingMessageWhatsappCloudService
                  (herda Whatsapp::IncomingMessageBaseService)
                  ├─ process_statuses  → atualiza delivered/read/failed por source_id
                  └─ process_messages
                      ├─ dedup (Message.source_id + Redis SET NX)
                      ├─ set_contact  → processed_waid → PhoneNumberNormalizationService
                      │                 → ContactInboxWithContactBuilder
                      ├─ set_conversation (lock_to_single_conversation)
                      └─ create_messages → Message incoming
                          └─ callbacks: reopen_conversation, hooks Captain,
                             MESSAGE_CREATED → listeners/automation
```

---

## 2. Webhook (controller)

**Rotas** — `config/routes.rb:664-665`:
- `GET  webhooks/whatsapp/:phone_number` → `webhooks/whatsapp#verify`
- `POST webhooks/whatsapp/:phone_number` → `webhooks/whatsapp#process_payload`

**`Webhooks::WhatsappController`** — `app/controllers/webhooks/whatsapp_controller.rb`:
- `verify` vem de `MetaTokenVerifyConcern` (`app/controllers/concerns/meta_token_verify_concern.rb:5-13`): responde o `hub.challenge` se `hub.verify_token` bater com `provider_config['webhook_verify_token']` do canal achado por `phone_number` da URL (`whatsapp_controller.rb:17-21`).
- `process_payload` (linhas 4-13): rejeita números listados em `GlobalConfig INACTIVE_WHATSAPP_NUMBERS` (linhas 23-32) e enfileira `Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)` devolvendo `200` imediato.
- ⚠️ **Não há validação de assinatura HMAC (`X-Hub-Signature-256`) no POST** — a “autenticação” do fluxo Cloud é só o verify token do GET de subscription. (O webhook de Lead Ads tem HMAC; este não.)

---

## 3. `Webhooks::WhatsappEventsJob` — roteamento pro canal

`app/jobs/webhooks/whatsapp_events_job.rb`:
- **Acha o canal** (`find_channel_from_whatsapp_business_payload`, linhas 86-101): se `params[:object] == 'whatsapp_business_account'`, usa `entry[0].changes[0].value.metadata.display_phone_number` (com `+` prefixado) e **valida que `phone_number_id` do payload bate com `provider_config['phone_number_id']`** do canal. Fallback: lookup pelo `:phone_number` da URL (linhas 80-84).
- **Descarta** se canal blank / `reauthorization_required?` / conta inativa (`channel_is_inactive?`, linhas 72-78).
- **Echo SMB** (coexistência com app WhatsApp Business): `field == 'smb_message_echoes'` → mesmo service com `outgoing_echo: true` (linhas 53-59).
- **Dispatch por provider** (linhas 61-68): `whatsapp_cloud` → `Whatsapp::IncomingMessageWhatsappCloudService`; default (360dialog) → `Whatsapp::IncomingMessageService`.
- **Não há override Enterprise** de nenhum desses services/jobs (grep em `enterprise/` por `IncomingMessage|PhoneNumberNormalization|ContactInboxWithContactBuilder` → zero resultados). Tudo é camada OSS.

---

## 4. `Whatsapp::IncomingMessageWhatsappCloudService`

`app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb`:
- `processed_params` = `params[:entry][0]['changes'][0]['value']` (linhas 7-9).
- `download_attachment_file` (11-19): GET na `media_url` com `api_headers`; **`inbox.channel.authorization_error!` se 401** (token expirado marca canal pra reautorização).
- Todo o resto vem do base service.

## 5. `Whatsapp::IncomingMessageBaseService` — o coração

`app/services/whatsapp/incoming_message_base_service.rb`:

### 5.1 Entrada (`perform`, linhas 9-17)
- Payload com `statuses` → `process_statuses` (47-53): acha `Message` por `source_id` (wamid) e atualiza `status` (sent/delivered/read/failed); em `failed`, grava `external_error = "código: título"` (55-62). *É daqui que o painel de campanha tira entregues/lidas/falhas (131026 etc.).*
- Payload com `messages` (ou `message_echoes`) → `process_messages`.

### 5.2 `process_messages` (linhas 26-45)
1. Skip de tipos não-processáveis: `reaction|ephemeral|unsupported|request_welcome` (`incoming_message_service_helpers.rb:46-48`).
2. **Dedup em 2 camadas**:
   - `find_message_by_source_id(wamid)` (`helpers:66-70`) — ⚠️ `Message.find_by(source_id:)` **global, sem escopo de conta/inbox**.
   - `lock_message_source_id!` (`helpers:72-76`) → `Whatsapp::MessageDedupLock` (`app/services/whatsapp/message_dedup_lock.rb`): Redis `SET NX EX` TTL 1 dia — evita corrida entre workers com retries da Meta.
3. `set_contact` → 5.3.
4. **Transação**: `set_conversation` + `create_messages` (41-44).

### 5.3 `set_contact_from_message` (linhas 112-129) — onde a ficha é resolvida
- `wa_id` vem de `processed_params[:contacts][0][:wa_id]`.
- `waid = processed_waid(wa_id)` (`helpers:50-52`) → **`Whatsapp::PhoneNumberNormalizationService#normalize_and_find_contact_by_provider(wa_id, :cloud)`** (ver §6).
- `ContactInboxWithContactBuilder.new(source_id: waid, inbox:, contact_attributes: { name: profile.name, phone_number: "+#{messages[0][:from]}" }).perform` (ver §7).
- `update_contact_with_profile_name` (218-233): troca o nome do contato pro ProfileName só se o nome atual é o próprio telefone.
- Echo (`set_contact_from_echo`, 97-110): contato vem do campo `to`.

### 5.4 `set_conversation` (linhas 131-142) — **o lock_to_single do incoming mora AQUI**
```ruby
@conversation = if @inbox.lock_to_single_conversation
                  @contact_inbox.conversations.last          # qualquer status, INCLUSIVE resolved
                else
                  @contact_inbox.conversations.where.not(status: :resolved).last
                end
return if @conversation
@conversation = ::Conversation.create!(conversation_params)
```
- `lock_to_single_conversation` é coluna boolean de `inboxes` (annotation `app/models/inbox.rb:19`; inbox 91 em prod = `true`).
- ⚠️ **Escopo POR FICHA (`@contact_inbox`), não por contato.** Se o mesmo contato tem 2 fichas, o incoming honra o “1 conversa” só dentro da ficha em que o wa_id caiu.
- `conversation_params` (`helpers:6-13`): só `account_id/inbox_id/contact_id/contact_inbox_id` — **sem `assignee_id`, sem `team_id`, sem `status`** → conversa nova criada por um reply nasce **`open` e NÃO ATRIBUÍDA** (a raiz do sintoma “Não atribuída, sem corretor”).

### 5.5 `create_messages` / `create_message` (linhas 64-87, 177-196)
- `message_type == 'contacts'` → uma Message por vCard; senão `create_regular_message`.
- `Message` construída com `message_type: :incoming`, `sender: @contact`, `status: :sent` (echo: `:outgoing`/`:delivered` pra não disparar `SendReplyJob`), `source_id` = wamid, `content` via `message_content` (`helpers:27-34`: `text.body` / `button.text` / `interactive.button_reply.title` / `interactive.list_reply.title` — **cliques de botão de HSM viram texto incoming normal**).
- `content_attributes[:referral]` guarda payload de anúncio click-to-WhatsApp (linha 194); `in_reply_to_external_id` para replies citados (helpers:62-64).
- Anexos: `attach_files` (144-162) baixa mídia; `attach_location` (164-175); contatos (198-216).

---

## 6. `Whatsapp::PhoneNumberNormalizationService` — variantes 12d/13d (CRÍTICO)

`app/services/whatsapp/phone_number_normalization_service.rb`:

```ruby
def normalize_and_find_contact_by_provider(raw_number, provider)   # linhas 14-31
  clean_number = extract_clean_number(raw_number, provider)        # :cloud → passa direto
  normalizer = find_normalizer_for_country(clean_number)           # Brazil (^55) ou Argentina
  return raw_number unless normalizer
  normalizer.variants(clean_number).each do |variant|              # ORDEM: [raw, com-9, sem-9]
    existing = find_existing_contact_inbox(format_for_provider(variant, provider))
    return existing.source_id if existing                          # ← PRIMEIRA ficha que casar VENCE
  end
  raw_number                                                       # contato novo → wa_id cru da Meta
end
```
- `find_existing_contact_inbox` = `inbox.contact_inboxes.find_by(source_id:)` (linha 43) — escopo correto por inbox.
- `Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer` (`app/services/whatsapp/phone_normalizers/brazil_phone_normalizer.rb`):
  - `normalize` (11-19): 12d → insere `9` depois do DDD → 13d.
  - `variants` (24-30): `[waid, with_nine, without_nine].compact.uniq` (`strip_ninth_digit`, 38-46).
- **Histórico do fork**: `variants` + loop de variantes foi introduzido em `56f7db0c6` (15/04/2026). Antes (upstream `f44e47a62`), o serviço só tentava **a forma normalizada 13d** e, se não achasse, retornava o raw. O commit está contido em `producao`, `homologacao` e `paulao` (`git branch -a --contains`).

**Comportamento resultante no incoming:**
| Estado das fichas | wa_id entregue | Resultado |
|---|---|---|
| 1 ficha (qualquer variante) | qualquer variante | Acha sempre (lookup pelas 2 formas). ✅ |
| 2 fichas (12d e 13d) | 12d | Vence a **12d** (raw é a 1ª variante) — pode ser a ficha “morta”. ⚠️ |
| 2 fichas | 13d | Vence a **13d**. ⚠️ idem |
| 0 fichas | qualquer | Retorna o raw → ficha nova criada **no formato que a Meta entrega**. ✅ |

---

## 7. `ContactInboxWithContactBuilder` — achar/criar Contact + ficha

`app/builders/contact_inbox_with_contact_builder.rb`:
- Linha 17-18: `inbox.contact_inboxes.find_by(source_id:)` — como o §6 já resolveu a variante, normalmente acha aqui.
- Se não achou ficha: `find_contact` (65-72) por identifier → email → **phone** → (Instagram). `find_contact_by_phone_number` (108-118):
  ```ruby
  contact = account.contacts.find_by(phone_number: phone_number)      # exato
  normalized = Contacts::BrazilPhoneNormalizer.normalize(phone_number) # SÓ adiciona o 9
  account.contacts.find_by(phone_number: normalized)
  ```
  ⚠️ **Assimétrico**: `Contacts::BrazilPhoneNormalizer` (`app/services/contacts/brazil_phone_normalizer.rb:22-27,45-51`) só converte +12d→+13d. Lookup com **+13d nunca tenta a forma +12d** → contato salvo como +12d não é achado por quem busca +13d → **cria CONTATO duplicado**.
- Criação: `create_contact` (54-63) + `ContactInboxBuilder` (41-48). `ContactInboxBuilder#wa_source_id` (`app/builders/contact_inbox_builder.rb:56-61`) = `contact.phone_number.delete('+')` quando não recebe `source_id` explícito — **derivado do phone armazenado, sem reconciliar variantes**.
- Race: `rescue ActiveRecord::RecordNotUnique` → retry (linhas 12-14); colisão de source_id com outro contato renomeia a ficha velha (`contact_inbox_builder.rb:88-105`).

---

## 8. Onde decide conversa nova vs. reusar — TRÊS implementações

| Caminho | Arquivo:linha | Escopo | Comportamento |
|---|---|---|---|
| **Incoming WhatsApp** | `incoming_message_base_service.rb:131-142` | **por FICHA** | lock_to_single → `conversations.last` (até resolved); senão última não-resolvida; cria sem assignee |
| **ConversationBuilder** (UI/API “Nova conversa”, campanhas nativas) | `app/builders/conversation_builder.rb:27-39` | **por CONTATO** (`inbox_id`+`contact_id`) | prioriza não-resolvida, fallback mais recente de qualquer status; com lock Redis `conv_builder:{inbox}:{contact}` TTL 10s (12-25) |
| **DisparoLeadJob (pós-fix)** | `app/jobs/spx/tozi/disparo_lead_job.rb:121-143` | **por CONTATO** | igual ao ConversationBuilder + `open!` + reatribui corretor |

- A migration `db/migrate/20260317214100_deduplicate_conversations_and_add_constraint.rb` fez **dedup one-shot** (resolve duplicatas de inbox lock_to_single) mas — apesar do nome — **não criou constraint de unicidade**; nada no banco impede 2 convs abertas pro mesmo contato.
- **Divergência real**: incoming é por ficha; builder é por contato. Com 2 fichas, o incoming pode criar conversa nova mesmo havendo conversa viva na outra ficha do MESMO contato.

---

## 9. Anatomia do bug das duplicatas de disparo (e o fix)

### O job ANTES do fix (`git show 11b913531^:app/jobs/spx/tozi/disparo_lead_job.rb`)
- `source_id: phone.delete('+')` com `phone` já passado por `Contacts::BrazilPhoneNormalizer` → **SEMPRE 13d** (formato “nosso”).
- `Conversation.create!` **incondicional** → 1 conversa nova por disparo, violando o lock_to_single da inbox 91 por construção.

### Cenário (a) — 2 fichas / 2 contatos (203 contatos em prod)
1. Contato antigo já tinha ficha **12d** (histórico orgânico: pra números legados a Meta entrega `wa_id` sem o 9; antes de `56f7db0c6` o incoming retornava o raw e criava ficha 12d).
2. Disparo: builder não acha ficha por source_id 13d; `find_contact_by_phone_number(+13d)` não acha o contato +12d (assimetria §7) → **novo contato + nova ficha 13d + conversa atribuída ao corretor**.
3. Lead responde dias depois: Meta entrega `wa_id` 12d → §6 testa `[12d, 13d]` → **a ficha 12d ANTIGA vence** (primeira variante) → `set_conversation` reusa/cria conversa naquela ficha → **conversa sem o histórico do disparo e sem corretor**; se reabriu resolved, o evento `CONVERSATION_OPENED` (`app/models/conversation.rb:380-385`) disparou a AutomationRule #53 (“iniciar zerado”, dado de prod) que zera assignee/team → “Não atribuída”.

### Cenário (b) — 2+ conversas na mesma ficha (72 contatos)
Mesmo com ficha única, o `Conversation.create!` incondicional criava conversa nova a cada disparo/redisparo; o reply caía em `conversations.last`, que podia não ser a do corretor.

### O fix `11b913531` (frente 1 — origem)
- `resolved_source_id` (`disparo_lead_job.rb:112-116`): roda o **mesmo** `PhoneNumberNormalizationService` do incoming → o disparo passa a usar a ficha que o reply usaria.
- `find_or_create_conversation` (121-143): reusa a conversa única **por contato**, reabre (`open!`), reatribui corretor, seta `campaign_id` se faltava; cria só se o contato nunca teve conversa.
- ⚠️ **Status de deploy**: commitado local/`paulao`; STATE registra que o job em prod (AWS) está ATRÁS do repo e o patch cirúrgico ainda depende de aval — ou seja, **a origem só está consertada no repo, não necessariamente no runtime de prod**.
- A consolidação de dados (frente 2, `scripts/spx/tozi/consolida_conversas_duplicadas.rb`) zerou as duplicatas existentes (275 contatos), então o caminho de incoming hoje opera no caso “1 ficha” (seguro).

---

## 10. Risco residual no caminho de incoming

1. **First-match nas variantes** (`phone_number_normalization_service.rb:24-28`): se um contato voltar a ter 2 fichas (por QUALQUER caminho), o incoming roteia pra primeira variante que casar, não pra “thread viva”. Já documentado com proposta pronta em `docs/backlog/reconciliador-incoming-9-digito.md` (escolher a ficha da conversa mais recente; early-return quando há 1 ficha). Prioridade baixa porque as fontes foram fechadas — mas é o único guarda-corpo que faltaria.
2. **Fontes vivas de ficha em formato “próprio” (sem passar pelo normalizador de variantes):**
   - `ContactInboxBuilder#wa_source_id` (`contact_inbox_builder.rb:60`) — “Nova conversa” pela UI / API gera source_id do `contact.phone_number`; se o phone armazenado é +12d e a ficha real é 13d (ou vice-versa), nasce a 2ª ficha.
   - `Contacts::ContactableInboxesService#whatsapp_contactable_inbox` (`app/services/contacts/contactable_inboxes_service.rb:50-56`) — mesmo padrão (`phone.delete('+')`).
   - **`Meta::LeadAds::CreateConversationService#source_id_for` (`app/services/meta/lead_ads/create_conversation_service.rb:98-109`)**: pra inbox **Cloud** com phone presente retorna `phone` **COM o `+`** (`"+5566..."`). Source_id com `+` **nunca casa** com o formato dígitos do incoming nem com as `variants` (que são só dígitos) → quando o hook de Lead Ads for apontado pra inbox 91, **cada lead vira ficha órfã** e o primeiro reply cria ficha duplicada. Além disso `create_conversation` (111-123) é `Conversation.create!` incondicional (não honra lock_to_single). **Mesma classe de bug do disparo, ainda aberta.**
   - `set_contact_from_echo` (`incoming_message_base_service.rb:97-110`) usa `processed_waid` ✅, mas o `to` de echo pode vir em variante diferente do histórico — coberto pelas variants se houver 1 ficha.
3. **Contato novo com variante “instável”**: se a Meta entregar a 1ª mensagem num formato e mudar depois, as `variants` cobrem (a ficha existente é achada pela outra forma). Risco real ≈ zero **enquanto houver no máximo 1 ficha**.
4. **Assimetria do `find_contact_by_phone_number`** (`contact_inbox_with_contact_builder.rb:108-118`): lookup +13d não acha contato +12d → duplicação de **Contact** (não só ficha) por qualquer integração que crie contato com phone normalizado.
5. **Dedup global de `source_id` de Message** (`helpers:66-70`): `Message.find_by(source_id:)` sem escopo de conta — colisão teórica entre contas multi-tenant (wamid é globalmente único na Meta, então baixo risco prático).
6. **Sem HMAC no POST do webhook** (§2) — payload forjado só precisa conhecer a URL com o phone_number.

---

## 11. Downstream imediato (pós-registro) — relevante pra IA orquestradora

Após `Message.create` (transação do §5.2), `execute_after_create_commit_callbacks` (`app/models/message.rb:341-350`) roda:

1. **`reopen_conversation`** (`message.rb:443-452`): incoming em conversa snoozed → `open!`; **resolved → `reopen_resolved_conversation` (466-476)**:
   - `conversation.inbox.active_bot?` → **`pending!`** (espera o bot — é o “limbo” quando o bot existe mas não atende, ex.: whitelist da Clara);
   - senão → `open!`.
   - `active_bot?` OSS = AgentBot/dialogflow (`app/models/inbox.rb:172-175`); **Enterprise soma `captain_active?`** (assistant conectada + cota de respostas) — `enterprise/app/models/enterprise/inbox.rb:10-16`.
2. **`mark_pending_conversation_as_open_for_human_response`** (`message.rb:454-464`): stub OSS (`captain_pending_conversation?` → `false`), **MAS o overlay Enterprise implementa de verdade** (`enterprise/app/models/enterprise/message.rb:4-34`, via `Message.prepend_mod_with('Message')` em `message.rb:515`): resposta humana pública abre a pending de inbox com `CaptainInbox`, com guard `template_bootstrap_message?` (HSM bootstrap sem incoming não abre) e activity message. *(O STATE de 02/06 citava o stub OSS; no branch atual o override Enterprise existe — commits upstream `374d2258c`/`ac93290c9`. Conferir o que está rodando em prod.)*
3. **`dispatch_create_events`** (`message.rb:401-412`): `MESSAGE_CREATED` no dispatcher (→ listeners de automação, webhooks, Captain v2 via listener), `FIRST_REPLY_CREATED`, `waiting_since`.
4. **`execute_message_template_hooks`** (`message.rb:482-484`) → `MessageTemplates::HookExecutionService`; o override Enterprise (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:4-10`) injeta o Captain: `captain_active?` → `process_captain_behavior` (router/debounce/etc.), senão `perform_handoff`.
5. `CONVERSATION_OPENED` (`conversation.rb:380-385`) — gatilho das automation rules (a #53 de prod zera assignee aqui).

**Pontos de plug pra IA orquestradora** (eventos/serviços concretos):
- `MESSAGE_CREATED` / `FIRST_REPLY_CREATED` (dispatcher Wisper) — já usado pelo `Spx::Tozi::FunnelAutomationListener`.
- `MessageTemplates::HookExecutionService` (Enterprise) — ponto canônico onde “bot decide atender”.
- `reopen_resolved_conversation` — é A decisão open-vs-pending no retorno de lead; qualquer orquestração de triagem precisa dominar esse if.
- `set_conversation`/`conversation_params` — o fato de reply novo nascer `open` sem assignee é o gancho natural pra um serviço de triagem/atribuição (hoje preenchido só por automation rules).
- `processed_waid`/`PhoneNumberNormalizationService` — serviço reutilizável por QUALQUER componente que crie ficha (o disparo passou a usar; Lead Ads ainda não).

---

## 12. Arquivos-chave (resumo)

| Arquivo | Papel |
|---|---|
| `config/routes.rb:664-665` | Rotas GET verify / POST payload |
| `app/controllers/webhooks/whatsapp_controller.rb` | Recepção, filtro número inativo, enfileira job |
| `app/controllers/concerns/meta_token_verify_concern.rb` | Challenge verify_token |
| `app/jobs/webhooks/whatsapp_events_job.rb` | Acha canal (payload metadata), roteia cloud/360dialog/echo |
| `app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb` | Parser do payload Cloud + download mídia |
| `app/services/whatsapp/incoming_message_base_service.rb` | Núcleo: dedup, contato, conversa (lock_to_single em 131-142), mensagens, statuses |
| `app/services/whatsapp/incoming_message_service_helpers.rb` | processed_waid (50-52), conversation_params (6-13), dedup helpers |
| `app/services/whatsapp/message_dedup_lock.rb` | Redis SET NX TTL 1d por wamid |
| `app/services/whatsapp/phone_number_normalization_service.rb` | Resolve a ficha por variantes 12d/13d (first-match) |
| `app/services/whatsapp/phone_normalizers/brazil_phone_normalizer.rb` | normalize + variants + strip_ninth_digit |
| `app/builders/contact_inbox_with_contact_builder.rb` | find/create Contact + ficha (assimetria de phone em 108-118) |
| `app/builders/contact_inbox_builder.rb` | source_id derivado do phone (wa_source_id:56-61) |
| `app/builders/conversation_builder.rb` | lock_to_single por CONTATO (27-39) — caminho UI/API |
| `app/jobs/spx/tozi/disparo_lead_job.rb` | Disparo HSM; fix 11b913531: resolved_source_id (112-116) + find_or_create_conversation (121-143) |
| `app/jobs/spx/tozi/followup_hsm_job.rb` | HSM na conversa existente (não cria ficha/conversa) ✅ |
| `app/services/meta/lead_ads/create_conversation_service.rb:98-109,111-123` | ⚠️ source_id com `+` pra Cloud + Conversation.create! incondicional |
| `app/models/message.rb:341-350,443-476,515` | Callbacks pós-registro: reopen, pending, eventos, hooks |
| `enterprise/app/models/enterprise/message.rb` | Resposta humana abre pending de CaptainInbox |
| `enterprise/app/models/enterprise/inbox.rb:10-16` | active_bot? += captain_active? |
| `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb` | Entrada do Captain no fluxo |
| `db/migrate/20260317214100_...` | Dedup one-shot; NÃO criou constraint |
| `docs/backlog/reconciliador-incoming-9-digito.md` | Proposta: 2+ fichas → preferir a da conversa mais recente |

---

## 13. Perguntas em aberto

1. O runtime de **prod** (AWS Tozi) contém `56f7db0c6` (variants) e os overrides Enterprise `374d2258c`/`ac93290c9`? O deploy de 29/05 veio de `producao` (contém o commit), mas o redeploy “rollout” de 08/06 dropou código off-git — vale `git diff` real contra o servidor (fora do escopo deste mapeamento, sem SSH).
2. O patch cirúrgico do `DisparoLeadJob` (frente 1) já foi aplicado em prod? O STATE diz que estava pendente de aval.
3. Quando o hook Meta Lead Ads apontar pra inbox 91 (Cloud), o `source_id_for` com `+` vai recriar a classe de bug — corrigir antes do switch (usar `resolved_source_id` igual ao disparo)?
4. Vale unificar o `set_conversation` do incoming com o `ConversationBuilder#find_contact_conversation_in_inbox` (escopo por contato) pra fechar o furo das 2 fichas de uma vez?
5. A AutomationRule #53 (“iniciar zerado” em `conversation_opened`) continua ativa? Com a IA orquestradora assumindo triagem/atribuição, ela conflita diretamente.
