# Mapeamento — Integração WhatsApp Cloud API (envio + regras Meta)

> Área: whatsapp-cloud · Repo: `C:/Users/paulo/Workspaces/chatspx` · Branch: `paulao` · Data: 2026-06-10
> Tudo abaixo foi verificado por leitura direta do código local (app/ e enterprise/). Referências em `arquivo:linha`.

---

## 1. Arquitetura de envio (pipeline completo)

### 1.1 Cadeia de envio

```
Message (outgoing) criada
  └─ SendReplyJob (app/jobs/send_reply_job.rb:11,29)
       └─ Whatsapp::SendOnWhatsappService (app/services/whatsapp/send_on_whatsapp_service.rb)
            ├─ perform_reply (linha 8): decide TEMPLATE vs SESSÃO
            │    should_send_template_message = template_params.present? || !message.conversation.can_reply?
            ├─ send_template_message (17-38) → Whatsapp::TemplateProcessorService → channel.send_template
            └─ send_session_message (40-43) → channel.send_message
```

- `Base::SendOnChannelService` (app/services/base/send_on_channel_service.rb:13-19) filtra: só `outgoing?` ou `template?`, nunca `private?`, nunca mensagem que já tem `source_id` (anti-loop, linhas 42-50).
- `Channel::Whatsapp` (app/models/channel/whatsapp.rb:43-49) escolhe o provider: `whatsapp_cloud` → `Whatsapp::Providers::WhatsappCloudService`; senão 360Dialog. Delegates em 57-62: `send_message`, `send_template`, `sync_templates`, `media_url`, `api_headers`, `send_typing_indicator`.
- **Não há override Enterprise** de `SendOnWhatsappService`, `TemplateProcessorService`, `MessageWindowService` nem `WhatsappCloudService` (grep em `enterprise/` = zero matches). O Enterprise só toca: `Enterprise::Messages::MessageBuilder` (apenas `message_type` p/ Channel::Voice — enterprise/app/builders/enterprise/messages/message_builder.rb:4-8) e `Enterprise::Channelable` (suprime audit log quando a única mudança é `message_templates_last_updated` — enterprise/app/models/enterprise/channelable.rb:37-43).

### 1.2 WhatsappCloudService (app/services/whatsapp/providers/whatsapp_cloud_service.rb)

- `send_message` (2-20): roteia por tipo — location (147-169), contacts (176-199), attachment (201-222: image/audio/video viram o próprio tipo, resto vira `document`; caption = `message.outgoing_content`; attachment vai por **link público** `attachment.download_url`), input_select → interactive (275-291, botões ≤3 / lista >3 via base_service:91-111), texto (129-143).
- `send_template` (22-40): POST `{phone_id_path}/messages` com `type: 'template'` e `template_body_parameters` (229-264): `name`, `language {policy: 'deterministic', code}`, `components` = `template_info[:parameters] || []`.
- Reply-to nativo: `whatsapp_reply_context` (266-273) — usa `content_attributes[:in_reply_to_external_id]` como `context.message_id`.
- **Versões da Graph API misturadas (gotcha):** mensagens/template = **v13.0** (`phone_id_path`, 121-123); sync de templates do WABA = **v14.0** (`business_account_path`, 125-127); typing indicator = **v21.0 hardcoded** (94-108, porque v13 não suporta `typing_indicator`); `TemplateManagementService` = **v22.0**; `HealthService` = `WHATSAPP_API_VERSION` default **v22.0**. Há um TODO no código (linha 120) para unificar.
- Base URL configurável: `WHATSAPP_CLOUD_BASE_URL` (default `https://graph.facebook.com`, linha 116-118).

### 1.3 Resposta da Meta e erros (process_response)

`Whatsapp::Providers::BaseService` (app/services/whatsapp/providers/base_service.rb):
- `process_response` (40-48): sucesso → retorna `parsed_response['messages'].first['id']` (vira `message.source_id` em send_on_whatsapp_service.rb:37,42). Falha → `handle_error`.
- `handle_error` (50-61): loga o body, e **se** `message` presente: `message.external_error = error_message(response)` + `message.status = :failed` + save. `error_message` no cloud service (224-227) = `response.parsed_response.dig('error', 'message')` — o texto da Meta (que costuma embutir `(#131026)` etc. no próprio texto).
- **Nenhuma exceção é levantada** em falha Meta: `SendReplyJob` tem `retry_on StandardError attempts: 5` (send_reply_job.rb:3), mas erro de negócio da Meta não dispara retry — a mensagem fica `failed` silenciosamente, visível só na UI (bolha vermelha) ou via query em `external_error`.
- No envio de campanha nativa (`Whatsapp::OneoffCampaignService#send_whatsapp_template_message`, app/services/whatsapp/oneoff_campaign_service.rb:83-88) `message` é `nil` → erro só vai pro log (handle_error retorna em `message.blank?`).

---

## 2. Janela de 24h — onde mora e o que acontece

### 2.1 Cálculo (backend, decisão local)

- `Conversation#can_reply?` (app/models/conversation.rb:165-167) → `Conversations::MessageWindowService` (app/services/conversations/message_window_service.rb).
- Para `Channel::Whatsapp` a janela é **fixa 24h** (`MESSAGING_WINDOW_24_HOURS`, linhas 2 e 27-28). Regra (34-38): `Time.current < last_incoming_message.created_at + 24h`; **sem nenhuma incoming → `can_reply? == false`** (linha 35) — caso típico de conversa criada por disparo que o lead nunca respondeu.
- `last_incoming_message` (67-69) = última `messages.incoming` da conversa.
- Channel::Api (WAHA) usa `additional_attributes['agent_reply_time_window']` do canal (40-44) — se vazio, **sem janela** (sempre pode).

### 2.2 Texto livre fora da janela: o que acontece de verdade

`Whatsapp::SendOnWhatsappService#perform_reply` (send_on_whatsapp_service.rb:8-15): se `!can_reply?`, **força o caminho de template mesmo sem `template_params`**. Aí `TemplateProcessorService.call` retorna `[nil,nil,nil,nil]` (template_processor_service.rb:4-8, `template_params.blank?`) e o serviço falha **localmente, sem chamar a Meta**:

```ruby
# send_on_whatsapp_service.rb:26-29
if name.blank?
  message.update!(status: :failed, external_error: 'Template not found or invalid template name')
  return
end
```

Ou seja: **validação local; o erro da Meta (#131047/131026 fora de janela) nem chega a acontecer** para texto livre. Consequência importante pra IA: mensagem de bot/agente criada sem `template_params` numa conversa fora da janela morre com esse erro genérico — é exatamente por isso que o follow-up fora da janela precisa ser HSM (`Spx::Tozi::FollowupHsmJob`, `ReactivationCadenceService`).

### 2.3 Como o front sabe (banner de janela expirada)

- `can_reply` é serializado em `app/views/api/v1/conversations/partials/_conversation.json.jbuilder:101` e no push websocket via `Conversations::EventDataPresenter#push_data` (app/presenters/conversations/event_data_presenter.rb:5).
- **ReplyBox** (app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue):
  - `isEditorDisabled` (604-610): WhatsApp/API + não-nota + `!can_reply` → editor desabilitado, placeholder `MESSAGING_RESTRICTED_WHATSAPP` (321-330).
  - `showWhatsappWindowExpired` (611-617): mesmo gatilho → renderiza `WhatsappWindowExpired.vue` (2195-2200) no lugar do composer pill (`useWaComposerBar` exclui o caso, 621-626).
- **WhatsappWindowExpired.vue** (components/widgets/conversation/WhatsappTemplates/WhatsappWindowExpired.vue) — componente do fork: título "janela expirada", **atalho com os 5 templates aprovados mais recentes** (`getFilteredWhatsAppTemplates`, linhas 23-33), botão "enviar template" (abre o modal TemplatesPicker) e botão "nota privada".
  - `getFilteredWhatsAppTemplates` (store/modules/inboxes.js:49-100): filtra `status == 'approved'`, exclui `AUTHENTICATION`, CSAT (`customer_satisfaction_survey*`) e componentes não suportados (LIST/PRODUCT/CATALOG/CALL_PERMISSION_REQUEST/HEADER LOCATION).
- **MessagesView.vue** (204-256): banner genérico de janela (`replyWindowBannerMessage` → i18n `CONVERSATION.TWILIO_WHATSAPP_CAN_REPLY`, link p/ política `REPLY_POLICY.WHATSAPP_CLOUD`, texto `24_HOURS_WINDOW`).
- **AIAssistantPanel.vue** (components-next/ai-assistant, 475-486): também consulta `can_reply === false` p/ saber que a janela expirou (comportamento do copilot).
- Os templates chegam no front pelo serializer da inbox: `app/views/api/v1/models/_inbox.json.jbuilder:134` (`json.message_templates resource.channel.try(:message_templates)`) — ou seja, o front lê o **cache JSONB** do canal, não a Graph API.

---

## 3. Envio de template com variáveis e header de imagem

### 3.1 Entrada de `template_params`

Três portas de entrada, todas convergindo em `message.additional_attributes['template_params']`:
1. **API REST** — POST `/messages` aceita `template_params` top-level (front monta em app/javascript/dashboard/api/inbox/message.js:14,45); o controller repassa `params` cru pro `Messages::MessageBuilder` (app/controllers/api/v1/accounts/conversations/messages_controller.rb:51).
2. **MessageBuilder** — `template_params` (app/builders/messages/message_builder.rb:124-126) injeta `additional_attributes.template_params` no `message_params` (148). É o caminho usado pelos jobs SPX (`DisparoLeadJob#send_hsm`, app/jobs/spx/tozi/disparo_lead_job.rb:149-164; `FollowupHsmJob`, app/jobs/spx/tozi/followup_hsm_job.rb:23-34) e pelo `ScheduledMessages::SendService:43` (coluna jsonb `template_params` da scheduled_message → `message_params[:template_params]` — cadência HSM fora da janela).
3. **Campanha nativa** — `campaign.template_params` direto no `OneoffCampaignService` (sem Message; **desativado** no fork: `Campaign#execute_campaign` p/ WhatsApp só loga — app/models/campaign.rb:66-76).

### 3.2 TemplateProcessorService (app/services/whatsapp/template_processor_service.rb)

- `call` → `[name, namespace, language, components]`. `namespace` só é usado pelo 360Dialog.
- `find_template` (21-27): procura no **cache local** `channel.message_templates` por `name` + `language` (case-insensitive) + **`status == 'approved'`**. `processed_templates_params` (29-38): **se o template não está no cache (não sincronizado/não aprovado) retorna `nil`** → componentes vazios → a Meta recebe template sem parâmetros → **erro `#132000` (number of parameters does not match)**. Este é o gotcha vivido em produção: criou template novo, disparou, #132000 até rodar `channel.sync_templates` (e na prática reiniciar o worker — ver §7 "questões em aberto").
- Conversão legado→enhanced: `Whatsapp::TemplateParameterConverterService` (template_parameter_converter_service.rb:17-34) aceita array posicional ou hash plano e converte pra `{'body' => {...}}`.
- Componentes (40-50): header, body, footer, buttons.
  - **Body** (79-94): cada valor vira `{type:'text', text:...}` posicional, ou `{type:'text', parameter_name:, text:}` quando `template['parameter_format'] == 'NAMED'`.
  - **Header de mídia** (52-77): formato esperado `processed_params['header'] = { 'media_url' => URL, 'media_type' => 'image'|'video'|'document', 'media_name' => opcional }`. `build_header_params` (59-73) detecta `media_url`+`media_type` e chama `PopulateTemplateParametersService#build_media_parameter` (populate_template_parameters_service.rb:33-40): sanitiza, normaliza com Addressable, valida http/https e ≤2000 chars, e monta `{type:'image', image:{link: url}}` (106-108) / video / document (com `filename`). **A Meta baixa a URL no momento do envio** — se a URL der 404 (caso real do `inq-mapa.jpeg` dropado do deploy), o envio falha. Header de **texto** também é suportado (chaves ≠ media_* viram `build_parameter`, linha 68-69).
  - **Botões** (108-125): `{type:'button', sub_type: 'url'|..., index, parameters:[...]}`; `copy_code` vira `coupon_code` com validação ≤15 chars (populate_template_parameters_service.rb:13-31). Botões quick-reply estáticos (caso Tozi) **não precisam** de parâmetros — não entram no payload.
  - Sanitização (135-140): remove `<>"'` e trunca em 1000 chars cada parâmetro.
- Exemplo real do fork (disparo inquilinos): `DisparoLeadJob#no_var_params` (disparo_lead_job.rb:166-175) monta `processed_params: {'header' => {'media_url' => INQ_IMAGE_URL, 'media_type' => 'image'}}` com corpo sem variável.

---

## 4. Gestão de templates (criar/listar/deletar/sincronizar)

### 4.1 TemplateManagementService (app/services/whatsapp/template_management_service.rb) — código do fork

- Graph API **v22.0** no WABA (`provider_config['business_account_id']` + `api_key`), 4 operações: `create` (30-43, valida categoria MARKETING/UTILITY/AUTHENTICATION, normaliza nome lowercase/underscore 71-74), `list` (45-50), `status` (52-62), `delete` (64-67).
- Exposto via REST: `resources :message_templates` aninhado em inboxes (config/routes.rb:311) → `Api::V1::Accounts::InboxMessageTemplatesController` (index/create/destroy; valida que o canal é Cloud com `business_account_id`, controller:53-58; components passam por `to_unsafe_h` porque a estrutura Graph é livre, 68-73).
- **Gotchas operacionais conhecidos (do STATE, confirmados na operação):** o `api_key` da inbox 91 cria mas **não deleta** (#100 permission — delete só no WhatsApp Manager); nome de template deletado fica travado ~4 semanas (subcode 2388023); corpo não pode começar/terminar com variável (2388299).

### 4.2 Cache e sync (Channel::Whatsapp)

- Cache: colunas `message_templates` (jsonb) + `message_templates_last_updated` (schema em app/models/channel/whatsapp.rb:6-7).
- `sync_templates` (whatsapp_cloud_service.rb:42-47): marca `message_templates_last_updated` ANTES (via `mark_message_templates_updated`, channel/whatsapp.rb:51-55, update_column p/ não disparar validação) e pagina `{business_account_path}/message_templates` (49-58) até esgotar `paging.next`; só atualiza o jsonb se veio algo.
- Disparo automático: `Channels::Whatsapp::TemplatesSyncSchedulerJob` (app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb) pega canais com sync **> 3h** atrás (prioriza nunca-sincronizados), limitado por `Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT`, e agenda `TemplatesSyncJob` por canal. O scheduler é chamado por `TriggerScheduledItemsJob` (app/jobs/trigger_scheduled_items_job.rb:21), que roda via cron `config/schedule.yml:13`.
- Disparo manual: `POST /api/v1/accounts/:id/inboxes/:id/sync_templates` (routes.rb:298 → inboxes_controller.rb:77-85) e também `after_create :sync_templates` no canal (channel/whatsapp.rb:35).
- `validate_provider_config?` (whatsapp_cloud_service.rb:64-67) = GET nos templates do WABA (usado na validação do model, channel/whatsapp.rb:33,77-79).

---

## 5. Typing indicator e read receipt (código do fork)

- `WhatsappCloudService#send_typing_indicator(source_id, show_typing = true)` (whatsapp_cloud_service.rb:90-108): POST **v21.0** `{phone_number_id}/messages` com `{status:'read', message_id: source_id}` + `typing_indicator:{type:'text'}` quando `show_typing` (true = digitando ~25s; false = só tique azul). Best-effort: rescue total, nunca levanta. No-op no `BaseService` (base_service.rb:30-34) — outros providers ignoram. Delegate no canal (channel/whatsapp.rb:62).
- **Quem chama (pipeline Captain/IA):**
  - `Enterprise::MessageTemplates::HookExecutionService#mark_customer_message_read` (enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:86-93): tique azul imediato (show_typing=false) quando a mensagem do cliente passa no router, antes do debounce (73-81).
  - `Captain::Conversation::ResponseBuilderJob#trigger_typing_indicator` (enterprise/app/jobs/captain/conversation/response_builder_job.rb:219-230): rajada de "digitando" **antes de cada chunk** do humanizer (205-217), com delay proporcional ao tamanho (`humanizer_typing_delay`, 232-241: 45ms/char, piso 1,5s, teto 7s) — exige o `source_id` da última incoming (a Meta ancora o typing numa mensagem do cliente).

---

## 6. Webhook de entrada e de status (sent/delivered/read/failed)

### 6.1 Roteamento

- `GET/POST /webhooks/whatsapp/:phone_number` → `Webhooks::WhatsappController` (app/controllers/webhooks/whatsapp_controller.rb): GET = verify token por canal (`provider_config['webhook_verify_token']`, 17-21); POST = rejeita números no kill-switch global `INACTIVE_WHATSAPP_NUMBERS` (GlobalConfig, 23-32) e enfileira `Webhooks::WhatsappEventsJob`.
- `WhatsappEventsJob` (app/jobs/webhooks/whatsapp_events_job.rb): resolve o canal pelo payload (`display_phone_number` + valida `phone_number_id`, 95-101) ou pela URL; ignora canal inativo/reauth/conta suspensa (72-78); suporta **echo SMB** (`smb_message_echoes`, coexistência com o app WhatsApp Business, 53-59) → `IncomingMessageWhatsappCloudService` com `outgoing_echo: true`.

### 6.2 Status de mensagem (atualização da Message)

`Whatsapp::IncomingMessageBaseService` (app/services/whatsapp/incoming_message_base_service.rb):
- `perform` (9-17): payload com `statuses` → `process_statuses`; com `messages` → `process_messages`.
- `process_statuses` (47-53): localiza a Message por `source_id` (`statuses.first[:id]` — **só o primeiro status do array**) e:

```ruby
# incoming_message_base_service.rb:55-62
def update_message_with_status(message, status)
  message.status = status[:status]            # sent/delivered/read/failed (enum em message.rb:107)
  if status[:status] == 'failed' && status[:errors].present?
    error = status[:errors]&.first
    message.external_error = "#{error[:code]}: #{error[:title]}"   # ex.: "131026: Message undeliverable"
  end
  message.save!
end
```

- É **daqui** que vem o formato `"<código>: <título>"` que a tela de campanha parseia (`WhatsAppCampaignDetail.vue:23` conhece `131026/130472/131049/outro`; i18n pt_BR/en campaign.json:178-180; `campaigns_controller#stats` agrega por regex `\A\d+`). `external_error` vive em `content_attributes` (store accessor, app/models/message.rb:113-117).
- Sem guarda de monotonicidade: se um `delivered` atrasado chegar depois do `read`, o status **regride** (sem comparação de ordem).
- Front: `Message.vue` (components-next/message/Message.vue:523-524, 774) mostra o erro quando `status === 'failed'` + `contentAttributes.externalError`.

### 6.3 Mensagens de entrada (contexto da janela e do 9º dígito)

- `process_messages` (26-45): dedup por `source_id` + lock Redis (`Whatsapp::MessageDedupLock`); `set_contact_from_message` (112-129) resolve o wa_id via `processed_waid` → **`Whatsapp::PhoneNumberNormalizationService#normalize_and_find_contact_by_provider`** (incoming_message_service_helpers.rb:50-52 → phone_number_normalization_service.rb:14-31): gera variantes BR 12d/13d (`BrazilPhoneNormalizer#variants`, phone_normalizers/brazil_phone_normalizer.rb:24-30) e **reusa a ContactInbox existente em qualquer variante** — é o mecanismo que o `DisparoLeadJob#resolved_source_id` (disparo_lead_job.rb:112-116) passou a usar no fix das fichas duplicadas (commit `11b913531`, ainda não deployado na AWS).
- `set_conversation` (131-142): com `inbox.lock_to_single_conversation` (caso da inbox 91) reusa **a última conversa** do contato (mesmo resolvida); cria mensagem incoming → reseta a janela de 24h (porque `last_incoming_message` muda).
- Incoming cria a Message com `status: :sent` (linha 184); echo cria como `:delivered` pra não disparar SendReplyJob (183-184).

---

## 7. Erros Meta comuns — onde aparecem

| Código | Significado | Onde aparece no sistema |
|---|---|---|
| `131026` | Número sem WhatsApp / undeliverable | Webhook de **status failed** → `external_error = "131026: ..."` (incoming_message_base_service.rb:59). Não no envio síncrono (o POST retorna 200 e falha depois). |
| `130472` / `131049` | Pacing / limite de marketing da Meta (per-user marketing limit; agressivo em número YELLOW) | Idem — status failed via webhook. |
| `132000` | Number of parameters mismatch | **Resposta síncrona** do POST `/messages` → `handle_error` → `external_error` = texto da Meta (base_service.rb:50-61). Causa típica no fork: template não sincronizado/aprovado no cache → componentes vazios (template_processor_service.rb:29-38). |
| `(#100)` permission | Token sem permissão de management | Retorno do `TemplateManagementService#delete` (response_body no resultado). |
| Local: `'Template not found or invalid template name'` | Texto livre fora da janela (sem template_params) ou nome inválido | Gerado **localmente** em send_on_whatsapp_service.rb:26-29, sem chamar a Meta. |

Não existe **nenhuma** tabela/constante de códigos Meta no backend — a classificação por código só existe no front da tela de campanha e nos scripts de relatório (`scripts/spx/tozi/report_gen.py:89-90`).

---

## 8. Saúde do número (quality rating)

- `Whatsapp::HealthService` (app/services/whatsapp/health_service.rb): GET `graph.facebook.com/{v22.0}/{phone_number_id}` com fields `quality_rating, messaging_limit_tier, throughput, name_status, account_mode, code_verification_status, webhook_configuration, platform_type...` (40-56). Versão configurável via GlobalConfig `WHATSAPP_API_VERSION`.
- Exposto em `GET /api/v1/accounts/:id/inboxes/:id/health` (routes.rb:299 → inboxes_controller.rb:87-93). **On-demand apenas** — não há job periódico, não persiste histórico, não alerta quando degrada GREEN→YELLOW→RED.
- UI: `AccountHealth.vue` (routes/dashboard/settings/inbox/components/AccountHealth.vue) nas configurações da inbox — `QUALITY_COLORS` GREEN/YELLOW/RED (23-28), tier, modo, botão "register webhook".
- `WebhookSetupService` (app/services/whatsapp/webhook_setup_service.rb:103-118) usa o health pra detectar número não-provisionado (platform_type/throughput `NOT_APPLICABLE`) e registrar com PIN (33-56).

---

## 9. Outras peças relevantes

- **Bloqueio "número não tem WhatsApp" (pré-envio):** `Messages::MessageBuilder#validate_whatsapp_contact!` (message_builder.rb:151-163) levanta erro se `contact.custom_attributes['whatsapp_number_exists'] == false` (vale p/ Channel::Whatsapp, Twilio-whatsapp e Channel::Api). O front espelha: `ReplyBox.shouldBlockWhatsappSend` (ReplyBox.vue:263-272) e o controller corta antes (`whatsapp_number_invalid_for_outgoing?`, messages_controller.rb:48). *Quem escreve esse custom_attribute é o fluxo WAHA (fora do escopo desta área).* 
- **Blaster nativo de campanha desativado:** `Campaign#execute_campaign` p/ WhatsApp só loga (campaign.rb:66-76) — disparo é 100% via `Spx::Tozi::DisparoLeadJob` (pacing manual de ~5s feito pelo orquestrador externo via `Sidekiq::ScheduledSet`). O `Whatsapp::OneoffCampaignService` segue no código (sem pacing: loop direto em `process_audience`, oneoff_campaign_service.rb:64-71) mas inalcançável.
- **Copilot tool `send_template`:** `Captain::Tools::Copilot::SendTemplateService` (enterprise/app/services/captain/tools/copilot/send_template_service.rb:17-20) monta `params = { ..., additional_attributes: { template_params: ... } }` e chama o MessageBuilder — **mas o MessageBuilder só lê `@params[:template_params]` top-level** (message_builder.rb:124-126) e ignora `@params[:additional_attributes]`. Resultado provável: a mensagem é criada **sem** template_params e com `content: nil` → dentro da janela vira sessão com corpo nulo; fora da janela falha local. **Bug aparente — a tool de template do copilot não envia template.**
- **ScheduledMessages como ponte HSM:** migração `db/migrate/20260529120000_add_template_params_to_scheduled_messages.rb` + `ScheduledMessages::SendService:40-44` — agendamento de HSM determinístico (cadência fora da janela), cancelável (status pending/cancelled).
- **Echo SMB (coexistência):** mensagens enviadas pelo celular/app WhatsApp Business entram como outgoing echo (whatsapp_events_job.rb:53-59; incoming_message_base_service.rb:97-110,182-184) — o painel enxerga o que o time manda por fora.

---

## 10. Lacunas e riscos (resumo)

1. **Falha de envio é silenciosa**: erro Meta não levanta exceção, não notifica, não reagenda — só `message.failed` + `external_error`. Sem listener/telemetria de `131026/130472` (a classificação existe só no front de campanha).
2. **Status webhook processa só `statuses.first`** (incoming_message_base_service.rb:48-50) — payload com múltiplos statuses perde os demais. Mesmo padrão em `messages.first`.
3. **Regressão de status**: `read` → `delivered` atrasado sobrescreve (sem guarda de ordem).
4. **Texto livre fora da janela falha com erro genérico** (`Template not found...`) — qualquer produtor de mensagem (Captain incluso: `ResponseBuilderJob#create_outgoing_message` não passa template_params, response_builder_job.rb:247-259) que escreva numa conversa sem incoming <24h gera failed local. A IA orquestradora PRECISA checar `can_reply?` antes de mandar texto.
5. **Cache de templates com até 3h de atraso** (scheduler) + dependência de `status='approved'` no cache → `#132000` ou componentes ignorados se disparar logo após aprovação sem `sync_templates` manual. (O gotcha operacional inclui restart do worker; no código o `find_template` lê o jsonb do banco a cada job — a necessidade de restart sugere processo segurando objeto `channel` antigo; não há memoização de templates no código, ver questão em aberto.)
6. **Quality rating sem monitoramento contínuo** — health é só endpoint on-demand; nada impede um disparo de continuar com número RED.
7. **Bug aparente no copilot `send_template`** (template_params em additional_attributes não é lido pelo MessageBuilder).
8. **Versões Graph API fragmentadas** (v13/v14/v21/v22) — risco de deprecação da v13 nas mensagens.
9. **Header de imagem por link**: a Meta busca a URL no envio — asset fora do ar = falha do disparo (caso real `inq-mapa.jpeg` 404 pós-deploy).
10. **`validate_provider_config` roda em toda validação do model** (channel/whatsapp.rb:33) — chamada HTTP síncrona à Meta em qualquer `update` do canal.

---

## 11. Pontos de plug pra IA orquestradora

- **Decisão janela 24h**: `conversation.can_reply?` (conversation.rb:165) — gate programático HSM × sessão; mesmo serviço (`Conversations::MessageWindowService`) pode ser consultado pra calcular *quanto* falta da janela (last_incoming_message + 24h).
- **Envio de HSM programático**: criar Message via `Messages::MessageBuilder` com `template_params` top-level (padrão DisparoLeadJob/FollowupHsmJob) — funciona de qualquer job/serviço; suporta corpo com variáveis, header de imagem e NAMED params.
- **HSM agendado/cancelável**: `ScheduledMessage` com `template_params` jsonb + `ScheduledMessages::SendService` — base pronta pra cadência de follow-up fora da janela com cancel-on-reply.
- **Eventos de entrega**: o webhook de status atualiza a Message (`message.save!` dispara callbacks/`MESSAGE_UPDATED`) — listener Wisper pode reagir a `failed`(131026 → marcar contato sem WhatsApp; 130472/131049 → backoff do pacing) e a `read` (sinal de engajamento p/ priorizar follow-up).
- **Gate de saúde**: `Whatsapp::HealthService#fetch_health_status` (ou `GET /inboxes/:id/health`) — orquestrador deve consultar `quality_rating`/`messaging_limit_tier` antes de cada lote e pausar em YELLOW/RED.
- **Templates code-first**: `Whatsapp::TemplateManagementService` + REST `inboxes/:id/message_templates` (create/list/delete) + `POST /inboxes/:id/sync_templates` — ciclo completo criar→aprovar→sincronizar→usar sem WhatsApp Manager.
- **Presença humana**: `channel.send_typing_indicator(source_id, show_typing)` — read receipt + digitando, já integrado ao pipeline Captain (HookExecutionService/ResponseBuilderJob).
- **Dedup de identidade (9º dígito)**: `Whatsapp::PhoneNumberNormalizationService#normalize_and_find_contact_by_provider` — TODO produtor de conversa outbound deve usar (como o fix do DisparoLeadJob) pra não recriar a duplicidade ficha/conversa.
- **Kill-switch**: GlobalConfig `INACTIVE_WHATSAPP_NUMBERS` corta o webhook por número (whatsapp_controller.rb:23-32).

## 12. Questões em aberto

1. Quem grava `contact.custom_attributes['whatsapp_number_exists']`? (consumido em message_builder.rb:160 e ReplyBox; produtor parece estar no fluxo WAHA — confirmar antes de reusar como sinal universal de "número morto" e alimentá-lo com os `131026` do Cloud.)
2. Por que o gotcha operacional exigiu **restart do worker** após `sync_templates`, se `find_template` lê `channel.message_templates` do banco a cada job? (Hipótese: instância `Channel::Whatsapp` memoizada num processo longo do Sidekiq segurando o jsonb antigo; não há cache explícito no código.)
3. O bug do copilot `send_template` (additional_attributes ignorado) está em uso real? Se sim, nunca funcionou ou houve regressão no MessageBuilder?
4. A Meta pode agrupar múltiplos `statuses` num payload? Se sim, o `statuses.first` perde atualizações (impacto direto nas métricas de campanha).
5. Não há tratamento da notificação de webhook `message_template_status_update` (aprovação/rejeição de template em tempo real) — hoje a aprovação só aparece via sync de 3h ou manual. Vale assinar esse field no app Meta?
