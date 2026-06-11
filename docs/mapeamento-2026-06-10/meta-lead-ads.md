# Mapeamento — Integração Meta Lead Ads (lead de formulário → conversa no SPX)

> Gerado em 2026-06-10, branch `paulao`. Baseado 100% em leitura do código local (referências arquivo:linha). Verificado nas duas árvores: **não existe nenhum override Enterprise** para esta integração (glob `enterprise/**/meta*lead*` vazio; grep `meta_lead_ads` só encontra arquivos em `app/`, `config/`, `lib/`).

---

## 1. Visão geral do fluxo

```
Meta (FB/IG Lead Ads)
  │  POST /webhooks/meta_lead_ads  (HMAC X-Hub-Signature-256)
  ▼
Webhooks::MetaLeadAdsController#process_payload          app/controllers/webhooks/meta_lead_ads_controller.rb:14
  │  SignatureVerifier.valid? → JSON.parse → enfileira
  ▼
Webhooks::MetaLeadAdsJob (queue :default)                app/jobs/webhooks/meta_lead_ads_job.rb:10
  │  por entry: HookFinder.for_page_id(entry['id'])
  │  por change leadgen: FetchLeadService (Graph API v22.0)
  ▼
Meta::LeadAds::CreateConversationService                 app/services/meta/lead_ads/create_conversation_service.rb:19
  │  normaliza phone → ContactInboxWithContactBuilder → Conversation.create!
  │  → Spx::Tozi::FunnelPlacementService ('novo_lead')
  │  → 1ª mensagem (texto livre via MessageBuilder) — SE !skip_initial_message e phone presente
  ▼
Conversa pending/open na inbox alvo, lead no Kanban "Novo Lead"
```

## 2. Rotas e verificação do webhook

- `config/routes.rb:670-671`:
  - `get 'webhooks/meta_lead_ads' → webhooks/meta_lead_ads#verify` (challenge de subscription)
  - `post 'webhooks/meta_lead_ads' → webhooks/meta_lead_ads#process_payload` (eventos leadgen)
- Controller (`app/controllers/webhooks/meta_lead_ads_controller.rb`):
  - `verify` (linhas 5-12): valida `hub.verify_token` via `Meta::LeadAds::TokenVerifier.valid?` e devolve `hub.challenge` em texto puro. 401 se inválido.
  - `process_payload` (linhas 14-32): pega `request.raw_post` cru, valida HMAC via `SignatureVerifier.valid?(raw_payload:, signature_header: request.headers['X-Hub-Signature-256'])`. Assinatura inválida → `head :unauthorized`. JSON inválido → `head :bad_request`. OK → `Webhooks::MetaLeadAdsJob.perform_later(payload)` e `head :ok` (responde rápido, processamento em background — padrão correto pra webhook Meta).
  - Herda de `ActionController::API` (sem CSRF, sem sessão).

### TokenVerifier — `app/services/meta/lead_ads/token_verifier.rb`
- Itera **todos** os `Integrations::Hook.where(app_id: 'meta_lead_ads', status: 'enabled')` da instância (linha 9, sem escopo de conta) e compara `settings['verify_token']` com `secure_compare` (linha 13). Token bate se **qualquer** hook ativo tiver o mesmo valor — suporta múltiplos apps Meta no mesmo SPX.

### SignatureVerifier — `app/services/meta/lead_ads/signature_verifier.rb`
- Mesmo padrão: itera todos os hooks ativos (linha 13), calcula `sha256=` + `OpenSSL::HMAC.hexdigest('SHA256', hook.settings['app_secret'], raw_payload)` (linha 17) e compara com `secure_compare` (linha 18). Retorna true no primeiro match. Multi-app por design; consequência: qualquer `app_secret` cadastrado valida qualquer payload da instância (a separação real acontece depois, no `HookFinder` por page_id).

## 3. Job de processamento — `app/jobs/webhooks/meta_lead_ads_job.rb`

- `perform(payload)` (linhas 13-28): para cada `entry`, `page_id = entry['id']` → `Meta::LeadAds::HookFinder.for_page_id(page_id)`; sem hook → log warn e `next`. Para cada `change` com `field == 'leadgen'` → `process_leadgen(change['value'], hook)`.
- `process_leadgen` (linhas 32-49): exige `leadgen_id`; chama `FetchLeadService.new(leadgen_id:, access_token: hook.settings['page_access_token']).perform`; depois `CreateConversationService.new(hook:, lead:).perform`. `rescue StandardError` → loga e **re-raise** (linha 48) → Sidekiq fará retry do job inteiro (ver riscos: criação de conversa não é idempotente).

### HookFinder — `app/services/meta/lead_ads/hook_finder.rb`
- `for_page_id(page_id)` (linhas 5-11): busca **global** (sem escopo de account) o primeiro hook ativo com `settings['page_id'].to_s == page_id.to_s`. Primeiro match vence — se duas contas cadastrarem a mesma página, comportamento ambíguo.

## 4. FetchLeadService — `app/services/meta/lead_ads/fetch_lead_service.rb`

- Graph API `GET https://graph.facebook.com/v22.0/{leadgen_id}` (linhas 26-29) com `fields = id,created_time,ad_id,ad_name,form_id,campaign_id,campaign_name,adset_id,adset_name,field_data,platform` (linha 8). Raise em resposta não-2xx (linha 31).
- Parse de `field_data` (linhas 38-64):
  - `normalize_key` (67-71): lowercase, translitera acentos, troca tudo que não é `[a-z0-9_]` por `_` — viabiliza forms com nomes custom PT-BR (`qual_seu_telefone?` → `qual_seu_telefone_`).
  - Match por **substring** contra hints (74-80): `PHONE_HINTS = %w[phone telefone celular whatsapp numero_de_telefone numero_telefone]`, `NAME_HINTS`, `EMAIL_HINTS`, `CITY_HINTS` (linhas 12-15).
  - `TEST_DUMMY_REGEX` (linha 18) filtra valores `<test lead: dummy data...>` do Lead Ads Testing Tool (vira `nil`, preservando a chave em `raw_fields`).
- Retorno: hash com `leadgen_id, created_time, ad_id/ad_name, adset_id/adset_name, form_id, campaign_id/campaign_name, platform, full_name, phone_number, email, city, raw_fields` (linhas 47-63). **Contexto de anúncio/campanha completo — ouro pra IA orquestradora rotear por origem.**

## 5. CreateConversationService — `app/services/meta/lead_ads/create_conversation_service.rb`

### 5.1 Normalização de telefone (linhas 56-63)
- Strip não-dígitos; 10-11 dígitos → prefixa `55`; formata `+digits`; passa por `Contacts::BrazilPhoneNormalizer.normalize` (mesma normalização "nossa" do `DisparoLeadJob#normalize_phone`, `app/jobs/spx/tozi/disparo_lead_job.rb:100-107`). Lead **sem** phone não aborta: cria conversa mesmo assim, sem 1ª mensagem (linhas 22-24, 30-32).

### 5.2 Contact + ContactInbox (linhas 65-109)
- `ContactInboxWithContactBuilder` com:
  - `contact_attributes.additional_attributes`: `source: 'meta_lead_ads'`, `leadgen_id`, `ad_id/ad_name`, `adset_id/adset_name`, `campaign_id/campaign_name`, `form_id`, `platform`, `city` (linhas 72-84) — rastreabilidade da origem no contato.
  - `source_id_for(phone)` (linhas 98-109):
    - Inbox WAHA (`Channel::Api` + `waha_session_name` presente — coluna em `inboxes`, `db/schema.rb:978`): `"#{digits}@c.us"` (JID).
    - Sem phone: `"meta_lead:#{leadgen_id}"` (fallback único).
    - **Qualquer outro canal (inclui `Channel::Whatsapp` Cloud API): retorna `phone` COM `+`** (linha 108).
- O builder (`app/builders/contact_inbox_with_contact_builder.rb:16-28`) reusa ContactInbox por `source_id` exato; senão reusa Contact por identifier/email/phone (com fallback `BrazilPhoneNormalizer`, linhas 108-118) e **cria ContactInbox novo** com o source_id informado.

### 5.3 Conversation (linhas 111-127)
- `Conversation.create!` com `additional_attributes: { source: 'meta_lead_ads', lead: {leadgen_id, ad_name, campaign_name, form_id, platform} }` (linhas 118-121).
- Status: `@inbox.pending_status_enabled? ? 'pending' : 'open'` (linha 126). Nota: `Conversation#pending_status_allowed_by_inbox` (`app/models/conversation.rb:324-330`) valida que `pending` só é permitido se a inbox tiver a flag — consistente. Diferente do `determine_conversation_status` nativo (`conversation.rb:337`, exige `active_bot?` E `pending_status_enabled?`), aqui basta a flag da inbox: **lead pode nascer `pending` mesmo sem bot ativo** → candidato a limbo invisível (mesma família do incidente de 02/06).

### 5.4 Funil (Kanban) — linhas 48-54
- `place_in_funnel`: `Spx::Tozi::FunnelPlacementService.new(conversation:, automation_type: 'novo_lead').perform` — chamado **sempre**, logo após o create.
- `FunnelPlacementService` (`app/services/spx/tozi/funnel_placement_service.rb`):
  - `find_funnel` (71-77): funil da account que cobre a inbox (`for_inbox`) E tem stage com `automation_type='novo_lead'` — só casa com o funil "Pré-Venda Tozi" (criado por `rake spx:tozi:setup_funnel`, automation_types em `funnel_placement_service.rb:16`). **No-op silencioso** se não existir (linhas 49-50) — não quebra outros tenants.
  - `perform` (48-64): `FunnelItem.find_or_initialize_by(conversation_id:, funnel_id:)` → seta stage → save. Idempotente. Rescue interno (não propaga).
- Movimentação posterior é dirigida por eventos: `Spx::Tozi::FunnelAutomationListener` (`app/listeners/spx/tozi/funnel_automation_listener.rb`) — incoming do lead em `novo_lead/aguardando_1a/em_silencio/frio` → `em_conversa` + cancela cadência (linhas 24-37); `assignee_changed` pra humano em estágio de pré-venda → `qualificado` (linhas 42-52). Registrado no `AsyncDispatcher` (`app/dispatchers/async_dispatcher.rb`).
- Backfill: `rake spx:tozi:backfill_funnel` consulta `additional_attributes->>'source' = 'meta_lead_ads'` (`lib/tasks/spx_tozi.rake:242`) — prova que esse marker é o identificador canônico de leads Meta.

### 5.5 Primeira mensagem (linhas 129-155)
- Gate duplo: phone presente E `skip_initial_message` falsy (`ActiveModel::Type::Boolean.cast` sobre `hook.settings['skip_initial_message']`, linhas 44-46).
- `create_initial_message`: `Messages::MessageBuilder.new(nil, conversation, content: rendered, message_type: 'outgoing', private: false, content_attributes: { meta_lead_ads_initial: true })` (linhas 133-140) — **texto livre**, sem `template_params`.
- Template Liquid (143-155): `hook.settings['initial_message_template']` ou `DEFAULT_TEMPLATE` PT-BR (linha 11); variáveis `full_name, first_name, ad_name, campaign_name, city, email, phone`.

## 6. Registro da integração — `config/integration/apps.yml:211-292`

- `hook_type: account`, `allow_multiple_hooks: true` (um hook por página Meta; linha 215-216). Sem `feature_flag`.
- `settings_json_schema` (217-235): obrigatórios `page_id, verify_token, app_secret, page_access_token, target_inbox_id`; opcionais `page_name, initial_message_template, skip_initial_message, enabled`; `additionalProperties: true` (**deixa espaço pra adicionar chaves novas — ex.: nome de template HSM — sem migração**).
- `settings_form_schema` (236-291): formulário declarativo renderizado pela UI genérica de integrações (`NewHook.vue`/`EditHook.vue` em `app/javascript/dashboard/routes/dashboard/settings/integrations/` — `EditHook.vue` monta o form a partir de `integration.settings_form_schema`, linhas 44-46). Não há componente Vue dedicado ao meta_lead_ads (grep no frontend = zero arquivos).
- `visible_properties: ['page_name', 'page_id', 'target_inbox_id', 'skip_initial_message']` (linha 292).
- i18n: `config/locales/pt_BR.yml:372-375` e `en.yml:384`.
- Modelo `Integrations::Hook` (`app/models/integrations/hook.rb`): `settings` é JSONB validado contra o `settings_json_schema` (linhas 92-96); `app_id` único por account **a menos que** `allow_multiple_hooks` (linha 32); enum `status: {disabled, enabled}` (linha 36). `access_token` (token interno do hook) é criptografado (linha 25), mas **`settings` JSONB não é** — `app_secret` e `page_access_token` ficam em claro no banco.

## 7. O GAP da 1ª mensagem em inbox Cloud API (Channel::Whatsapp)

### O que acontece hoje (cadeia exata, com referências)
1. `create_initial_message` cria Message outgoing **sem `template_params`** (`create_conversation_service.rb:133-140`).
2. `SendReplyJob` → `Whatsapp::SendOnWhatsappService#perform_reply` (`app/services/whatsapp/send_on_whatsapp_service.rb:8-15`): `should_send_template_message = template_params.present? || !message.conversation.can_reply?`.
3. `can_reply?` → `Conversations::MessageWindowService` (`app/services/conversations/message_window_service.rb:27-28`): `Channel::Whatsapp` → janela de 24h; `last_message_in_messaging_window?` retorna **false se não há incoming** (linha 35). Lead de formulário nunca mandou mensagem → `can_reply? == false`.
4. Logo cai em `send_template_message` com `template_params = nil` → `TemplateProcessorService.call` retorna `[nil, nil, nil, nil]` (`app/services/whatsapp/template_processor_service.rb:4-5`) → `name.blank?` → **`message.update!(status: :failed, external_error: 'Template not found or invalid template name')`** (`send_on_whatsapp_service.rb:26-28`).
- Resultado: a 1ª mensagem **nem chega a ser tentada na Meta** — falha localmente. O lead entra no funil mas não recebe nada ("lead morre"), exatamente como descrito no STATE (bloqueio do hook em prod).
- Em WAHA (`Channel::Api`) funciona porque a janela é configurável/ausente (`message_window_service.rb:40-44` — `agent_reply_time_window` em branco → `can_reply? == true`) e o envio é texto livre via WAHA.

### O padrão a copiar — `Spx::Tozi::DisparoLeadJob#send_hsm` (`app/jobs/spx/tozi/disparo_lead_job.rb:149-175`)
```ruby
params = {
  content: format(PREVIEWS.fetch(template, 'Oi %<n>s!'), n: first, a: agent), # espelho na transcrição
  content_type: :text, message_type: 'outgoing', private: false,
  template_params: {
    'name' => template, 'language' => LANGUAGE,                # 'pt_BR'
    'processed_params' => { 'body' => { '1' => first, '2' => agent } }
  }
}
Messages::MessageBuilder.new(nil, conversation, params.with_indifferent_access).perform
```
- `MessageBuilder#template_params` grava em `message.additional_attributes['template_params']` (`app/builders/messages/message_builder.rb:124-126`, merged na linha 148).
- `SendOnWhatsappService` lê de lá (linhas 45-47) e o `TemplateProcessorService` resolve o template **nos templates sincronizados do canal** (`channel.message_templates`, `template_processor_service.rb:21-27` — só `status=approved`). Gotcha documentado no STATE: exige `inbox.channel.sync_templates` + restart do worker (cache) após criar template novo.
- Header de imagem (se o template de abertura tiver): `processed_params['header'] = { 'media_url' => URL, 'media_type' => 'image' }` (`disparo_lead_job.rb:166-175` + `template_processor_service.rb:52-77`).

### Mudança mínima proposta (1ª-mensagem-como-HSM quando `inbox.channel_type == 'Channel::Whatsapp'`)
1. **Settings novos no hook** (apps.yml já tem `additionalProperties: true`): ex. `initial_template_name` (ex. `tozi_lead_abertura`, já citado no STATE como aprovado no WABA) e opcionalmente `initial_template_lang` (default `pt_BR`).
2. **No `create_initial_message`** (`create_conversation_service.rb:129-141`): branch — se a inbox é `Channel::Whatsapp` (ou, mais preciso, `!conversation.can_reply?` em canal com janela), montar `template_params` no padrão do DisparoLeadJob, com `content` = corpo renderizado (espelho da transcrição) e `processed_params.body` mapeando as variáveis do template ({{1}} = primeiro nome etc.). Senão, manter o caminho texto-livre atual (WAHA).
3. Pré-requisitos operacionais: template aprovado no WABA da inbox 91 + sincronizado (`Channel::Whatsapp#sync_templates` / `templates_sync_job`) + worker com cache renovado.

## 8. Estado operacional (segundo STATE.md, não verificável em código)

- Hook em produção PAULAO: `Integrations::Hook id=3`, Account 1, inbox alvo 1 (WAHA), `skip_initial_message=true` (modo teste). App Meta "SPX Lead Ads Tozi" (`1658426868710322`) em modo Live, page Tozi subscrita em `leadgen`.
- **Callback do app Meta ainda aponta pra PAULAO** (`paulo.chatspx.app`); o switch pra prod AWS (`tozi.chatspx.app/webhooks/meta_lead_ads`) está pendente e bloqueado pelo gap do HSM (item 7).
- E2E validado em 27/05 via Testing Tool (conversas 144-146 criadas; dummy data filtrada).

## 9. Gaps e riscos (consolidado)

1. **GAP HSM (bloqueador do go-live em prod):** 1ª mensagem texto-livre falha localmente em `Channel::Whatsapp` (cadeia do item 7). Lead entra no funil mas nunca recebe abertura.
2. **GAP source_id em Cloud API (mesma família do bug dos disparos):** `source_id_for` devolve `phone` **com `+`** pra inbox `Channel::Whatsapp` (`create_conversation_service.rb:108`), mas o inbound Cloud cria/busca ContactInbox por **wa_id só-dígitos** normalizado (`app/services/whatsapp/incoming_message_base_service.rb:116-122` + `incoming_message_service_helpers.rb:50-52` → `PhoneNumberNormalizationService`, que busca variantes **sem `+`**, `phone_number_normalization_service.rb:57-64`). Resultado previsto: lead criado pelo webhook ganha ficha `+5566...`; quando responde no WhatsApp, o reply cai em **ficha nova** (`5566...`) e portanto **conversa nova** (o `set_conversation` é escopado por contact_inbox, `incoming_message_base_service.rb:131-142`, mesmo com `lock_to_single_conversation`) → reply órfão + duplicata. O `DisparoLeadJob` já foi consertado com `resolved_source_id` (`disparo_lead_job.rb:112-116`); o `CreateConversationService` do Lead Ads **não** — precisa do mesmo patch antes de apontar o hook pra inbox 91. Soma-se a variante do 9º dígito.
3. **Sem idempotência por leadgen_id:** `Conversation.create!` incondicional (`create_conversation_service.rb:111-123`). Redelivery do webhook ou retry do Sidekiq (o job re-raise, `meta_lead_ads_job.rb:48`) cria conversas duplicadas (evidência: convs 144-146 do mesmo lead replay no STATE). O `leadgen_id` está salvo em `contact.additional_attributes` e `conversation.additional_attributes['lead']` mas nunca é consultado como dedup.
4. **Pending sem bot:** status `pending` depende só de `pending_status_enabled?` da inbox (linha 126) — sem Clara conectada, lead nasce invisível na aba "Abertas" (limbo conhecido). Com Clara conectada + whitelist, idem (incidente de 02/06).
5. **Hook lookup global:** `HookFinder`/`SignatureVerifier`/`TokenVerifier` iteram hooks de toda a instância sem escopo de conta; page_id duplicado entre contas = primeiro match vence.
6. **Segredos em claro:** `app_secret`/`page_access_token` em `settings` JSONB não criptografado (`hook.rb` só encripta `access_token`, linha 25).
7. **Acoplamento Tozi em código OSS genérico:** `place_in_funnel` chama `Spx::Tozi::FunnelPlacementService` hardcoded (`create_conversation_service.rb:50-54`). No-op pra outros tenants, mas a generalização multi-cliente exigirá extrair isso (config por hook ou listener).
8. **Zero specs:** `spec/**/*meta_lead*` não existe — fluxo crítico sem rede de testes.
9. **Lead sem telefone:** conversa criada com source_id `meta_lead:<id>`, sem 1ª mensagem e sem fluxo definido de follow-up manual (`create_conversation_service.rb:30-32`).

## 10. Pontos de plug pra IA orquestradora

- **Marker canônico:** `conversation.additional_attributes['source'] == 'meta_lead_ads'` (+ sub-hash `lead` com `leadgen_id/ad_name/campaign_name/form_id/platform`) — já usado pelo backfill (`spx_tozi.rake:242`). Orquestrador identifica e segmenta leads Meta por query.
- **Contexto de anúncio no contato:** `contact.additional_attributes` carrega `ad_id/ad_name/adset/campaign/form_id/platform/city` (`create_conversation_service.rb:72-84`) — permite à IA escolher persona/cenário/corretor pelo anúncio de origem.
- **Evento `conversation_created`:** disparado no create (`conversation.rb:345-347`) via dispatcher — um listener (padrão `FunnelAutomationListener`) pode fazer triagem/atribuição automática no nascimento do lead.
- **Funil como state machine legível/escrevível:** `FunnelPlacementService.move/current_type` (`funnel_placement_service.rb:22-32`) é a API interna de estágio; `FunnelAutomationListener` já reage a `message_created`/`assignee_changed`. A IA pode tanto ler o estágio quanto movê-lo.
- **Status `pending` como fila de triagem:** a conversa nasce pending (se a flag da inbox estiver on) — exatamente o estado que o Captain v2 consome; a IA orquestradora decide atribuir → `open`.
- **Hook settings como painel de controle remoto:** `skip_initial_message`, `initial_message_template` (e futuros `initial_template_name`) editáveis via API de integrações (`EditHook.vue` já existe; `additionalProperties: true` no schema) — a IA/Claude Code pode ligar/desligar modos sem deploy.
- **Ponto de inserção do HSM:** `create_initial_message` (`create_conversation_service.rb:129-141`) é o único lugar a mudar; o transporte (`MessageBuilder` → `SendOnWhatsappService` → `TemplateProcessorService`) já entende `template_params` fim-a-fim, provado pelo `DisparoLeadJob` e pelo `FollowupHsmJob`.
- **`content_attributes.meta_lead_ads_initial: true`** na 1ª mensagem (linha 139) — flag pra distinguir abertura automática de mensagens humanas em análises/decisões do orquestrador.

## 11. Perguntas em aberto

1. A inbox 91 em prod está com `pending_status_enabled=true`? Define se lead Meta nasce `pending` (limbo potencial) ou `open`.
2. Qual template de abertura usar e como parametrizar ({{1}} nome? corretor?) — `tozi_lead_abertura` consta como aprovado no STATE; confirmar status atual no WABA e variáveis.
3. O fix do source_id (item 9.2) deve reusar `Whatsapp::PhoneNumberNormalizationService` igual ao DisparoLeadJob — aplicar junto com o switch do callback ou antes?
4. HookFinder deveria ser escopado por conta (ou validar unicidade de page_id entre hooks)?
5. Lead sem telefone: descartar, criar tarefa pra secretária, ou tentar e-mail? Hoje fica conversa muda.
6. A atribuição do lead Meta (round-robin de corretor, como no disparo) deve acontecer no create (listener `conversation_created`) ou ficar com a IA de triagem?
