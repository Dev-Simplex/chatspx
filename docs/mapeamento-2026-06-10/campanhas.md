# Mapeamento — Módulo de Campanhas (SPX/chatspx, branch paulao)

> Mapeado em 2026-06-10, por leitura direta do código local. Todas as referências são `arquivo:linha` do repo `C:/Users/paulo/Workspaces/chatspx`.

---

## 1. Visão geral

O módulo de campanhas do SPX hoje é um **híbrido de três camadas**:

1. **Esqueleto nativo do Chatwoot** (model `Campaign`, scheduler, jobs, services de envio) — mantido, mas com o **blaster WhatsApp neutralizado de propósito**.
2. **Motor próprio de disparo SPX** (`app/jobs/spx/tozi/`) — quem realmente envia: pacing, round-robin de corretores, rotação de templates HSM, dedup de telefone.
3. **Camada de visualização ancorada** — uma `Campaign` criada já `completed` serve só de "âncora" agregadora; as conversas criadas pelo motor recebem `campaign_id` e um endpoint `stats` agrega tudo numa tela read-only (`WhatsAppCampaignDetail.vue`).

Não existe **nenhum override Enterprise** do model, controller ou policy de Campaign (busca por `Campaign` em `enterprise/` só retorna usos no Captain — ver §8).

---

## 2. Model `Campaign` e a desativação do blaster nativo

**Arquivo:** `app/models/campaign.rb`

- Schema (annotation linhas 1–31): `audience` jsonb, `campaign_status` enum (`active: 0, completed: 1`, linha 50), `campaign_type` enum (`ongoing: 0, one_off: 1`, linha 48), `message` (obrigatório), `scheduled_at`, `template_params` jsonb (adicionado em `db/migrate/20250709102213_add_template_params_to_campaigns.rb`), `trigger_rules`, `sender_id`, `display_id` (gerado por DB trigger, linhas 132–134).
- `has_many :conversations, dependent: :nullify` (linha 52) — é por aqui que a âncora agrega.
- Tipos de inbox suportados na validação: `Website`, `Twilio SMS`, `Sms`, `Whatsapp` (linha 88). Para SMS/WhatsApp o tipo é forçado a `one_off` com `scheduled_at ||= Time.now.utc` (linhas 92–102).
- `prevent_completed_campaign_from_update` (linhas 127–129): campanha `completed` **não pode ser editada** — relevante porque a âncora Tozi é criada já completed (imutável pela UI).

### `trigger!` e `execute_campaign` (o ponto da desativação)

```ruby
# app/models/campaign.rb:57-79
def trigger!
  return unless one_off?
  return if completed?          # <- âncora completed NUNCA dispara
  execute_campaign
end

def execute_campaign
  case inbox.inbox_type
  when 'Twilio SMS' then Twilio::OneoffSmsCampaignService...
  when 'Sms'        then Sms::OneoffSmsCampaignService...
  when 'Whatsapp'
    # Disparo de WhatsApp e feito pelo orquestrador SPX (Spx::Tozi / DisparoLeadJob):
    # pacing, atribuicao round-robin por corretor e rotacao de template. O blaster
    # nativo (loop sem pacing) fica DESATIVADO para nao atropelar a operacao nem a
    # qualidade/tier do WABA. Campanhas WhatsApp existem so como ancora/registro.
    Rails.logger.warn("[Campaign ##{id}] WhatsApp one-off nativo desativado — envio via orquestrador SPX.")
  end
end
```

A desativação é **dupla proteção**: (a) o `case 'Whatsapp'` só loga (`campaign.rb:72-77`); (b) a âncora é criada `completed`, então `trigger!` retorna antes (`campaign.rb:59`) e o scheduler nem a seleciona (ver §3).

---

## 3. Fluxo nativo one_off original (como o Chatwoot upstream dispararia)

1. **Cron**: `config/schedule.yml:13-16` — `TriggerScheduledItemsJob` roda **a cada 5 minutos** (`*/5 * * * *`, fila `scheduled_jobs`).
2. **Seleção**: `app/jobs/trigger_scheduled_items_job.rb:6-9` — pega `Campaign.where(campaign_type: :one_off, campaign_status: :active).where(scheduled_at: 3.days.ago..Time.current)` e enfileira `Campaigns::TriggerOneoffCampaignJob` por campanha. (Note: o mesmo job-guarda-chuva também agenda o auto-resolve do Captain e o sync de templates WhatsApp, linhas 17–21.)
3. **Trigger**: `app/jobs/campaigns/trigger_oneoff_campaign_job.rb:4-8` — `campaign.trigger!`.
4. **Envio (neutralizado no fork)**: `Whatsapp::OneoffCampaignService` (`app/services/whatsapp/oneoff_campaign_service.rb`) seria chamado pelo `execute_campaign`.

### Anatomia do blaster nativo e POR QUE não serve

`app/services/whatsapp/oneoff_campaign_service.rb`:

- **Validações** (linhas 16–41): inbox WhatsApp + one_off, não-completed, `provider == 'whatsapp_cloud'` (linha 29), feature flag `whatsapp_campaign` habilitada na conta (linha 33; flag default `false` em `config/features.yml:182-184`).
- Marca `campaign.completed!` antes de processar (linha 7).
- **Audiência = labels**: `extract_audience_labels` (linhas 43–46) lê `campaign.audience` (jsonb `[{type: 'Label', id: ...}]`) e resolve para contatos via `contacts.tagged_with(labels, any: true)` (linha 65).
- **Loop síncrono sem pacing**: `contacts.each { |contact| process_contact(contact) }` (linha 68) — todos os envios disparados em sequência imediata, num único job. Para 1.500+ leads num número YELLOW isso é receita de RED na Meta.
- **Template único**: usa `campaign.template_params` fixo para todos (linhas 56–61, 73–88) — **zero rotação de copy** (decorrelação corretor↔template foi necessidade real da operação Tozi).
- **Envia "no vácuo"**: `channel.send_template(to, ...)` direto (linha 83) — **não cria Contact, ContactInbox, Conversation nem Message**. O HSM sai mas não existe transcrição no SPX, não há atribuição a corretor, não há `campaign_id` em conversa nenhuma, e a resposta do lead cai numa conversa nova órfã.
- **Sem atribuição round-robin**, sem dedup/normalização do 9º dígito, sem dry-run, sem retomada parcial.
- Erro só loga e segue (linhas 90–94).

Em contraste, o motor SPX (§4) cria toda a estrutura conversacional + atribuição, e o pacing é feito **fora do job**, no enfileiramento (`set(wait:)`).

### Fluxo `ongoing` (livechat) — intacto

Para registro: campanhas `ongoing` de Website continuam funcionando pelo caminho widget → `campaign_triggered` → `CampaignListener#campaign_triggered` (`app/listeners/campaign_listener.rb:2-15`) → `Campaigns::CampaignConversationBuilder` (`app/builders/campaigns/campaign_conversation_builder.rb`), que cria a conversa **com `campaign_id`** (linha 38) e a 1ª mensagem com `campaign_id` nos params (linhas 26–30). Esse builder recusa contato que já tem conversa (linha 12). É o "irmão nativo" do conceito que o SPX reusa: conversa carimbada com `campaign_id`.

---

## 4. O motor real: `Spx::Tozi::DisparoLeadJob` + rake + FollowupHsmJob

### `app/jobs/spx/tozi/disparo_lead_job.rb`

- `INBOX_ID = 91` **hardcoded** (linha 12); `LANGUAGE = 'pt_BR'` (linha 13).
- `PREVIEWS` (linhas 17–54): hash template→corpo que vira o `content` visível na transcrição (o envio real é HSM via `template_params`). Fallback `'Oi %<n>s!'` (linha 155) — causa do incidente "mensagens estranhas" quando um template novo não era adicionado aqui.
- `NO_BODY_VAR` (linhas 58–62): templates de inquilinos sem variável de corpo; `:image` liga header de imagem com `INQ_IMAGE_URL` (linha 56, asset `public/inq-mapa.jpeg` — hoje 404 em prod, dropado por deploy).
- **Assinatura**: `perform(nome:, telefone:, assignee_id:, template:, campaign_id: nil, dry_run: false)` (linha 64).
- **Fix anti-duplicata (commit `11b913531`, ainda não deployado)**:
  - `resolved_source_id` (linhas 112–116): usa `Whatsapp::PhoneNumberNormalizationService#normalize_and_find_contact_by_provider(waid, :cloud)` (`app/services/whatsapp/phone_number_normalization_service.rb:14`) pra reconciliar variantes 12d/13d do 9º dígito e **reusar a ficha que o WhatsApp já usa nos replies**.
  - `find_or_create_conversation` (linhas 121–143): honra o `lock_to_single` da inbox 91 — reusa a conversa não-resolvida mais recente (ou a última qualquer), reatribui ao corretor do disparo, seta `campaign_id` se vazio, `open!`; só cria nova se o contato nunca teve conversa. A criação grava `campaign_id` e `additional_attributes: { source: 'disparo_lancamento', template: }` (linhas 133–142).
- **Envio**: `send_hsm` (linhas 149–164) monta params com `content` (preview) + `template_params: { name, language, processed_params: { body: { '1' => nome, '2' => corretor } } }` e chama `Messages::MessageBuilder`. O `MessageBuilder` põe `template_params` em `message.additional_attributes['template_params']` (`app/builders/messages/message_builder.rb:124-126`) e o `Whatsapp::SendOnWhatsappService` lê de lá (`app/services/whatsapp/send_on_whatsapp_service.rb:45-46`) e envia como template (obrigatório fora da janela 24h, linha 9).
- Best-effort: `rescue` + log (linhas 90–92), não derruba a fila.

### Rake `spx:tozi:disparo` (`lib/tasks/spx_tozi.rake:142-212`)

O "orquestrador" de enfileiramento: lê CSV de audiência (`nome`, `telefone_e164`), aplica `limit`, espalha em `spread_min` (default 120 min → `step = spread/(total-1)`, linha 171), **round-robin de corretores** `DISPARO_BROKERS = [128, 126, 127, 131, 125]` (linha 131, `i % BROKERS.size`), **rotação de templates** `DISPARO_TEMPLATES` (linhas 134–138, `i % TEMPLATES.size` — a fórmula original casava corretor↔template; a decorrelação foi corrigida em scripts posteriores), `dry_run` default **true** (linha 149), e enfileira `DisparoLeadJob.set(wait: delay).perform_later` (linhas 184–186). Imprime plano completo (distribuição por corretor/template + amostra). **Gap**: a rake NÃO passa `campaign_id` (linha 184-186) — o carimbo de campanha nos disparos reais foi feito por scripts de console ad-hoc (`Downloads/disparo_*.rb`), não pela rake versionada.

Há também `spx:tozi:disparo_teste` (linhas 216–231, 1 HSM real imediato) e `spx:tozi:create_templates` (linhas 101–125, idempotente via `svc.list`).

### `app/jobs/spx/tozi/followup_hsm_job.rb`

Capacidade nova (re-engajamento): envia HSM `tozi_followup_lanc` **dentro da conversa existente** (`perform(conversation_id:, first:)`, linha 16), `open!` se resolvida (linha 21), mantém assignee, mesmo mecanismo `template_params` (linhas 23–34). Template e preview **hardcoded** (linhas 11–14) — só texto, sem suporte a header de imagem (motivo do bloqueio da 2ª leva de locação).

---

## 5. A âncora `completed` + endpoint de stats

### Conceito da âncora

Uma `Campaign` (#1 "Disparo Lançamento Tozi", #2 "Disparo Venda Tozi") é criada via console **já com `campaign_status: completed`**. Consequências:

- Scheduler ignora (só seleciona `active`, `trigger_scheduled_items_job.rb:6-7`).
- `trigger!` retorna em `return if completed?` (`campaign.rb:59`).
- UI não consegue editá-la (`prevent_completed_campaign_from_update`, `campaign.rb:127-129`).
- Serve apenas de **chave de agregação**: o motor grava `conversations.campaign_id` apontando pra ela.

### `campaigns_controller#stats` e `campaign_stats`

**Rota:** `config/routes.rb:125-129` — `resources :campaigns { member { get :stats } }` → `GET /api/v1/accounts/:account_id/campaigns/:id/stats` (`:id` = `display_id`, resolvido em `campaigns_controller.rb:31-33`).
**Policy:** `app/policies/campaign_policy.rb:22-24` — `stats?` exige `administrator` (corretores e secretária NÃO acessam; toda a policy de Campaign é admin-only, linhas 2–24).

**Agregador** `campaign_stats` (`app/controllers/api/v1/accounts/campaigns_controller.rb:43-86`), genérico por design ("vale pra qualquer campanha WhatsApp cujo orquestrador grave campaign_id nas conversas", comentário linhas 40–42):

- `conv_ids = @campaign.conversations.pluck(:id)` (linha 44) — via FK `conversations.campaign_id`.
- **Mensagens-template**: outgoing com `additional_attributes -> 'template_params' ->> 'name' IS NOT NULL` (linhas 47–48), agrupadas por `status` → `sent/delivered/read/failed`; `reached = sent+delivered+read` (linhas 49–54).
- **Respostas**: `replied` = nº de conversas distintas com incoming público não-vazio (linhas 56–57).
- **Distribuição por corretor**: group by `assignee_id` + nomes (linhas 59–62).
- **Falhas por código Meta**: regex `\A\d+` sobre `message.external_error` (linhas 64–66) — ex.: 131026 (sem WhatsApp), 130472/131049 (pacing).
- **Recentes**: 15 conversas por `last_activity_at` com última resposta do lead truncada em 80 chars (linhas 68–77).
- **Taxas**: `delivery_rate = reached/total`, `read_rate = read/reached` (linhas 82–83).

Limitações do agregador (relevantes pra IA):
- **Não quebra por template** — o nome do template está em cada `message.additional_attributes['template_params']['name']` e em `conversation.additional_attributes['template']`, mas o group-by é só por `status` e `assignee_id`. A "taxa de resposta qualificada por template" do teste A/B teve que ser medida por script de console.
- `failures` usa `find_each` em Ruby (linha 65) — ok pra milhares, não pra milhões.
- Sem série temporal (envios/respostas por hora), sem custo (pricing Meta), sem janela de atribuição de resposta.

### Plumbing do `campaign_id`

- `conversations.campaign_id` bigint + índice: `db/schema.rb:717,740`; `belongs_to :campaign, optional: true` em `app/models/conversation.rb:122`.
- `Messages::MessageBuilder#campaign_id` (`app/builders/messages/message_builder.rb:120-122`): param `campaign_id` → `message.additional_attributes['campaign_id']`; existe índice GIN dedicado `index_messages_on_additional_attributes_campaign_id` (`db/schema.rb:1107`). O motor SPX hoje **não** passa `campaign_id` no message_params (só na conversa) — o agregador não depende disso, mas o índice está disponível.
- **Efeito colateral importante**: `Conversation#determine_conversation_status` (`app/models/conversation.rb:332-343`) — conversa nova com `campaign` presente e `campaign.sender_id.nil?` + `inbox.active_bot?` + `pending_status_enabled?` → nasce **`pending`** ("bot-initiated, let bot handle it", linha 341-342). Com a Clara reconectada na inbox 91, **disparos futuros ancorados em campanha sem sender nasceriam pending** (o `DisparoLeadJob` força `status: 'open'` na criação, linha 139, mas o callback roda em `before_validation`? — na real `determine_conversation_status` é chamado na criação; como o job passa `status: 'open'` explícito, conferir precedência ao religar o bot. As âncoras Tozi não têm sender).

---

## 6. Frontend: viewer + card 📊 + tela de detalhe

### Lista (viewer sem criação)

- `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignsPage.vue` — comentário-decisão nas linhas 13–15: "Criacao nativa de campanha WhatsApp removida de proposito... Esta tela e VIEWER". Não passa `buttonLabel` ao layout; só lista (`CampaignList` com `show-view`, linhas 61–67), exclui (dialog, linhas 74–77) e navega pro detalhe (`goToDetail` → rota `campaigns_whatsapp_detail`, linhas 42–50).
- `CampaignLayout.vue` (`components-next/Campaigns/CampaignLayout.vue:39-46`): botão "+" só renderiza com `v-if="buttonLabel"` — é assim que o botão "Nova campanha WhatsApp" sumiu sem mexer nas telas SMS/LiveChat.
- Getter: `getWhatsAppCampaigns` (`store/modules/campaigns.js:43-46`) = one_off + inbox WHATSAPP.
- O formulário nativo de criação ainda existe no código (`components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignDialog.vue` + `WhatsAppCampaignForm.vue`) — órfão, não referenciado pela page.

### Card 📊

`components-next/Campaigns/Pages/CampaignPage/CampaignList.vue:13-16,39` repassa `showView`; `CampaignCard.vue:124-131` renderiza o botão `i-lucide-bar-chart-2` que emite `view`.

### Detalhe `WhatsAppCampaignDetail.vue`

`routes/dashboard/campaigns/pages/WhatsAppCampaignDetail.vue`:
- Rota: `campaigns.routes.js:64-73` (`whatsapp/:campaignId`, flag `WHATSAPP_CAMPAIGNS`, permissão `administrator` herdada do meta, linhas 10–13).
- Busca `CampaignsAPI.getStats(campaignId)` no `onMounted` (linhas 27–45). **Fetch único, sem polling** — pra acompanhar disparo ao vivo é F5.
- `api/campaigns.js:11-13`: `getStats` usa o **axios global** (comentário linhas 9–10; o `import axios` quebrava com 401 por não ter interceptor de auth).
- Renderiza: título + status + delivery/read rate (linhas 64–80), 5 `StatsCard` reaproveitados do módulo de agentes (`components-next/agents/StatsCard.vue` — Targeted/Delivered/Read/Replied/Failed, linhas 82–108), tabela por corretor (110–129), falhas por código Meta com labels i18n `CAMPAIGN.WHATSAPP.DETAIL.CODES` (130–154; códigos conhecidos no front: `KNOWN_CODES`, linha 23), e 15 conversas recentes (157–177). Sem link clicável da conversa pro inbox (a tabela é texto puro).
- i18n: `app/javascript/dashboard/i18n/locale/en/campaign.json:157-183` (keys DETAIL completas).
- Não mostra: breakdown por template, série temporal, custo, botões Pausar/Retomar (o "Painel de Disparos" com controle operacional segue pendente — pausar ainda é deletar jobs do `Sidekiq::ScheduledSet` via console).

---

## 7. Infra reaproveitável já existente (pra campanha virar módulo de verdade)

1. **Templates HSM via API**: `Whatsapp::TemplateManagementService` (`app/services/whatsapp/template_management_service.rb`) — create/list/status/delete na Graph API v22.0 com `business_account_id`+`api_key` do `provider_config`. Endpoint REST já exposto: `resources :message_templates, controller: 'inbox_message_templates'` (`config/routes.rb:311`; `app/controllers/api/v1/accounts/inbox_message_templates_controller.rb`). Sync de aprovação: `Channel::Whatsapp#sync_templates` + `Channels::Whatsapp::TemplatesSyncSchedulerJob` (agendado pelo mesmo `trigger_scheduled_items_job.rb:21`).
2. **Processamento de template**: `Whatsapp::TemplateProcessorService` (`app/services/whatsapp/template_processor_service.rb`) — body posicional/NAMED, header de mídia (`build_header_params`, linhas 59–73, formato `media_url`+`media_type`), botões. Gotcha: `find_template` (linhas 21–27) só acha template **sincronizado e APPROVED** no `channel.message_templates` — por isso o erro `#132000` até rodar `sync_templates` + restart do worker (cache).
3. **Mensagens agendadas com HSM**: `ScheduledMessage` (`app/models/scheduled_message.rb`, status pending/sent/failed/cancelled, attachments) + coluna `template_params` (`db/migrate/20260529120000_add_template_params_to_scheduled_messages.rb`) + `ScheduledMessages::SendService` que repassa `template_params` ao MessageBuilder (`app/services/scheduled_messages/send_service.rb:40-44`). **Isso já é um disparador HSM agendado, por conversa, com cancelamento** — base pronta pra cadência de follow-up de campanha.
4. **Cadência pronta (Tozi)**: `Spx::Tozi::ReactivationCadenceService` (`app/services/spx/tozi/reactivation_cadence_service.rb`) — agenda HSM 1d/3d/7d via ScheduledMessages, idempotente (linhas 72–79), cancel-on-reply via `Spx::Tozi::FunnelAutomationListener#message_created` (`app/listeners/spx/tozi/funnel_automation_listener.rb:24-37`), no-op fora de Cloud API (linhas 67–70).
5. **Funil/Kanban**: `FunnelPlacementService`, funil "Pré-Venda Tozi" (`lib/tasks/spx_tozi.rake:16-53`), listener que move card por evento (incoming→em_conversa, handoff→qualificado, `funnel_automation_listener.rb:24-52`).
6. **Normalização de telefone**: `Whatsapp::PhoneNumberNormalizationService` (variantes BR 12d/13d) + `Contacts::BrazilPhoneNormalizer` — a dupla que resolve o 9º dígito.
7. **Audiência por label** (nativo): `contacts.tagged_with(labels)` do `OneoffCampaignService:65` — mecanismo de audiência declarativa que pode ser reusado no lugar de CSV.

---

## 8. Integração Campanha ↔ Captain (IA) já existente

O Captain v2 **já enxerga a campanha** da conversa:

- `enterprise/app/services/captain/assistant/agent_runner_service.rb:21` — `CAMPAIGN_STATE_ATTRIBUTES = %i[id title message campaign_type description]`; linha 159: `state[:campaign] = slice_attrs(@conversation.campaign, ...) if @conversation.campaign`.
- `enterprise/app/models/concerns/agentable.rb:24` — o estado `campaign` entra no contexto do prompt.
- `enterprise/lib/captain/prompts/snippets/campaign.liquid` — snippet que renderiza "Campaign Context: title, type, description, Original Message Sent" no prompt do agente.

Ou seja: **se a Clara assumir uma conversa de disparo, ela já sabe qual campanha originou e qual copy foi enviada** — desde que `conversations.campaign_id` esteja gravado (o fix do `DisparoLeadJob` garante isso daqui pra frente) e que `campaign.description/message` da âncora contenham contexto útil (hoje a âncora tem `message` genérico).

Proteções já implementadas no fork (4 pontos espelhados):
- `enterprise/lib/captain/tools/handoff_tool.rb:67-69`
- `enterprise/app/jobs/captain/conversation/response_builder_job.rb:140-142`
- `enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb:95-97`
- `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:157-159`

Todos com a mesma regra: **conversa de campanha nunca recebe template OOO** (`return if conversation.campaign.present?`) — a campanha é o primeiro contato; mandar "estamos fora do horário" em cima do HSM mataria o lead.

---

## 9. O que falta pra "campanhas" virar módulo de verdade

### Backend
1. **Modelo de disparo persistido**: hoje o "estado" do disparo vive no Sidekiq ScheduledSet + scripts em `Downloads/`. Falta uma entidade (ex.: `CampaignDispatch`/`campaign_runs`) com: audiência resolvida (snapshot), pacing, templates da rotação, corretores do round-robin, contadores, status (`draft/running/paused/done`). A âncora `Campaign` pode continuar sendo a FK pública.
2. **Audiência estruturada**: CSV→ingestão hoje é script Python ad-hoc com dedup em 4 camadas. Reaproveitar `audience` jsonb do model (já existe) com tipos `Label` (nativo) + novo tipo `CsvUpload`/`Segment`, e mover a normalização (BrazilPhoneNormalizer + PhoneNumberNormalizationService + blacklist + dedup contra já-enviados via `additional_attributes->>'source'`) pra um service versionado.
3. **Generalizar o `DisparoLeadJob`**: tirar `INBOX_ID=91`, `PREVIEWS`, `NO_BODY_VAR` e `INQ_IMAGE_URL` hardcoded — o preview pode vir do corpo do template sincronizado (`channel.message_templates`) renderizando as variáveis, eliminando a classe de bug "template fora do PREVIEWS". Receber `inbox_id`, lista de corretores e templates como parâmetros (ou da entidade do item 1).
4. **Pausar/Retomar como API**: endpoints `POST /campaigns/:id/pause|resume` que manipulam os jobs (ou melhor: que o job consulte o status da entidade antes de enviar — pausa instantânea sem caçar jobs no ScheduledSet).
5. **`trigger!` plugável**: em vez de só logar, o `case 'Whatsapp'` pode despachar pro orquestrador SPX quando a campanha tiver a config nova (mantendo o log/no-op pra campanhas legadas) — aí `scheduled_at` volta a valer e "agendar disparo pra 17:30" deixa de ser script.
6. **Stats por template**: estender `campaign_stats` com group-by `additional_attributes -> 'template_params' ->> 'name'` (mesma fonte que já filtra) — é o dado do A/B que hoje exige console.
7. **Carimbo consistente**: rake/job sempre com `campaign_id` (a rake versionada não passa, `spx_tozi.rake:184-186`); opcionalmente gravar `campaign_id` também na message (o `MessageBuilder` já suporta e há índice GIN).

### Frontend
8. **Form de criação WhatsApp novo** (o `WhatsAppCampaignForm.vue` órfão pode ser base): seleção de inbox Cloud API, upload/seleção de audiência, multi-select de templates aprovados (via endpoint `message_templates` existente), multi-select de agentes pro round-robin, pacing (intervalo/spread), agendamento, dry-run com preview do plano (o que a rake imprime no console).
9. **Detalhe vivo**: polling/websocket no `WhatsAppCampaignDetail.vue`, barra de progresso (enviados/na fila), botões pausar/retomar, breakdown por template, link das conversas recentes pro chat.

### Riscos a tratar junto
10. **Interação com bot**: `handle_campaign_status` (`conversation.rb:340-343`) pode mandar conversa de campanha pra `pending` quando a Clara religar — decidir explicitamente quem cuida do lead recém-disparado (corretor humano hoje; IA orquestradora amanhã).
11. **Divergência prod↔repo**: o job em prod está atrás do repo (sem lógica inq) e assets/jobs off-git somem a cada redeploy da `rollout` — qualquer evolução do módulo pressupõe reconciliação antes.

---

## 10. Como a IA orquestradora consulta performance de campanha (hoje, sem código novo)

- **HTTP**: `GET /api/v1/accounts/6/campaigns/:display_id/stats` com token de admin → JSON completo (total, reached, read, replied, failed, delivery_rate, read_rate, distribution, failures, recent). É exatamente o que o front consome (`api/campaigns.js:11-13`).
- **Listagem**: `GET /api/v1/accounts/6/campaigns` (controller `index`, `campaigns_controller.rb:5-8`) pra descobrir as âncoras.
- **Por template (query direta, padrão pronto)**: replicar `campaign_stats` adicionando `.group("additional_attributes -> 'template_params' ->> 'name'")` sobre o mesmo escopo de mensagens — todos os dados necessários já estão gravados (`message.additional_attributes['template_params']['name']` + `message.status` + incoming por conversa). Em conversa: `conversation.additional_attributes['template']` guarda o template do disparo original (`disparo_lead_job.rb:141`).
- **No prompt do agente**: o snippet `campaign.liquid` já injeta título/copy da campanha quando a conversa tem `campaign_id` — a Clara pode adaptar abordagem por campanha sem tool nova.
- **Tool Captain futura**: uma `Captain::Tools::CampaignStatsTool` seria trivial — basta encapsular o `campaign_stats` (mover o agregador do controller pra um service público seria o passo 0).

---

## 11. Tabela-resumo de arquivos

| Papel | Arquivo |
|---|---|
| Model + desativação do blaster | `app/models/campaign.rb` (trigger! 57–62; execute_campaign 66–79) |
| Cron seletor | `config/schedule.yml:13-16` + `app/jobs/trigger_scheduled_items_job.rb:6-9` |
| Job de trigger | `app/jobs/campaigns/trigger_oneoff_campaign_job.rb` |
| Blaster nativo (neutralizado) | `app/services/whatsapp/oneoff_campaign_service.rb` |
| Endpoint stats | `app/controllers/api/v1/accounts/campaigns_controller.rb:12-14,43-86` |
| Policy | `app/policies/campaign_policy.rb` (stats? 22–24, tudo admin) |
| Rota stats | `config/routes.rb:125-129` |
| API client front | `app/javascript/dashboard/api/campaigns.js` (axios global 1, getStats 11–13) |
| Tela detalhe | `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignDetail.vue` |
| Lista viewer | `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignsPage.vue` |
| Card 📊 | `app/javascript/dashboard/components-next/Campaigns/CampaignCard/CampaignCard.vue:124-131` |
| Layout (botão removível) | `app/javascript/dashboard/components-next/Campaigns/CampaignLayout.vue:39-46` |
| Rotas front | `app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js:55-73` |
| FK conversas | `db/schema.rb:717,740`; `app/models/conversation.rb:122` |
| Status pending p/ campanha+bot | `app/models/conversation.rb:332-343` |
| Ponte template_params/campaign_id | `app/builders/messages/message_builder.rb:120-126,148` |
| Envio HSM | `app/services/whatsapp/send_on_whatsapp_service.rb:9,45-46` + `template_processor_service.rb` |
| Motor de disparo | `app/jobs/spx/tozi/disparo_lead_job.rb` |
| Follow-up HSM | `app/jobs/spx/tozi/followup_hsm_job.rb` |
| Rake orquestrador | `lib/tasks/spx_tozi.rake:142-212` |
| Cadência HSM agendada | `app/services/spx/tozi/reactivation_cadence_service.rb` + `app/services/scheduled_messages/send_service.rb:40-44` |
| Cancel-on-reply + funil | `app/listeners/spx/tozi/funnel_automation_listener.rb` |
| Gestão de templates | `app/services/whatsapp/template_management_service.rb` + `config/routes.rb:311` |
| Campanha no prompt do Captain | `enterprise/app/services/captain/assistant/agent_runner_service.rb:21,159` + `enterprise/app/models/concerns/agentable.rb:24` + `enterprise/lib/captain/prompts/snippets/campaign.liquid` |
| Guarda anti-OOO em campanha | `enterprise/lib/captain/tools/handoff_tool.rb:67-69` (+3 espelhos, §8) |
| Builder nativo ongoing | `app/builders/campaigns/campaign_conversation_builder.rb` + `app/listeners/campaign_listener.rb` |
| Feature flags | `config/features.yml:182-184`; `app/javascript/dashboard/featureFlags.js:9` |
